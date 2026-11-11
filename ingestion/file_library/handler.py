import requests, os, logging, re, time
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


TOKEN_URL = "https://keycloak.tp.entsoe.eu/realms/tp/protocol/openid-connect/token"
CLIENT_ID = "tp-fms-public"
TIMEOUT_SECONDS = 30
LIST_URL = "https://fms.tp.entsoe.eu/listFileMetadata"
TOP_LEVEL_FOLDER = "TP_export"

DATASET_FOLDERS = [
    "ActualTotalLoad_6.1.A_r3",                                         # Actual Total Load
    "AggregatedGenerationPerType_16.1.B_C_r3",                          # Generation Per Type
    "ActualGenerationOutputPerGenerationUnit_16.1.A_r3",                # Generation Per Unit
    "EnergyPrices_12.1.D_r3.1",                                         # Day-Ahead Energy Prices
    "PhysicalFlows_12.1.G_r3",                                          # Physical Flows
    "GenerationForecastsForWindAndSolar_14.1.D_r3",                     # Generation Forecasts for Wind and Solar
    "InstalledGenerationCapacityAggregated_14.1.A_r3",                  # Installed Generation Capacity
    "UnavailabilityOfProductionAndGenerationUnits_15.1.A_B_C_D_r3.1"    # Unavailability of Production and Generation Units
]
MAX_IDS_PER_DOWNLOAD = 100  # File Library API limit (https://transparencyplatform.zendesk.com/hc/en-us/articles/35960137882129-File-Library-Guide)
DOWNLOAD_URL = "https://fms.tp.entsoe.eu/downloadFileContent"

s3 = boto3.client("s3")
ssm = boto3.client("ssm")
SSM_USERNAME = "/entsoe/username"
SSM_PASSWORD = "/entsoe/password"   # SecureString: stored encrypted
WATERMARK_KEY = "state/file_library/watermark.txt"
INITIAL_WATERMARK = "2026-10-31T00:00:00.000Z"  # first run only: a week before the start (2026-11-07) so it also picks up the installed capacity file, last updated 2026-11-01
EARLIEST_UPDATE = "2015-01-01T00:00:00.000Z" # earliest possible update timestamp in the File Library (used to check if a folder exists)

# Retry strategy for temporary failures with exponential backoff
http = requests.Session()
http.mount("https://", HTTPAdapter(max_retries=Retry(
  total=3,
  backoff_factor=2,
  status_forcelist=[429, 500, 502, 503, 504],
  allowed_methods=["POST"],
  raise_on_status=False
))) 


def get_token(username: str, password: str) -> str:
  
  """
  Fetches an OAuth access token for the ENTSO-E File Library.
  Args:
    username (str): The ENTSO-E username.
    password (str): The ENTSO-E password.

  Returns:
    str: The access token.

  Raises:
    requests.HTTPError: If Keycloak rejects the request
  """

  response = http.post(TOKEN_URL, data={
      "client_id": CLIENT_ID,
      "grant_type": "password",
      "username": username,
      "password": password
  }, timeout=TIMEOUT_SECONDS)
  response.raise_for_status()

  return response.json()["access_token"]




def list_files(token: str, folder: str, updated_from: str, updated_to: str) -> list[dict]:
  """
  Lists the files metadata for one dataset folder, newest first.

  Args:
    token: The OAuth access token from get_token().
    folder: The dataset folder, e.g. "ActualTotalLoad_6.1.A_r3".
    updated_from: Start of the window (the watermark).
    updated_to: End of the window (this run's start time).

  Returns:
    The items from the response's itemList.

  Raises:
    requests.HTTPError: If File Library API rejects the request
  """

  body = {
    "topLevelFolder": TOP_LEVEL_FOLDER,
    "typeSpecificAttributeMap": {"path": f"/{TOP_LEVEL_FOLDER}/{folder}/"},
    "sorterList": [{"key": "lastUpdatedTimestamp", "ascending": False}],
    "pageInfo": {"pageIndex": 0, "pageSize": MAX_IDS_PER_DOWNLOAD},
    "updatedAt": {"from": updated_from, "to": updated_to}
  }

  items = []

  while True:
    response = http.post(
      LIST_URL,
      json=body,
      headers={"Authorization": f"Bearer {token}"},
      timeout=TIMEOUT_SECONDS
    )
    response.raise_for_status()

    page = response.json()["itemList"]
    items.extend(page)

    if len(page) < MAX_IDS_PER_DOWNLOAD:
      return items

    body["pageInfo"]["pageIndex"] += 1


