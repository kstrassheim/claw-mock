# =============================================================================
# Terraform core: version constraints, providers, and remote state backend.
# State lives in the mytofustates storage account (Entra auth, no keys).
# =============================================================================
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

# Kubernetes/Helm credentials are read straight off the AKS resource rather
# than from a kubeconfig file on disk.
#
# The previous version pointed both providers at /tmp/kubeconfig_clawmock,
# written by an `az aks get-credentials` step in deploy.yml. That file cannot
# exist on the run that first creates the cluster, so the providers silently
# fell back to their default host (localhost:80) and every kubernetes_* resource
# failed with "dial tcp [::1]:80: connect: connection refused". The workflow
# worked around it by expecting the first apply to fail and asking for a manual
# re-run.
#
# Sourcing from azurerm_kubernetes_cluster.aks instead makes the credentials a
# resource attribute, so Terraform resolves them after the cluster is created
# and the whole thing converges in a single apply. kube_admin_config is the
# local admin credential (cert-based, no kubelogin needed); it is populated
# because local_account_disabled is not set on the cluster. Entra RBAC still
# governs normal user access via azure_rbac_enabled.
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_admin_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_admin_config[0].cluster_ca_certificate)
  }
}

data "azurerm_client_config" "current" {}
