import requests, dotenv, os
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
MAX_IDS_PER_DOWNLOAD = 100  # File Library API limit (https://transparencyplatform.zendesk.com/hc/en-us/articles/35960137882129-File-Library-Guide)
DOWNLOAD_URL = "https://fms.tp.entsoe.eu/downloadFileContent"

s3 = boto3.client("s3")

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




def list_files(token: str, folder: str, updated_since: str | None = None) -> list[dict]:
  """
  Lists the files metadata for one dataset folder, newest first. 

  Args:
    token: The OAuth access token from get_token().
    folder: The dataset folder, e.g. "ActualTotalLoad_6.1.A_r3".
    updated_since: For incremental loading: Only return files updated since the last successful run (watermark).

  Returns:
    The items from the response's itemList.

  Raises:
    requests.HTTPError: If File Library API rejects the request
  """

  body = {
    "topLevelFolder": TOP_LEVEL_FOLDER,
    "typeSpecificAttributeMap": {"path": f"/{TOP_LEVEL_FOLDER}/{folder}/"},
    "sorterList": [{"key": "lastUpdatedTimestamp", "ascending": False}],
    "pageInfo": {"pageIndex": 0, "pageSize": MAX_IDS_PER_DOWNLOAD}
  }

  if updated_since:
    body["updatedAt"] = {"from": updated_since, "to": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")}

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
    The S3 key, e.g. raw/file_library/<folder>/<filename>/updated_at=<ts>/<filename>.
  """

  filename = item["content"]["filename"]
  updated = datetime.fromisoformat(item["lastUpdatedTimestamp"])
  updated_at = updated.strftime("%Y%m%dT%H%M%SZ")   # basic ISO 8601 (no dashes or colons): colons in S3 keys break windows paths and spark path parsing

  return f"raw/file_library/{folder}/{filename}/updated_at={updated_at}/{filename}"


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


if __name__ == "__main__":

  dotenv.load_dotenv(override =True) 

  # OAuth token 
  token = get_token(os.environ["ENTSOE_USERNAME"], os.environ["ENTSOE_PASSWORD"])
  print(f"Token: {token[:10]}")

  # Listing files in a dataset folder
  files = list_files(token, "ActualTotalLoad_6.1.A_r3", "2026-11-05T00:00:00.000Z")
  
  print(f"Found {len(files)} files in ActualTotalLoad_6.1.A_r3")
  for f in files[:1]:
    print(f"""Path: {f["typeSpecificAttributeMap"]["path"]},
      File: {f["content"]["filename"]}, 
      Last Updated: {f["lastUpdatedTimestamp"]}""")
    
  # Downloading the newest file
  newest = files[0]
  content = download_file(token, newest["fileId"])
  filename = newest["content"]["filename"]
  
  # with open(filename, "wb") as out:
  #   out.write(content)
  # print(f"Downloaded {filename} ({len(content)} bytes)")

  print(build_key_for_s3("ActualTotalLoad_6.1.A_r3", files[0]))

  write_raw_to_s3(os.environ["RAW_BUCKET"], build_key_for_s3("ActualTotalLoad_6.1.A_r3", files[0]), content)
