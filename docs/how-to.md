# Set up the integration

You need a Snowflake CLI connection and warehouse, permission to administer the Entra app and group, and a Fabric administrator for the tenant setting. Use an account that supports Snowflake external access integrations for the full deployment. Run the shell commands from the repository root.

## Check Snowflake access

```sh
export SNOW_CONNECTION='your-connection'
snow sql -c "$SNOW_CONNECTION" --role ACCOUNTADMIN \
  -q 'SELECT CURRENT_ACCOUNT_NAME(), CURRENT_REGION(), CURRENT_ROLE(), CURRENT_WAREHOUSE()'
```

Check that the account is the intended target and the role is `ACCOUNTADMIN`. Select a warehouse with the CLI's `--warehouse` option if your connection has no default warehouse. These steps create a dedicated database and an account-level integration. Check for existing objects with the names in the [reference](reference.md) before deploying.

## Create the group and authorize the API

1. In Microsoft Entra ID, create a **Security** group with **Assigned** membership. For example, name it `Snowflake-PowerBI-ReadOnly-Admins`.
2. In the Fabric admin portal, open **Tenant settings → Admin API settings → Service principals can access read-only admin APIs**. Enable it for **Specific security groups**, add the group, and apply. Retain any existing allowed groups and exclusions. If the current policy allows the entire organization, review the effect of narrowing it before saving.
3. In Entra **App registrations**, register a single-tenant application. Leave the redirect URI empty. In the group's **Members** page, add the new **enterprise application**. Check its application ID against the registration.
4. Record the directory (tenant) ID and application (client) ID privately. For this app-only admin API, Power BI admin-consent permissions on the app registration must be absent. Fabric evaluates the security group for access. [Microsoft setup guide](https://learn.microsoft.com/en-us/fabric/admin/enable-service-principal-admin-apis)

## Establish the trust

```sh
snow sql -c "$SNOW_CONNECTION" --role ACCOUNTADMIN -f sql/01_identity.sql
```

The final statement describes the secret. In the app registration, open **Certificates & secrets → Federated credentials → Add credential → Other issuer**. Copy `workload_identity_federation_issuer` to **Issuer** and `workload_identity_federation_subject` to the explicit **Subject**. Keep the audience `api://AzureADTokenExchange`. Give the credential a name and save. Use the exact values from the target account, including case. [Snowflake outbound federation](https://docs.snowflake.com/en/user-guide/workload-identity-federation-outbound)

## Deploy the HTTP handler and procedure

On a repeat deployment, `IF NOT EXISTS` keeps the existing secret, rule, and integration. Inspect them before replacing the function or procedure.

```sql
DESC SECRET POWERBI_WIF.API.ENTRA_IDENTITY;
DESC NETWORK RULE POWERBI_WIF.API.POWERBI_HOSTS;
DESC INTEGRATION POWERBI_WIF_EGRESS;
```

Check the secret type and the exact issuer and subject against Entra. Check that the rule is an egress host-and-port rule for the two hosts in the [reference](reference.md). Check that the integration is enabled and allows only that rule. Resolve any differences before rerunning the deployment.

Set these two variables to the actual UUIDs for your registration before running the commands.

```sh
export ENTRA_TENANT_ID='your-directory-id'
export ENTRA_CLIENT_ID='your-application-id'

snow sql -c "$SNOW_CONNECTION" --role ACCOUNTADMIN \
  -D "tenant_id=$ENTRA_TENANT_ID" -D "client_id=$ENTRA_CLIENT_ID" \
  -f sql/02_external_access.sql && \
snow sql -c "$SNOW_CONNECTION" --role ACCOUNTADMIN -f sql/03_procedure.sql
```

The first command creates the egress rule, external access integration, and secure Python function. The second creates the SQL procedure. A procedure can exist even when the helper is missing. Confirm that the first command succeeded, then run the [one-workspace tutorial](tutorial.md).

To allow an existing role to call the procedure, grant `USAGE` on its warehouse, the `POWERBI_WIF` database, the `POWERBI_WIF.API` schema, and `PROCEDURE POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(NUMBER, NUMBER)`. Choose a role whose members may read tenant-wide workspace metadata. The handler and identity secret are for the procedure owner.

## Diagnose a failed call

| Symptom | Action |
| --- | --- |
| Snowflake 509009 creating the integration | The trial rejects external access. Complete the deployment in an account that supports it. A different Microsoft permission cannot resolve this error. |
| Unknown function `FETCH_WORKSPACE_PAGE` | Inspect the result of `02_external_access.sql`. Resolve its first error and rerun it. |
| Entra HTTP 400 or 401 | Check the client ID and tenant ID, the exact issuer and subject, and the audience. Allow time for a newly created credential to propagate. |
| Power BI HTTP 401 or 403 | Confirm the Power BI resource scope, enterprise application membership, tenant setting, and absence of Power BI admin-consent permissions. The portal advises allowing up to 15 minutes for setting changes. |
| Power BI HTTP 429 | Wait for the reported `Retry-After` period before sending another page request. |
| Snowflake error -20001 | Check the page bounds in the [procedure reference](reference.md). |

Snowflake can hide secure function error details from callers. An operator with the owning role can run the one-workspace call to diagnose the problem. [Snowflake secure object error redaction](https://docs.snowflake.com/en/release-notes/bcr-bundles/un-bundled/bcr-1858)

## Revoke access

To withdraw this app's access through the group, remove its enterprise application from the group's members. To prevent new token exchanges through this trust, delete its specific federated credential. Allow for propagation and already-issued tokens. Removing the group from the Fabric setting affects every member of the group.