def download_file(token: str, file_id: str) -> bytes:
  """
  Downloads a file from the ENTSO-E File Library.

  Args:
    token: The OAuth access token from get_token().
    file_id: The file ID from list_files().
  
  Returns:
    The file content as bytes.
  
  Raises:
    requests.HTTPError: If File Library API rejects the request
  """
  
  body = {
    "topLevelFolder": TOP_LEVEL_FOLDER,
    "fileIdList": [file_id],
    "downloadAsZip": False
  }


  response = http.post(
    DOWNLOAD_URL,
    json=body,
    headers={"Authorization": f"Bearer {token}"},
    timeout=TIMEOUT_SECONDS
  )
  response.raise_for_status()

  return response.content



def build_key_for_s3(folder: str, item: dict) -> str:
  """
  Builds the S3 key for one version of a File Library file.

  A file version is identified by its filename and its lastUpdatedTimestamp,
  so a retry builds the same key and IfNoneMatch blocks the duplicate.

  Args:
    folder: The dataset folder, e.g. "ActualTotalLoad_6.1.A_r3".
    item: One item from list_files().

  Returns:
    The S3 key, e.g. raw/file_library/<folder>/month=<yyyy_mm>/updated_at=<ts>/<filename>.
    month and updated_at are Hive-style partitions, so Glue/Athena/Spark read them as columns.
    month is the period the data covers, or "all" for single-file datasets (e.g. installed capacity).
  """

  filename = item["content"]["filename"]
  updated = datetime.fromisoformat(item["lastUpdatedTimestamp"])
  updated_at = updated.strftime("%Y%m%dT%H%M%SZ")   # basic ISO 8601 (no dashes or colons): colons in S3 keys break windows paths and spark path parsing

  return f"raw/file_library/{folder}/month={file_month(filename)}/updated_at={updated_at}/{filename}"


def file_month(filename: str) -> str:
  """
  Returns the data month of a File Library file.

  Args:
    filename: e.g. "2026_11_ActualTotalLoad_6.1.A_r3.csv".

  Returns:
    The month as "yyyy_mm" (monthly file names start with it), or "all" for single-file datasets that cover all periods.
  """

  match = re.match(r"(\d{4}_\d{2})_", filename)
  return match.group(1) if match else "all"


def write_raw_to_s3(bucket: str, key: str, content: bytes) -> bool:
  """
  Writes a file to S3.

  Args:
    bucket: The S3 bucket name.
    key: The S3 key.
    content: The file content as bytes.
  Returns:
    True if the file was written, False if it already exists (duplicate).
  Raises:
    botocore.exceptions.ClientError: If S3 rejects the request
  """

  try:
    s3.put_object(Bucket=bucket, Key=key, Body=content, IfNoneMatch="*") 
  except ClientError as e:
    if e.response["Error"]["Code"] == "PreconditionFailed":
      return False
    raise

  return True



def read_watermark_from_s3(bucket: str) -> str:
  """
  Reads the watermark from S3 (end of last successful run or INITIAL_WATERMARK for the initial run).

  Args:
    bucket: The S3 bucket name.
  Returns:
    The watermark as a string, e.g. "2026-11-07T00:00:00.000Z".
  Raises:
    botocore.exceptions.ClientError: If S3 rejects the request
  """

  try:
    response = s3.get_object(Bucket=bucket, Key=WATERMARK_KEY)
    return response["Body"].read().decode("utf-8")
  except ClientError as e:
    if e.response["Error"]["Code"] == "NoSuchKey":
      return INITIAL_WATERMARK
    raise


def save_watermark(bucket: str, watermark: str) -> None:
  """
  Saves the watermark to S3 (end of last successful run, so it will only be called after a successful run).

  Args:
    bucket: The S3 bucket name.
    watermark: The watermark as a string, e.g. "2026-11-07T00:00:00.000Z".
  Raises:
    botocore.exceptions.ClientError: If S3 rejects the request
  """

  s3.put_object(Bucket=bucket, Key=WATERMARK_KEY, Body=watermark.encode("utf-8"))


def exists_in_s3(bucket: str, key: str) -> bool:
  """
  Checks if a file exists in S3.

  Args:
    bucket: The S3 bucket name.
    key: The S3 key.

  Returns:
    True if the file exists, False otherwise.
  Raises:
    botocore.exceptions.ClientError: If S3 rejects the request
  """

  try:
    s3.head_object(Bucket=bucket, Key=key)
    return True
  except ClientError as e:
    if e.response["Error"]["Code"] == "404":   # head_object has no response body, so S3 returns the bare HTTP status as the code
      return False
    raise


