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

OpenTofu provisions the infrastructure, but a number of Entra objects must
exist **before** the first deploy. OpenTofu references them through `data`
sources and never creates or modifies them, so a missing one fails the run.

### Managed identities

**`deploy-claw-mock-dev`** — used by GitHub Actions to deploy, and by the bot
pod at runtime via AKS workload identity.

| Permission | Scope | Why |
| --- | --- | --- |
| Owner | resource group `claw-mock-dev` | create AKS, ACR, storage, SQL |
| Storage Blob Data Contributor | container `claw-mock` on storage account `mytofustates` | read/write the OpenTofu state (the backend uses `use_azuread_auth`, so no account keys) |
| Directory Readers | tenant | OpenTofu looks the Entra groups up by display name (`azuread_group` data sources); without it `tofu plan` fails with a Graph 403 |
| Member of `local-data-admins-claw-mock-dev` | — | makes it admin on the SQL server, which is how the pipeline publishes dacpacs and runs `init-sql-permissions.sql` |

It also needs a **federated credential** for GitHub OIDC with subject
`repo:<owner>/claw-mock:environment:dev`. The second federated credential, for
AKS workload identity, is created by OpenTofu.

`AcrPull` is granted by OpenTofu — it is not a prerequisite.

**`claw-mock-pod-<env>`** — the identity the bot pod runs as. **Created by
OpenTofu, not a prerequisite.**

It deliberately holds **no Azure RBAC at all**. Its only privileges are the
database roles `init-sql-permissions.sql` grants it (`db_datawriter` +
`db_datareader`). It is separate from the deploy identity on purpose: the
deploy identity is Owner on the resource group and can rewrite the OpenTofu
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
- **OpenTofu → state**: Entra auth on the storage container, and the state
  itself is encrypted with a Key Vault key (see below).
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
tofu-apply
├── dacpac-build-deploy ──┬─→ seed-databases
│                         └─→ grant-sql-access
├── apply-secrets
└── build-and-push-image ──→ deploy-to-aks
```

- **tofu-apply** — AKS, ACR, storage, SQL server and both databases.
- **dacpac-build-deploy** — builds both `.sqlproj` and publishes **schema only**
  to Azure SQL. The dacpacs carry no seed data.
- **seed-databases** — applies `seed/<database>.sql`, but only to a database
  whose user tables are all still empty. Seeding is a one-time concern and the
  bot owns the contents afterwards, so a database it has written to is never
  reseeded.
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
- `seed/<database>.sql` — initial contents, applied only to an empty database.
  Deliberately outside the `database/` projects: `MSBuild.Sdk.SqlProj` globs
  `**/*.sql` as schema, so a seed script left in there would be compiled into
  the dacpac.

## Region and architecture

Everything lives in `westeurope`. AKS and SQL are deliberately co-located —
splitting them bills cross-region egress on every query. Two earlier regions did
not work: `switzerlandnorth` could not provision the AKS node size, and
`northeurope` could not provision Azure SQL at all.

The node pool is arm64 (`Standard_D2pds_v5`) and the image is built for
`linux/arm64`. Those two are one decision — changing either without the other
leaves the pod unschedulable.

## State encryption

State lives in the `claw-mock` container of the `mytofustates` storage account
and is **encrypted by OpenTofu itself**, on top of Azure's storage encryption. A
fresh AES-GCM data key is generated per run and wrapped with the RSA key
`claw-mock` in the `kv-mytofustates` Key Vault, so key material never leaves the
vault.

- **HashiCorp Terraform cannot read this state.** Use `tofu`. The pipelines pin
  OpenTofu via `TOFU_VERSION` in `VERSIONS`.
- `var.app_name` is the single source of truth for both the state blob
  container and the Key Vault key name; the backend reads it directly, which
  relies on OpenTofu early evaluation and is not parseable by Terraform.
- `deploy-claw-mock-dev` holds `Key Vault Crypto User` scoped to that **single
  key object**, not to the vault, so it cannot decrypt another project's state.

Locally the key provider authenticates through your `az login` session. CI uses
GitHub OIDC, which needs `TF_VAR_use_oidc=true` plus `TF_VAR_arm_client_id` /
`TF_VAR_arm_tenant_id`. Those are separate from `ARM_USE_OIDC` / `ARM_USE_CLI`,
which configure the backend and the azurerm provider — the key provider does not
read `ARM_*` at all. The pipelines set both; if only one is set, that consumer
falls back to the Azure CLI credential and fails with *"Please specify only one
of subscription and tenant, not both"*.

## Skills lockdown

The bot has exactly one skill — `mocker`, defined in `k8s/050-db-mocker.yaml`
and mounted from the `claw-mock-skill-mocker` ConfigMap. It must not be able to
acquire another at runtime.

That is not a small control. A skill is just instructions the agent will
follow, so one it wrote for itself never went through a pull request and can
tell it to do anything the sandbox physically permits — which makes it the
shortest way around every other restriction here.

Two halves, and neither is sufficient alone:

**The image ships no bundled skill.** `builder/BUNDLED_SKILLS_ALLOWED` names
what may survive the strip, and it is deliberately empty. The Dockerfile
enumerates every loadable skill (`<...>/skills/<name>/SKILL.md`, including the
ones inside extensions and in the `/app/dist` mirror — they are not all under
`/app/skills`), removes what the list does not name, and then **asserts** that
nothing unlisted survived. The assertion is the point: `rm -rf` on a path
upstream has moved exits 0 and removes nothing, which is silent and total
failure with a green build.

**The skills directory is not the agent's.** `builder/lock-skill-dirs.sh` makes
every directory openclaw can load a skill from root-owned and read-only. It
runs in the init container **after** the recursive `chown -R 1000:1000` — a
chown afterwards would hand the directories straight back while the manifest
still read as locked. It fails closed: a missing binary refuses to start rather
than coming up writable with nothing reporting it.

### How it is checked

| Check | Where | What it proves |
|---|---|---|
| `builder/verify-skills-locked.sh` | CI job **Skills Lockdown** | Static, over the repo: the allowlist is honoured, the assertion exists and can fail the build, no self-extension skill is re-enabled through the plugin allowlist, the mounted skills are exactly the ConfigMaps this repo defines in both directions, and the lockdown runs after the chown. |
| `builder/verify-lockdown-effective.sh` | inside the built image, in **Docker Image Build** | Dynamic: runs the real lockdown against a scratch tree, then tries to defeat it as uid 1000. |
| `builder/list-loadable-skills` | build assertion **and** the image re-check | One definition of "what counts as a loadable skill", so the two cannot drift apart. |

The image build is gated on the static check — a green image next to a red
lockdown would read as "the image is fine".

The dynamic half also checks the two ways **over-locking** would break things:
the agent must still be able to write `workspace/`, and root must still be able
to mount a `SKILL.md` into a locked directory. Without that second one the pod
comes up with **no skills at all**, which looks like the feature being broken
rather than a permissions bug.

### Changing the skills

Add or change a skill in `k8s/` and mount it in `k8s/020-deployment.yaml`; the
static check fails if a ConfigMap defines a skill nothing mounts, or if
something is mounted without a matching ConfigMap. Keeping an upstream bundled
skill means naming it in `BUNDLED_SKILLS_ALLOWED`, in a pull request that says
what the bot needs it for.

The lockdown runs in the init container, so it takes effect on the **next pod
restart**, not on a ConfigMap update.
