import requests, dotenv, os

TOKEN_URL = "https://keycloak.tp.entsoe.eu/realms/tp/protocol/openid-connect/token"
CLIENT_ID = "tp-fms-public"
TIMEOUT_SECONDS = 30
LIST_URL = "https://fms.tp.entsoe.eu/listFileMetadata"
TOP_LEVEL_FOLDER = "TP_export"
MAX_IDS_PER_DOWNLOAD = 100  # File Library API limit (https://transparencyplatform.zendesk.com/hc/en-us/articles/35960137882129-File-Library-Guide)

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

  response = requests.post(TOKEN_URL, data={
      "client_id": CLIENT_ID,
      "grant_type": "password",
      "username": username,
      "password": password
  }, timeout=TIMEOUT_SECONDS)
  response.raise_for_status()

  return response.json()["access_token"]


def list_files(token: str, folder: str) -> list[dict]:
  """
  Lists the files metadata for one dataset folder, newest first. 

  Args:
    token: The OAuth access token from get_token().
    folder: The dataset folder, e.g. "ActualTotalLoad_6.1.A_r3".
    page_size: Max items to return per request (max 100).

  Returns:
    The items from the response's itemList.

  Raises:
    requests.HTTPError: If Keycloak rejects the request
  """

  body = {
    "topLevelFolder": TOP_LEVEL_FOLDER,
    "typeSpecificAttributeMap": {"path": f"/{TOP_LEVEL_FOLDER}/{folder}/"},
    "sorterList": [{"key": "lastUpdatedTimestamp", "ascending": False}],
    "pageInfo": {"pageIndex": 0, "pageSize": MAX_IDS_PER_DOWNLOAD}
  }

  response = requests.post(
    LIST_URL, 
    json=body,
    headers={"Authorization": f"Bearer {token}"},
    timeout=TIMEOUT_SECONDS
  )
  response.raise_for_status()

  return response.json()["itemList"]



if __name__ == "__main__":
  dotenv.load_dotenv() 
  
  # OAuth token 
  token = get_token(os.environ["ENTSOE_USERNAME"], os.environ["ENTSOE_PASSWORD"])
  print(f"Token: {token[:10]}")

  # Listing files in a dataset folder
  files = list_files(token, "ActualTotalLoad_6.1.A_r3")
  print(f"Found {len(files)} files in ActualTotalLoad_6.1.A_r3")
  for f in files[:1]:
    print(f"""Path: {f["typeSpecificAttributeMap"]["path"]},
      File: {f["content"]["filename"]}, 
      Last Updated: {f["lastUpdatedTimestamp"]}""")