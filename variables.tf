variable "app_name" {
  description = <<-EOT
    Canonical project name, and the single source of truth for three things
    that must agree:

      * the blob container in the mytofustates storage account holding this
        project's state (backend.container_name),
      * the RSA key in the kv-mytofustates Key Vault that wraps the state
        encryption data key (encryption.key_provider.vault_key_name),
      * the project name itself.

    Referencing a variable from the backend block is OpenTofu-only (early
    evaluation, resolved at `tofu init` before state exists) — HashiCorp
    Terraform cannot parse it. That is already true of the encryption block
    above it, so this adds no new constraint.
  EOT
  default     = "claw-mock"
  type        = string
}

variable "env" {
  description = "Environment name"
  default     = "dev"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name"
  default     = "claw-mock-aks"
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure region for every resource in this project. AKS and Azure SQL are
    deliberately kept in the same region — splitting them bills cross-region
    egress on every query the mock bot runs.

    History: switzerlandnorth could not provision the AKS node size
    (VMSizeNotSupported); northeurope could not provision Azure SQL at all
    ("ProvisioningDisabled: Provisioning is restricted in this region").
    westeurope serves both — Standard_D2pds_v5 is offered there, and the
    subscription already runs a SQL server in the region.
  EOT
  default     = "westeurope"
  type        = string
}

variable "node_size" {
  description = <<-EOT
    VM size for the AKS node pool. Standard_D2pds_v5 is arm64 (2 vCPU / 8 GiB)
    and must stay arm64: deploy.yml builds the image for linux/arm64 only, so
    an x86 node size would leave the bot pod unschedulable with an
    exec-format/no-matching-manifest error. Verified available in westeurope.

    To move to x86, change this AND the `platforms:` value in deploy.yml
    together — they are one decision, not two.
  EOT
  default     = "Standard_D2pds_v5"
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the default pool"
  default     = 1
  type        = number
}

variable "namespace" {
  description = "Kubernetes namespace for claw-mock"
  default     = "claw-mock"
  type        = string
}

variable "aks_admin_group_name" {
  description = <<-EOT
    Display name of the Entra security group granted AKS cluster-admin RBAC.
    The group must already exist; Terraform only references it by name.

    This is now the dedicated claw-mock-aks-admin group rather than the SQL
    data-admins group, so cluster administration and database administration
    are separate duties. Members of this group get cluster-admin via
    azure_rbac_enabled — without it there is no way in to the cluster.
  EOT
  type        = string
  default     = "claw-mock-aks-admin"
}

variable "sql_admin_group_name" {
  description = "Display name of the Entra ID security group assigned as the Azure SQL server's Entra admin principal. The group must already exist; Terraform only references it by name (never a hardcoded object ID)."
  type        = string
  default     = "local-data-admins-claw-mock-dev"
}

variable "sql_identity_name" {
  description = <<-EOT
    Name of the pre-existing user-assigned managed identity attached to the
    Azure SQL server. It must already hold Directory.Read on the tenant —
    that is what lets the server resolve Entra principals for
    `CREATE USER ... FROM EXTERNAL PROVIDER`. Referenced via a data source;
    Terraform never creates or modifies it.
  EOT
  type        = string
  default     = "claw-code-mi-sqlserver-dev"
}

variable "pod_identity_name" {
  description = <<-EOT
    Name of the managed identity the claw-mock pod authenticates as via AKS
    workload identity. init-sql-permissions.sql grants this principal access
    inside each database; the deploy pipeline substitutes it into the script.
  EOT
  type        = string
  default     = "deploy-claw-mock-dev"
}

variable "unique_suffix" {
  description = "Unique suffix appended to globally-unique resource names (max 4 chars, e.g. 'dev1'). Used to make the ACR name unique across deployments."
  type        = string
  default     = "dev1"
}

variable "use_oidc" {
  description = <<-EOT
    Authenticate the azure_vault state-encryption key provider with a GitHub
    OIDC token instead of the Azure CLI. Defaults to false so local runs use
    your `az login` session; CI sets TF_VAR_use_oidc=true.

    This has to be a block argument on the key provider. The provider does NOT
    read ARM_USE_OIDC / ARM_USE_CLI / ARM_CLIENT_ID / ARM_TENANT_ID from the
    environment the way the backend and the azurerm provider do -- setting
    those has no effect on it, and it silently falls through to
    AzureCLICredential, which then runs `az account get-access-token` with both
    --subscription and --tenant and fails with:
      ERROR: Please specify only one of subscription and tenant, not both
  EOT
  type        = bool
  default     = false
}

variable "arm_client_id" {
  description = "Client ID for the key provider when use_oidc is true. Empty locally; CI sets TF_VAR_arm_client_id."
  type        = string
  default     = ""
}

variable "arm_tenant_id" {
  description = "Tenant ID for the key provider when use_oidc is true. Empty locally; CI sets TF_VAR_arm_tenant_id."
  type        = string
  default     = ""
}
