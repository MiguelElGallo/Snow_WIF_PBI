CREATE OR REPLACE PROCEDURE POWERBI_WIF.API.LIST_ADMIN_WORKSPACES(
  page_size INTEGER DEFAULT 1, page_offset INTEGER DEFAULT 0
)
COPY GRANTS
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  invalid_page EXCEPTION (-20001, 'Use page_size 1 through 100 and page_offset 0 through 2147483647.');
  workspace_page VARIANT;
BEGIN
  IF (page_size IS NULL OR page_size NOT BETWEEN 1 AND 100 OR
      page_offset IS NULL OR page_offset NOT BETWEEN 0 AND 2147483647) THEN
    RAISE invalid_page;
  END IF;
  SELECT POWERBI_WIF.API.FETCH_WORKSPACE_PAGE(
    SYSTEM$ISSUE_WORKLOAD_IDENTITY_FEDERATION_TOKEN(
      'POWERBI_WIF.API.ENTRA_IDENTITY', '{"aud":"api://AzureADTokenExchange"}'
    ), :page_size, :page_offset
  ) INTO :workspace_page;
  RETURN workspace_page;
END;
$$;
