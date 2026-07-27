# =============================================================================
# Azure SQL Server (MSSQL) — cheapest tier, 2 databases
#
# Entra-only authentication (azuread_authentication_only = true): NO SQL
# admin login, NO SQL password anywhere on the server. Server-level admin
# is the Entra group local-data-admins-claw-mock-dev (referenced via the
# azuread_group data source in main.tf — never hardcoded object IDs). Its
# members — cameron-howe and the deploy identity deploy-claw-mock-dev —
# are admins of every database on the server, which is how both the
# deploy pipeline (sqlpackage, "Active Directory Default") and the
# runtime bot (workload identity) authenticate.
# =============================================================================
resource "azurerm_mssql_server" "sql" {
  name                = local.sql_server_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = local.location
  version             = "12.0"
  minimum_tls_version = "1.2"

  azuread_administrator {
    login_username              = data.azuread_group.sql_admins.display_name
    object_id                   = data.azuread_group.sql_admins.object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

# Basic SKU (5 DTU, 2 GB) — the cheapest Azure SQL tier. Mock databases
# don't need more; scale up later if the mock load outgrows it.
resource "azurerm_mssql_database" "adventureworks" {
  name        = "AdventureWorks"
  server_id   = azurerm_mssql_server.sql.id
  sku_name    = "Basic"
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb = 2

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

resource "azurerm_mssql_database" "northwind" {
  name        = "Northwind"
  server_id   = azurerm_mssql_server.sql.id
  sku_name    = "Basic"
  collation   = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb = 2

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

# "Allow Azure services and resources to access this server". Covers both
# GitHub-hosted runners (which run on Azure VMs) for the dacpac deploy
# step and the AKS cluster's outbound IPs for the claw-mock bot pod.
# If you later need a tighter perimeter, replace this with explicit
# firewall rules for the runner egress IPs + a private endpoint for AKS.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# =============================================================================
# Bot database connection info
#
# The SQL server is Entra-only, so there is no SQL user or password to
# hand to the bot. The pod authenticates as the deploy identity
# (deploy-claw-mock-dev) via Azure Workload Identity; that identity is a
# member of the server's Entra-admin group and therefore has full access
# to both databases. This secret carries only non-secret connection
# parameters (kept as a Secret so the deployment's envFrom wiring matches
# the other claw-mock secrets).
# =============================================================================
resource "kubernetes_secret" "claw_mock_db" {
  metadata {
    name      = "claw-mock-db"
    namespace = var.namespace
  }
  data = {
    SQL_SERVER_FQDN       = azurerm_mssql_server.sql.fully_qualified_domain_name
    SQL_DB_ADVENTUREWORKS = azurerm_mssql_database.adventureworks.name
    SQL_DB_NORTHWIND      = azurerm_mssql_database.northwind.name
  }
  depends_on = [kubernetes_namespace.claw-mock]
}

# =============================================================================
# Outputs
# =============================================================================
output "sql_server_fqdn" {
  description = "Fully qualified domain name of the Azure SQL server"
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_databases" {
  description = "Mock databases on the SQL server"
  value       = [azurerm_mssql_database.adventureworks.name, azurerm_mssql_database.northwind.name]
}
