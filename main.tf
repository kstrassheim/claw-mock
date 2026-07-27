terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform"
    storage_account_name = "mytofustates"
    container_name       = "claw-mock"
    key                  = "dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

provider "kubernetes" {
  # For CI: set env vars ARM_USE_OIDC=true, ARM_USE_AZUREAD_AUTH=true, then run
  # `kubelogin convert-kubeconfig -l azurecli` to use Entra auth (requires kubelogin binary).
  # For local dev without AAD: use the admin kubeconfig directly.
  # We use the admin kubeconfig here so Terraform can run locally without kubelogin.
  config_path = "/tmp/kubeconfig_clawmock"
}

provider "helm" {
  kubernetes = {
    config_path = "/tmp/kubeconfig_clawmock"
  }
}

data "azurerm_client_config" "current" {}

locals {
  resource_group_name  = "claw-mock-dev"
  cluster_name         = var.cluster_name
  location             = var.location
  storage_account_name = var.storage_account_name
  namespace            = var.namespace
  aks_version          = "1.35.3"
  sql_server_name      = "claw-mock-sql-${var.env}"
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

# Get existing resource group
data "azurerm_resource_group" "rg" {
  name = local.resource_group_name
}

# Create the claw-mock namespace (needed for NetworkPolicies and later K8s resources)
resource "kubernetes_namespace" "claw-mock" {
  metadata {
    name = var.namespace
    labels = {
      "environment" = var.env
      "project"     = "claw-mock"
    }
  }
  # Namespace may be pre-created manually — don't fail if it already exists
  lifecycle {
    ignore_changes = [metadata]
  }
}

# Get the deploy managed identity (deploy-claw-mock-dev). Pre-existing,
# with federated credentials for this repo's GitHub `dev` environment.
data "azurerm_user_assigned_identity" "deploy_identity" {
  name                = "deploy-claw-mock-dev"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# =============================================================================
# PV Storage Account
# =============================================================================
resource "azurerm_storage_account" "pv" {
  name                       = local.storage_account_name
  resource_group_name        = data.azurerm_resource_group.rg.name
  location                   = data.azurerm_resource_group.rg.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

# Create a file share in the storage account (for K8s PV)
resource "azurerm_storage_share" "claw_mock" {
  name               = "claw-mock"
  storage_account_id = azurerm_storage_account.pv.id
  quota              = 50 # 50 GiB
}

# =============================================================================
# Azure Container Registry — for the custom claw-mock image
# =============================================================================
resource "azurerm_container_registry" "acr" {
  name                = "clwmock${var.env}${var.unique_suffix}" # clwmock + env + suffix, max 50 chars
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false # Entra-only auth, no admin user

  public_network_access_enabled = true # AKS must be able to pull; restrict via NSG rules if needed

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

# Grant the deploy identity AcrPull (used by GitHub Actions for `az acr login`
# and by `az acr import` when mirroring the upstream openclaw base image).
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_user_assigned_identity.deploy_identity.principal_id
}

# Grant the AKS *kubelet* identity AcrPull. AKS uses a separate auto-created
# kubelet managed identity (NOT the cluster's SystemAssigned identity, NOT
# the deploy identity above) to pull images for pods. Without this role the
# kubelet hits "401 Unauthorized" when trying to pull from our ACR.
resource "azurerm_role_assignment" "acr_pull_aks_kubelet" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "container_registry_login_server" {
  description = "ACR login server for docker push/pull"
  value       = azurerm_container_registry.acr.login_server
}

# =============================================================================
# AKS Cluster
# =============================================================================
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.cluster_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  dns_prefix          = "claw-mock"
  kubernetes_version  = local.aks_version
  sku_tier            = "Free"

  default_node_pool {
    name                        = "default"
    vm_size                     = var.node_size
    node_count                  = var.node_count
    os_disk_size_gb             = 30
    os_disk_type                = "Managed"
    type                        = "VirtualMachineScaleSets"
    temporary_name_for_rotation = "tmpdefault"
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = [data.azuread_group.aks_admin.object_id]
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  tags = {
    environment = var.env
    project     = "claw-mock"
  }
}

# Grant the AKS admin group Azure Kubernetes Service RBAC Cluster Admin on the
# cluster scope. This allows Entra-authenticated users (via kubelogin) to
# access the cluster. Note: azure_rbac_enabled = true is set on the AKS
# cluster, so Azure RBAC governs access.
resource "azurerm_role_assignment" "aks_admin" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azuread_group.aks_admin.object_id
}

# =============================================================================
# Azure SQL Server (MSSQL) — cheapest tier, 2 databases
#
# Server-level admin is the Entra group local-data-admins-claw-mock-dev
# (referenced via the azuread_group data source above — never hardcoded
# object IDs). A SQL admin login also exists because the azurerm provider
# requires one unless Entra-only auth is enabled; its password is a
# random value that lives only in Terraform state and is not used by any
# pipeline step or by the bot.
# =============================================================================
resource "random_password" "sql_admin" {
  length  = 32
  special = false
}

resource "azurerm_mssql_server" "sql" {
  name                         = local.sql_server_name
  resource_group_name          = data.azurerm_resource_group.rg.name
  location                     = data.azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "clawmockadmin"
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  azuread_administrator {
    login_username = data.azuread_group.sql_admins.display_name
    object_id      = data.azuread_group.sql_admins.object_id
    tenant_id      = data.azurerm_client_config.current.tenant_id
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
# Bot database credentials
#
# The bot authenticates to both databases as the contained database user
# `clawmockbot` (created by each dacpac's post-deployment script with
# WITH PASSWORD = '$(BotPassword)'). The password is generated here and
# flows to two places:
#   1. this Kubernetes secret — read by the claw-mock pod via envFrom
#   2. the `bot_sql_password` sensitive output — read by the deploy
#      pipeline to pass /v:BotPassword to sqlpackage
# =============================================================================
resource "random_password" "bot_sql" {
  length      = 32
  special     = false
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
}

resource "kubernetes_secret" "claw_mock_db" {
  metadata {
    name      = "claw-mock-db"
    namespace = var.namespace
  }
  data = {
    SQL_SERVER_FQDN       = azurerm_mssql_server.sql.fully_qualified_domain_name
    SQL_BOT_USER          = "clawmockbot"
    SQL_BOT_PASSWORD      = random_password.bot_sql.result
    SQL_DB_ADVENTUREWORKS = azurerm_mssql_database.adventureworks.name
    SQL_DB_NORTHWIND      = azurerm_mssql_database.northwind.name
  }
  depends_on = [kubernetes_namespace.claw-mock]
}

# =============================================================================
# Default-deny-all NetworkPolicy — blocks ALL ingress/egress by default.
# Add explicit allow policies for each required access pattern.
# =============================================================================
resource "kubernetes_network_policy_v1" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = local.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# Allow DNS egress (required for cluster DNS resolution)
resource "kubernetes_network_policy_v1" "allow_dns" {
  metadata {
    name      = "allow-dns"
    namespace = local.namespace
  }
  spec {
    pod_selector {}
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
    policy_types = ["Egress"]
  }
}

# Allow HTTPS/443 egress (needed for cloud API calls, OIDC, image pulls,
# Telegram + MiniMax API access, etc.)
resource "kubernetes_network_policy_v1" "allow_https" {
  metadata {
    name      = "allow-https"
    namespace = local.namespace
  }
  spec {
    pod_selector {}
    egress {
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
    policy_types = ["Egress"]
  }
}

# Allow TDS/1433 egress — without this the bot's sqlcmd cannot reach the
# Azure SQL server (default-deny-all blocks it).
resource "kubernetes_network_policy_v1" "allow_mssql" {
  metadata {
    name      = "allow-mssql"
    namespace = local.namespace
  }
  spec {
    pod_selector {}
    egress {
      ports {
        protocol = "TCP"
        port     = "1433"
      }
    }
    policy_types = ["Egress"]
  }
}

# =============================================================================
# Terraform Output
# =============================================================================
output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_fqdn" {
  description = "AKS cluster FQDN"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "storage_account_name" {
  description = "PV storage account name (Entra-only auth, no keys)"
  value       = azurerm_storage_account.pv.name
}

output "storage_share_name" {
  description = "PV storage share name"
  value       = azurerm_storage_share.claw_mock.name
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the Azure SQL server"
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_databases" {
  description = "Mock databases on the SQL server"
  value       = [azurerm_mssql_database.adventureworks.name, azurerm_mssql_database.northwind.name]
}

output "bot_sql_password" {
  description = "Password of the contained database user clawmockbot (passed to sqlpackage /v:BotPassword by the deploy pipeline)"
  value       = random_password.bot_sql.result
  sensitive   = true
}

output "kubeconfig" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "deploy_identity_client_id" {
  description = "Client ID of the deploy-claw-mock-dev managed identity"
  value       = data.azurerm_user_assigned_identity.deploy_identity.client_id
}
