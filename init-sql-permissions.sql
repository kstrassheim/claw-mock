-- =============================================================================
-- init-sql-permissions.sql — grant the claw-mock pod access inside a database
-- =============================================================================
--
-- WHY THIS EXISTS AS A SCRIPT
--
-- The server is Entra-only (azuread_authentication_only = true). Database-level
-- access for a managed identity is granted with T-SQL against the database
-- itself — there is no ARM/Terraform resource for it, so it cannot live in
-- sqlserver.tf. This script is therefore run by the deploy pipeline, once per
-- database, immediately after `terraform apply`.
--
-- PLACEHOLDERS
--
-- The pipeline substitutes these before executing; do not hardcode values here.
--
--   __POD_IDENTITY_NAME__   display name of the pod's managed identity
--                           (Terraform output pod_identity_name,
--                            default deploy-claw-mock-dev)
--
-- PREREQUISITE
--
-- The server must have a user-assigned identity with Directory.Read attached
-- (claw-code-mi-sqlserver-dev, wired up in sqlserver.tf). Without it the
-- CREATE USER below fails with:
--   Principal '...' could not be found or this principal type is not supported.
-- because the server cannot look the principal up in the directory.
--
-- IDEMPOTENT: safe to re-run on every deploy. Creating the user is guarded,
-- and ALTER ROLE ... ADD MEMBER is a no-op when the member is already present.
-- =============================================================================

SET NOCOUNT ON;

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals WHERE name = N'__POD_IDENTITY_NAME__'
)
BEGIN
    PRINT 'Creating contained user [__POD_IDENTITY_NAME__] from external provider';
    CREATE USER [__POD_IDENTITY_NAME__] FROM EXTERNAL PROVIDER;
END
ELSE
BEGIN
    PRINT 'User [__POD_IDENTITY_NAME__] already exists — skipping CREATE';
END

-- Contributor-equivalent at database scope. The mock bot inserts and updates
-- rows on every hourly run and the mocking manuals allow schema-shaped changes,
-- so it needs more than datareader/datawriter.
ALTER ROLE db_owner ADD MEMBER [__POD_IDENTITY_NAME__];

PRINT 'Granted db_owner on [' + DB_NAME() + '] to [__POD_IDENTITY_NAME__]';
