# Procedure reference

`POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(page_size INTEGER DEFAULT 1, page_offset INTEGER DEFAULT 0)` returns one `VARIANT` object. It makes one page request to `GET https://api.powerbi.com/v1.0/myorg/admin/groups`.

| Input | Accepted values | Power BI parameter |
| --- | --- | --- |
| `page_size` | 1–100, default 1 | `$top` |
| `page_offset` | 0–2,147,483,647, default 0 | `$skip` |

Null arguments and out-of-range values raise error `-20001`. To read another page, increase the offset by the number of rows returned. Stop on an empty or short page. Changes to the tenant during paging can shift the results.

| Output | Meaning |
| --- | --- |
| `count` | Number of workspaces in this page |
| `workspaces` | Array with one object per returned workspace |
| `id`, `name`, `type`, `state` | Fields projected from each Power BI workspace. A missing field becomes JSON null. |

The Microsoft endpoint accepts up to 5,000 records in one request. The procedure caps each call at 100. Microsoft documents tenant limits of 15 requests per minute and 50 per hour for this endpoint. [Groups – GetGroupsAsAdmin](https://learn.microsoft.com/en-us/rest/api/power-bi/admin/groups-get-groups-as-admin)

## Deployment objects

| File | Objects |
| --- | --- |
| [01_identity.sql](../sql/01_identity.sql) | Database `POWERBI_WIF`, schema `API`, WIF secret `ENTRA_IDENTITY` |
| [02_external_access.sql](../sql/02_external_access.sql) | Network rule `POWERBI_HOSTS`, account integration `POWERBI_WIF_EGRESS`, secure Python function `FETCH_WORKSPACE_PAGE` |
| [03_procedure.sql](../sql/03_procedure.sql) | Owner's-rights procedure `LIST_ADMIN_WORKSPACES` |

The network rule permits HTTPS on port 443 to `login.microsoftonline.com` and `api.powerbi.com`. The handler uses fixed URLs and disables redirects. It requests `https://analysis.windows.net/powerbi/api/.default`. The token-exchange audience on the Snowflake assertion is `api://AzureADTokenExchange`.

## Verification record

| Check | Result |
| --- | --- |
| Snowflake CLI access | Activated `ACCOUNTADMIN` |
| Identity and authorization | Created the WIF secret, federated credential, group and app. Verified direct group membership and saved Fabric setting. |
| Live token exchange and Power BI endpoint | The [Mac test script](../scripts/test_from_mac.py) ran the deployment's Python handler on the Mac with a real Snowflake-issued assertion. Entra and Power BI both returned HTTP 200. One workspace was returned. |
| SQL entry point on the trial | Created the stored procedure. Calling it with page size zero raised `-20001`. |
| Python runtime and tutorial SQL on the trial | Created a temporary copy of the HTTP function with the integration clause omitted. A temporary procedure passed a real assertion to a test function that returned a fictional workspace. The tutorial's SQL pipe produced the expected name and state. |
| Full in-Snowflake call | Blocked. The trial rejected the external access integration with 509009. Calling the procedure with valid inputs reported that its HTTP helper was missing. |
