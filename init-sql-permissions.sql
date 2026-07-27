-- =============================================================================
-- init-sql-permissions.sql — give the claw-mock pod access to the SQL server
-- =============================================================================
--
-- WHY THIS EXISTS AS A SCRIPT
--
-- The server is Entra-only (azuread_authentication_only = true). Granting a
-- managed identity access is T-SQL run against the server — there is no ARM or
-- Terraform resource for it, so it cannot live in sqlserver.tf. The deploy
-- pipeline runs this immediately after `terraform apply`, once against master
-- and once against each mock database.
--
-- WHO RUNS IT
--
-- The deploy identity (deploy-claw-mock-dev), which is a member of the
-- server's Entra admin group local-data-admins-claw-mock-dev and therefore
-- admin on the server. The pipeline is already logged in as it via OIDC, so
-- sqlcmd authenticates with ActiveDirectoryDefault and no password exists
-- anywhere in this flow.
--
-- PLACEHOLDERS
--
-- Substituted by the pipeline before execution; do not hardcode values here.
--
--   __POD_IDENTITY_NAME__   display name of the pod's managed identity
--                           (terraform output pod_identity_name,
--                            default deploy-claw-mock-dev)
--
-- PREREQUISITE
--
-- The server must have a user-assigned identity holding Directory.Read
-- (claw-code-mi-sqlserver-dev, attached in sqlserver.tf). Without it the
-- CREATE USER below fails with:
--   Principal '...' could not be found or this principal type is not supported.
-- because the server cannot look the principal up in the directory.
--
-- IDEMPOTENT: safe on every deploy. CREATE USER is guarded, and
-- ALTER ROLE ... ADD MEMBER is a no-op when the member is already present.
-- =============================================================================

SET NOCOUNT ON;

-- Server-level user. In Azure SQL a contained user in master is what makes the
-- principal known to the server; it is created in every database context this
-- script runs against, including master.
IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals WHERE name = N'__POD_IDENTITY_NAME__'
)
BEGIN
    PRINT 'Creating user [__POD_IDENTITY_NAME__] from external provider in [' + DB_NAME() + ']';
    CREATE USER [__POD_IDENTITY_NAME__] FROM EXTERNAL PROVIDER;
END
ELSE
BEGIN
    PRINT 'User [__POD_IDENTITY_NAME__] already exists in [' + DB_NAME() + '] — skipping CREATE';
END

-- Role membership applies to the mock databases only. master carries the
-- server-level user and nothing more, so the bot gets no rights there.
IF DB_NAME() <> N'master'
BEGIN
    -- db_datawriter is the requirement: the hourly mock run inserts and
    -- updates rows. db_datareader is granted alongside it because the run has
    -- to read existing keys and row counts to generate referentially valid
    -- data and to report per-table counts afterwards.
    ALTER ROLE db_datawriter ADD MEMBER [__POD_IDENTITY_NAME__];
    ALTER ROLE db_datareader ADD MEMBER [__POD_IDENTITY_NAME__];

    PRINT 'Granted db_datawriter + db_datareader on [' + DB_NAME() + '] to [__POD_IDENTITY_NAME__]';
END
ELSE
BEGIN
    PRINT 'Server-level user created in [master]; no role membership granted there';
END
