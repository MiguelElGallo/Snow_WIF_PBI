# Call the Power BI admin API from Snowflake

List a page of Power BI workspaces with a SQL stored procedure. Snowflake issues a short-lived identity token. Microsoft Entra ID exchanges it for a Power BI access token. The application uses a federated credential and needs no client password.

```sql
CALL POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(1, 0);
```

| I want to… | Start here |
| --- | --- |
| Make my first call on a configured account | [Tutorial](docs/tutorial.md) |
| Set up the trust or diagnose a failure | [How-to guide](docs/how-to.md) |
| Look up arguments, output, limits, or test coverage | [Reference](docs/reference.md) |
| Understand who can see what | [Explanation](docs/explanation.md) |

**Verification.** In a Snowflake trial, the stored procedure was created and rejected an invalid page size as expected. A local run of the same HTTP handler exchanged a real Snowflake assertion and read one workspace from Power BI. The trial rejected the external access integration with error 509009, so the complete procedure call still needs verification in a Snowflake account that supports external access.
