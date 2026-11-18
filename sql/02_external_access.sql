CREATE NETWORK RULE IF NOT EXISTS POWERBI_WIF.API.POWERBI_HOSTS
  MODE = EGRESS TYPE = HOST_PORT
  VALUE_LIST = ('login.microsoftonline.com:443', 'api.powerbi.com:443');

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS POWERBI_WIF_EGRESS
  ALLOWED_NETWORK_RULES = (POWERBI_WIF.API.POWERBI_HOSTS)
  ENABLED = TRUE;

-- The SQL procedure passes the assertion directly to this private helper.
CREATE OR REPLACE SECURE FUNCTION POWERBI_WIF.API.FETCH_WORKSPACE_PAGE(
  assertion VARCHAR, page_size INTEGER, page_offset INTEGER
)
RETURNS VARIANT
LANGUAGE PYTHON
VOLATILE
RUNTIME_VERSION = '3.12'
PACKAGES = ('requests')
HANDLER = 'fetch'
EXTERNAL_ACCESS_INTEGRATIONS = (POWERBI_WIF_EGRESS)
AS
$$
import requests
from uuid import UUID

TENANT = str(UUID('<% tenant_id %>'))
CLIENT = str(UUID('<% client_id %>'))
SCOPE = 'https://analysis.windows.net/powerbi/api/.default'
WORKSPACES = 'https://api.powerbi.com/v1.0/myorg/admin/groups'


def check(response, service):
    if response.status_code == 200:
        return
    message = f'{service} HTTP {response.status_code}'
    if service == 'Entra':
        try:
            payload = response.json()
        except ValueError:
            payload = None
        codes = payload.get('error_codes') if isinstance(payload, dict) else None
        if isinstance(codes, list):
            message += ''.join(f' AADSTS{c}' for c in codes if type(c) is int)
    elif response.status_code == 429:
        message += ' Retry-After=' + response.headers.get('Retry-After', 'unspecified')
    raise ValueError(message)


def fetch(assertion, page_size, page_offset):
    with requests.Session() as http:
        token = http.post(
            f'https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/token',
            data={
                'client_id': CLIENT,
                'scope': SCOPE,
                'grant_type': 'client_credentials',
                'client_assertion_type': 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
                'client_assertion': assertion,
            },
            timeout=(5, 25), allow_redirects=False,
        )
        check(token, 'Entra')
        response = http.get(
            WORKSPACES, params={'$top': page_size, '$skip': page_offset},
            headers={'Authorization': 'Bearer ' + token.json()['access_token']},
            timeout=(5, 35), allow_redirects=False,
        )
        check(response, 'Power BI')
        rows = response.json()['value']
        return {
            'count': len(rows),
            'workspaces': [{key: row.get(key) for key in ('id', 'name', 'type', 'state')} for row in rows],
        }
$$;
