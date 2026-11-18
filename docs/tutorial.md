# Read your first workspace

You will call the procedure for a single workspace and extract two fields from its JSON result. Start with an account where all three [deployment files](how-to.md) have run successfully. Select a warehouse and a role with permission to call the procedure.

## 1. Call the procedure

```sql
CALL POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(1, 0);
```

The first argument requests one workspace. The second starts at the beginning. A populated tenant can return a result shaped like this fictional example.

```json
{
  "count": 1,
  "workspaces": [
    {"id": "00000000-0000-4000-8000-000000000001", "name": "Example workspace", "type": "Workspace", "state": "Active"}
  ]
}
```

## 2. Read the result as a table

When you want table rows, use the following form of the call. Snowflake's pipe operator passes this call's result into the query on the right. Running the example issues one new Power BI request.

```sql
CALL POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(1, 0)
->> SELECT ws.value:name::VARCHAR AS workspace_name,
       ws.value:state::VARCHAR AS workspace_state
FROM $1 AS result,
     LATERAL FLATTEN(INPUT => result.$1:workspaces) AS ws;
```

For the example above, the row contains `Example workspace` and `Active`. An empty page has `count: 0` and produces zero table rows. Workspace names from your tenant can identify people. Use fictional data when sharing examples.
