# =============================================================================
# Stage 1: Infrastructure — Terraform variables (dev environment)
# =============================================================================
# Copy to terraform.tfvars and fill in real values.
# DO NOT commit real secrets to git — use GitHub Actions secrets + TF_VAR_* instead.

env                  = "dev"
cluster_name         = "claw-mock-aks"
location             = "northeurope"
node_size            = "Standard_D2pds_v5"
node_count           = 1
storage_account_name = "clwmockdev" # PV storage (Azure Files), globally unique, NOT mytofustates
namespace            = "claw-mock"
aks_admin_group_name = "local-data-admins-claw-mock-dev" # Entra security group with AKS cluster-admin RBAC
sql_admin_group_name = "local-data-admins-claw-mock-dev" # Entra security group = SQL server Entra admin
