# =============================================================================
# Shared references: locals, resource group, Entra groups, and identities.
#
# Everything here is a *reference* (data source) to pre-existing objects —
# no hardcoded object IDs. The concrete resources live in:
#   aks.tf        — AKS cluster, ACR, PV storage, K8s namespace/policies
#   sqlserver.tf  — Azure SQL server + databases + bot connection secret
# =============================================================================

locals {
  resource_group_name = "claw-mock-dev"
  cluster_name        = var.cluster_name
  location            = var.location
  namespace           = var.namespace
  aks_version         = "1.35.3"
  # Renamed from "claw-mock-sql-${var.env}". The old name is stuck in an
  # Azure name-to-location reservation pointing at northeurope, left behind
  # by a create that failed there with ProvisioningDisabled. Every attempt to
  # create it in westeurope then returned:
  #   409 InvalidResourceLocation: The resource 'claw-mock-sql-dev' already
  #   exists in location 'northeurope' ... cannot be created in 'westeurope'
  # No server object or DNS record exists under that name and `az resource
  # show` reports ResourceNotFound, so there is nothing to delete and the
  # reservation had not expired after ~35 minutes. A new name sidesteps it.
  # Keeps the ${var.env} suffix so test/prod get their own server — Azure SQL
  # server names are globally unique DNS labels (<name>.database.windows.net),
  # so a static name would collide across environments.
  sql_server_name = "claw-mock-sqlserver-${var.env}"
}

# Get existing resource group
data "azurerm_resource_group" "rg" {
  name = local.resource_group_name
}

# Lookup the AKS admin group by display name. The object ID changes per
# tenant, but the group name is stable — easier to keep this in tfvars.
data "azuread_group" "aks_admin" {
  display_name     = var.aks_admin_group_name
  security_enabled = true
}

# Lookup the SQL data-admins group by display name. This group is the
# Entra admin principal of the Azure SQL server (its members can manage
# every database on the server). Members: cameron-howe (the claw-code
# bot's Entra user) and the deploy identity deploy-claw-mock-dev.
data "azuread_group" "sql_admins" {
  display_name     = var.sql_admin_group_name
  security_enabled = true
}

# Get the deploy managed identity (deploy-claw-mock-dev). Pre-existing,
# with federated credentials for this repo's GitHub `dev` environment.
data "azurerm_user_assigned_identity" "deploy_identity" {
  name                = "deploy-claw-mock-dev"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Identity assigned to the Azure SQL server itself (not to any workload).
# Pre-existing and already granted Directory.Read, which is what lets the
# server resolve Entra principals for CREATE USER ... FROM EXTERNAL PROVIDER.
data "azurerm_user_assigned_identity" "sql_identity" {
  name                = var.sql_identity_name
  resource_group_name = data.azurerm_resource_group.rg.name
}
