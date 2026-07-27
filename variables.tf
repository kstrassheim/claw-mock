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
  description = "Azure region"
  default     = "northeurope"
  type        = string
}

variable "node_size" {
  description = "VM size for AKS node pool. Default is arm64 (Standard_D2pds_v5, 2 vCPU / 8 GiB) — matches the openclaw image build target (linux/arm64)."
  default     = "Standard_D2pds_v5"
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the default pool"
  default     = 1
  type        = number
}

variable "storage_account_name" {
  description = "Storage account name for Azure Files PV (must be globally unique, ~24 chars max, e.g. clwmockdev)"
  default     = "clwmockdev"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for claw-mock"
  default     = "claw-mock"
  type        = string
}

variable "aks_admin_group_name" {
  description = "Display name of the Entra ID security group granted AKS cluster-admin RBAC. The group must already exist; Terraform only references it by name. Defaults to the SQL data-admins group because it is the only pre-existing group for this project (its members — cameron-howe and deploy-claw-mock-dev — then also get cluster-admin for kubelogin access). Point this at a dedicated claw-mock-aks-admin group later if you want to split the duties."
  type        = string
  default     = "local-data-admins-claw-mock-dev"
}

variable "sql_admin_group_name" {
  description = "Display name of the Entra ID security group assigned as the Azure SQL server's Entra admin principal. The group must already exist; Terraform only references it by name (never a hardcoded object ID)."
  type        = string
  default     = "local-data-admins-claw-mock-dev"
}

variable "unique_suffix" {
  description = "Unique suffix appended to globally-unique resource names (max 4 chars, e.g. 'dev1'). Used to make the ACR name unique across deployments."
  type        = string
  default     = "dev1"
}
