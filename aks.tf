# =============================================================================
# AKS cluster and everything that lives on/around it: the cluster itself,
# the ACR for the claw-mock image, the Azure Files PV storage account,
# the Kubernetes namespace, NetworkPolicies, and the workload-identity
# federated credential for the bot pod.
# =============================================================================

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

# =============================================================================
# PV Storage Account
# =============================================================================
resource "azurerm_storage_account" "pv" {
  name                       = local.storage_account_name
  resource_group_name        = data.azurerm_resource_group.rg.name
  location                   = local.location
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
  location            = local.location
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
  location            = local.location
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

  # Azure Workload Identity: the claw-mock pod authenticates to Azure SQL
  # as the deploy identity (deploy-claw-mock-dev) via a projected
  # service-account token — no SQL password, no client secret anywhere.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

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

# Identity the bot pod runs as. Deliberately separate from the deploy
# identity, and deliberately holds NO Azure RBAC at all.
#
# The pod previously federated onto deploy-claw-mock-dev, which is Owner on
# this resource group and Storage Blob Data Contributor on the Terraform state
# container. A bot whose whole job is inserting rows into two databases does
# not need — and should not have — the ability to rewrite the infrastructure
# or the state file. Its only privileges are the database roles that
# init-sql-permissions.sql grants it (db_datawriter + db_datareader).
#
# Created here rather than referenced as a pre-existing object because it
# needs no tenant-admin grant: no directory role, no subscription role. The
# deploy identity is Owner on this resource group, so it can create it.
resource "azurerm_user_assigned_identity" "pod" {
  name                = "claw-mock-pod-${var.env}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = local.location

  tags = {
    environment = var.env
    project     = "claw-mock"
    purpose     = "claw-mock bot pod workload identity"
  }
}

# Federated credential that lets the claw-mock Kubernetes service account
# (namespace/SA: claw-mock/claw-mock) exchange its projected token for an
# Entra token of the pod identity. This is the pod's ONLY credential —
# no keys, no secrets. The deploy pipeline annotates the SA with the
# identity's client ID at deploy time (pod_identity_client_id output).
resource "azurerm_federated_identity_credential" "claw_mock_workload" {
  name                = "claw-mock-workload"
  resource_group_name = data.azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.pod.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:claw-mock"
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
# Outputs
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

output "kubeconfig" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "deploy_identity_client_id" {
  description = "Client ID of the deploy-claw-mock-dev managed identity"
  value       = data.azurerm_user_assigned_identity.deploy_identity.client_id
}

# Consumed by deploy.yml to annotate the claw-mock service account
# (azure.workload.identity/client-id). This is the identity the pod actually
# authenticates as — not the deploy identity.
output "pod_identity_client_id" {
  description = "Client ID of the claw-mock pod's workload identity"
  value       = azurerm_user_assigned_identity.pod.client_id
}
