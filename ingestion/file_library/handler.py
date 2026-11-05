import requests, dotenv, os

TOKEN_URL = "https://keycloak.tp.entsoe.eu/realms/tp/protocol/openid-connect/token"
CLIENT_ID = "tp-fms-public"
TIMEOUT_SECONDS = 30

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


if __name__ == "__main__":
  dotenv.load_dotenv() 
  token = get_token(os.environ["ENTSOE_USERNAME"], os.environ["ENTSOE_PASSWORD"])
  print(f"Token: {token[:10]}")