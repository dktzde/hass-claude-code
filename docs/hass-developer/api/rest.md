Home Assistant provides a RESTful API on the same port as the web frontend. The default port is 80 on Home Assistant OS installations and 8123 otherwise, unless the port is changed via the `SETUP_PORT` environment variable.

If you are not using the [`frontend`](https://www.home-assistant.io/integrations/frontend/) in your setup then you need to add the [`api` integration](https://www.home-assistant.io/integrations/api/) to your `configuration.yaml` file.

- `http://IP_ADDRESS:8123/` is an interface to control Home Assistant.
- `http://IP_ADDRESS:8123/api/` is a RESTful API.

The API accepts and returns only JSON encoded objects.

All API calls have to be accompanied by the header `Authorization: Bearer TOKEN`, where `TOKEN` is replaced by your unique access token. You obtain a token ("Long-Lived Access Token") by logging into the frontend using a web browser, and going to [your profile](https://www.home-assistant.io/docs/authentication/#your-account-profile) `http://IP_ADDRESS:8123/profile`. Be careful to copy the whole key.

There are multiple ways to consume the Home Assistant Rest API. One is with `curl`:

```shell
curl \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  http://IP_ADDRESS:8123/ENDPOINT
```

Another option is to use Python and the [Requests](https://requests.readthedocs.io/en/latest/) module.

```python
from requests import get

url = "http://localhost:8123/ENDPOINT"
headers = {
    "Authorization": "Bearer TOKEN",
    "content-type": "application/json",
}

response = get(url, headers=headers)
print(response.text)
```

Another option is to use the [RESTful Command integration](https://www.home-assistant.io/integrations/rest_command/) in a Home Assistant automation or script.

```yaml
turn_light_on:
  url: http://localhost:8123/api/states/light.study_light
  method: POST
  headers:
    authorization: 'Bearer TOKEN'
    content-type: 'application/json'
  payload: '{"state":"on"}'
```

Successful calls will return status code 200 or 201. Other status codes that can return are:

- 400 (Bad Request)
- 401 (Unauthorized)
- 404 (Not Found)
- 405 (Method Not Allowed)

### Actions

The API supports the following actions:
