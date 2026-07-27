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
