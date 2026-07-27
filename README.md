# claw-mock

An fully automated live database mocker.

An openclaw bot runs in AKS and, once an hour, writes plausible new rows into
two Azure SQL databases (AdventureWorks and Northwind) so they look like live
systems rather than static samples. It inserts new rows, updates existing
ones (order status, stock, prices, contact data), and trims old rows so
every table stays inside its size band — dimension rows are only deleted
when nothing references them. A few rows per run deliberately carry edge
cases (max-length strings, unicode, numeric extremes) so DWH import jobs
are tested against column limits. What it writes is governed by a mocking
manual per database, which classifies every table as fact or dimension and
sets the timing rules. After each run the bot reports the rows it
inserted, updated and deleted, grouped by database and by fact/dimension.

## Prerequisites

Terraform provisions the infrastructure, but a number of Entra objects must
exist **before** the first deploy. Terraform references them through `data`
sources and never creates or modifies them, so a missing one fails the run.

### Managed identities

**`deploy-claw-mock-dev`** — used by GitHub Actions to deploy, and by the bot
pod at runtime via AKS workload identity.

| Permission | Scope | Why |
| --- | --- | --- |
| Owner | resource group `claw-mock-dev` | create AKS, ACR, storage, SQL |
| Storage Blob Data Contributor | container `claw-mock` on storage account `mytofustates` | read/write the Terraform state (the backend uses `use_azuread_auth`, so no account keys) |
| Directory Readers | tenant | Terraform looks the Entra groups up by display name (`azuread_group` data sources); without it `terraform plan` fails with a Graph 403 |
| Member of `local-data-admins-claw-mock-dev` | — | makes it admin on the SQL server, which is how the pipeline publishes dacpacs and runs `init-sql-permissions.sql` |

It also needs a **federated credential** for GitHub OIDC with subject
`repo:<owner>/claw-mock:environment:dev`. The second federated credential, for
AKS workload identity, is created by Terraform.

`AcrPull` is granted by Terraform — it is not a prerequisite.

**`claw-mock-pod-<env>`** — the identity the bot pod runs as. **Created by
Terraform, not a prerequisite.**

It deliberately holds **no Azure RBAC at all**. Its only privileges are the
database roles `init-sql-permissions.sql` grants it (`db_datawriter` +
`db_datareader`). It is separate from the deploy identity on purpose: the
deploy identity is Owner on the resource group and can rewrite the Terraform
state, and a bot whose job is inserting rows into two databases must not
inherit that. The federated credential for
`system:serviceaccount:claw-mock:claw-mock` sits on this identity, and the
pipeline annotates the service account with its client ID.

**`claw-code-mi-sqlserver-dev`** — attached to the Azure SQL server itself, not
to any workload.

| Permission | Scope | Why |
| --- | --- | --- |
| Directory Readers | tenant | lets the server resolve Entra principals for `CREATE USER ... FROM EXTERNAL PROVIDER`; without it that fails with "Principal could not be found" |

### Entra groups

| Group | Purpose |
| --- | --- |
| `claw-mock-aks-admin` | granted AKS cluster-admin through Azure RBAC. Without membership there is no access to the cluster. Wired via `var.aks_admin_group_name`. |
| `local-data-admins-claw-mock-dev` | Entra admin principal of the SQL server. The server is Entra-only, so this is the only route to administer it. Wired via `var.sql_admin_group_name`. |

### Other

- Resource group `claw-mock-dev` must exist.
- Storage account `mytofustates` with a container named `claw-mock` for state.
- A GitHub environment named `dev` holding these secrets:

  | Secret | Used for |
  | --- | --- |
  | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | OIDC login as the deploy identity |
  | `MINIMAX_API_KEY` | the bot's only model (MiniMax M3) |
  | `TELEGRAM_BOT_TOKEN` | Telegram channel |

  The gateway auth token is **not** a secret here — `apply-secrets` mints one on
  first deploy and reuses it afterwards.

## Authentication

No password exists anywhere in this project.

- **Pipeline → Azure**: OIDC federated credential on the deploy identity.
- **Terraform → state**: Entra auth on the storage container.
- **Pipeline → SQL**: the deploy identity is a member of the SQL admin group;
  `sqlpackage` and `sqlcmd` use `Active Directory Default`.
- **Bot pod → SQL**: AKS workload identity as `claw-mock-pod-<env>`, which has
  no Azure RBAC. The webhook injects a federated token into the pod and
  `sqlcmd --authentication-method=ActiveDirectoryDefault` picks it up; the
  identity holds `db_datawriter` + `db_datareader` in each database, granted by
  `init-sql-permissions.sql`.

  One wrinkle: openclaw's exec tool filters the environment it hands to
  commands, and `AZURE_CLIENT_ID` does not survive it (while
  `AZURE_FEDERATED_TOKEN_FILE` and `SQL_*` do). The client ID is therefore also
  published as `SQL_BOT_CLIENT_ID` in the `claw-mock-db` secret, and `TOOLS.md`
  tells the bot to prefix its command with
  `AZURE_CLIENT_ID="${SQL_BOT_CLIENT_ID}"`. Without that the connection fails
  with "WorkloadIdentityCredential: no client ID specified".

The `claw-mock-db` secret carries only the server FQDN and the database names.

## Deploy pipeline

`.github/workflows/deploy.yml` runs on merge to `main`:

```
terraform-apply
├── dacpac-build-deploy ──→ grant-sql-access
├── apply-secrets
└── build-and-push-image ──→ deploy-to-aks
```

- **terraform-apply** — AKS, ACR, storage, SQL server and both databases.
- **dacpac-build-deploy** — builds both `.sqlproj` and publishes schema + seed
  data to Azure SQL.
- **grant-sql-access** — runs `init-sql-permissions.sql` against `master` and
  each database. It runs *after* the dacpac publish, because a publish
  reconciles database objects against the package and grants applied earlier are
  not guaranteed to survive. The script is idempotent.
- **apply-secrets** — renders `claw-mock-secrets` into the cluster.
- **build-and-push-image** / **deploy-to-aks** — build the image and roll out.
  Deploying needs neither the schema nor the grants (the bot only touches the
  databases on its hourly run), so it runs in parallel with them.

## Mocking

- `MOCK-AdventureWorks.md` and `MOCK-Northwind.md` — one manual per
  database: table classification (fact / dimension / static reference), rows per
  run, live-timing and integrity rules. Mounted into the pod as a ConfigMap
  generated at deploy time.
- `builder/mock-prompt.md` — the prompt for each hourly run, including the
  report format.
- `k8s/050-db-mocker.yaml` — the hourly CronJob.

## Region and architecture

Everything lives in `westeurope`. AKS and SQL are deliberately co-located —
splitting them bills cross-region egress on every query. Two earlier regions did
not work: `switzerlandnorth` could not provision the AKS node size, and
`northeurope` could not provision Azure SQL at all.

The node pool is arm64 (`Standard_D2pds_v5`) and the image is built for
`linux/arm64`. Those two are one decision — changing either without the other
leaves the pod unschedulable.