def process_folder(token: str, bucket: str, folder: str, updated_from: str, updated_to: str, months: tuple[str, str] | None = None) -> int:
  """
  Processes one dataset folder from the ENTSO-E File Library.

  Args:
    token: The OAuth access token from get_token().
    bucket: The S3 bucket name.
    folder: The dataset folder, e.g. "ActualTotalLoad_6.1.A_r3".
    updated_from: Start of the window (see list_files).
    updated_to: End of the window (see list_files).
    months: Optional (first, last) data months to keep, e.g. ("2023_01", "2025_12"), both included. Used by the backfill.
  Returns:
    The number of files written to S3.
  Raises:
    ValueError: If the folder does not exist in the File Library (api returns no errors for that).

    Check by listing all files since the earliest possible update timestamp (EARLIEST_UPDATE) and if that returns no files, the folder does not exist.
  """

  files = list_files(token, folder, updated_from, updated_to)
  

  if not files and not list_files(token, folder, EARLIEST_UPDATE, updated_to):  # check if the folder exists by listing all files since the earliest possible update
    raise ValueError(f"Folder {folder} does not exist in the File Library.")

  if months:
    first, last = months
    files = [item for item in files if first <= file_month(item["content"]["filename"]) <= last]   # "yyyy_mm" strings sort like dates; "all" falls outside any range

  written = 0

  for item in files:
    key = build_key_for_s3(folder, item)
    if exists_in_s3(bucket, key):
      continue  # skip if already exists (duplicate)
    content = download_file(token, item["fileId"])
    if write_raw_to_s3(bucket, key, content):
      written += 1

  return written


def get_entsoe_credentials() -> tuple[str, str]:
  """
  Reads the ENTSO-E credentials from SSM Parameter Store.

  Returns:
    The username and password.
  Raises:
    botocore.exceptions.ClientError: If a parameter is missing or access is denied.
  """

  username = ssm.get_parameter(Name=SSM_USERNAME)["Parameter"]["Value"]
  password = ssm.get_parameter(Name=SSM_PASSWORD, WithDecryption=True)["Parameter"]["Value"]

  return username, password



def lambda_handler(event: dict, context: object) -> dict:
  """
  Copies files from the file library to S3 for every folder.
  Note: a failed folder doesn't stop the others, but the run still fails at the end and the watermark is not updated.

  Backfill mode, for history the watermark never covered (files last updated before INITIAL_WATERMARK):
    {"backfill": {"folder": "EnergyPrices_12.1.D_r3.1", "months_from": "2023_01", "months_to": "2025_12"}}
  copies every file of that folder whose data month is in the range, whenever it was last updated,
  skips files already in S3, and leaves the watermark alone so the daily runs are not affected.

  Raises:
    RuntimeError: If any folder fails to process.
    ValueError: If the backfill folder is not one of DATASET_FOLDERS.
  """

  bucket = os.environ["RAW_BUCKET"]
  window_end = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")  # this run's start time, taken before listing so nothing updated mid-run is missed

  backfill = event.get("backfill")
  if backfill:
    if backfill["folder"] not in DATASET_FOLDERS:
      raise ValueError(f"Unknown backfill folder {backfill['folder']}. Expected one of {DATASET_FOLDERS}.")
    folders = [backfill["folder"]]
    window_start = EARLIEST_UPDATE                                    # any update time: the months filter picks the files
    months = (backfill["months_from"], backfill["months_to"])
  else:
    folders = DATASET_FOLDERS
    window_start = read_watermark_from_s3(bucket)                     # where the last successful window ended
    months = None

  username, password = get_entsoe_credentials()

  written = {}
  failed = []

  for folder in folders:
    start = time.perf_counter()
    try:
      token = get_token(username, password)   # getting a new token for each folder to avoid token expiration mid-run
      written[folder] = process_folder(token, bucket, folder, window_start, window_end, months)
      print(f"Folder {folder} processed successfully. {written[folder]} files written in {time.perf_counter() - start:.0f} s.")
    except Exception as e:
      logging.exception(f"Folder {folder} failed to process after {time.perf_counter() - start:.0f} s: {e}")
      failed.append(folder)

  if failed:
    raise RuntimeError(f"Folders that failed processing: {failed}. Watermark not updated.")

  if backfill:
    return {"Written Files": written, "Backfill months": months}   # the watermark belongs to the daily runs

  save_watermark(bucket, window_end)   # this window's end is the next window's start

  return {
    "Written Files": written,
    "Watermark": window_end}



if __name__ == "__main__":
  import dotenv

  dotenv.load_dotenv(override=True)  # in case credentials changed since last run
  print(lambda_handler({}, None))  # for local testing
