"""Exercise the Snowflake assertion and Power BI HTTP handler from a Mac."""

import json
import os
from pathlib import Path
import subprocess
import sys
from uuid import UUID

import requests


HANDLER_SQL = Path(__file__).resolve().parents[1] / "sql" / "02_external_access.sql"
ISSUE_ASSERTION = """SELECT SYSTEM$ISSUE_WORKLOAD_IDENTITY_FEDERATION_TOKEN(
    'POWERBI_WIF.API.ENTRA_IDENTITY', '{"aud":"api://AzureADTokenExchange"}'
) AS ASSERTION"""


def load_handler(tenant_id, client_id):
    # Run the same Python body that Snowflake would install, from this checkout.
    # Only the two validated, non-secret UUIDs are substituted into its source.
    _, body, _ = HANDLER_SQL.read_text(encoding="utf-8").split("$$")
    body = body.replace("<% tenant_id %>", str(UUID(tenant_id)))
    body = body.replace("<% client_id %>", str(UUID(client_id)))
    namespace = {}
    exec(compile(body, str(HANDLER_SQL), "exec"), namespace)
    return namespace["fetch"]


def issue_assertion(connection):
    result = subprocess.run(
        ["snow", "sql", "-c", connection, "--role", "ACCOUNTADMIN",
         "--format", "json", "-q", ISSUE_ASSERTION],
        stdout=subprocess.PIPE, text=True, check=True,
    )
    # CLI stdout holds a bearer credential. Consume it in memory.
    assertion = json.loads(result.stdout)[0]["ASSERTION"]
    if not isinstance(assertion, str) or assertion.count(".") != 2:
        raise ValueError("Unexpected assertion format.")
    return assertion


def main():
    try:
        connection = os.environ["SNOW_CONNECTION"]
        fetch = load_handler(os.environ["ENTRA_TENANT_ID"], os.environ["ENTRA_CLIENT_ID"])
    except KeyError as error:
        sys.exit(f"Set the environment variable {error.args[0]} before running the test.")
    except ValueError:
        sys.exit("Check that the tenant and client IDs are UUIDs and the SQL handler is intact.")

    try:
        assertion = issue_assertion(connection)
    except FileNotFoundError:
        sys.exit("Install Snowflake CLI and make the snow command available on PATH.")
    except (subprocess.CalledProcessError, ValueError, KeyError, IndexError, TypeError):
        sys.exit("Could not read an assertion from Snowflake. Check the connection, role and WIF secret.")
    print("Snowflake issued the workload assertion.", flush=True)

    try:
        page = fetch(assertion, 1, 0)
    except ValueError as error:
        # The shared handler's HTTP errors contain only the service and status diagnostics.
        if str(error).startswith(("Entra HTTP ", "Power BI HTTP ")):
            sys.exit(str(error))
        sys.exit("Unexpected response format from Microsoft.")
    except requests.RequestException:
        sys.exit("The Mac could not complete the Microsoft HTTPS request. Check connectivity and retry.")
    except (KeyError, TypeError, AttributeError):
        sys.exit("Unexpected response format from Microsoft.")

    rows = page["workspaces"]
    if page["count"] != len(rows) or len(rows) > 1:
        sys.exit("The returned page did not match the one-workspace request.")
    print("Mac to Entra token endpoint: HTTP 200")
    print(f"Mac to Power BI admin API: HTTP 200 (workspace rows: {len(rows)})")


if __name__ == "__main__":
    main()
