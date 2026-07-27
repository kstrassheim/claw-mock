# claw-mock — database-mocking agent capabilities

This file is the bot's self-description: when you don't know whether a
capability is wired, look here first. Anything **not** mentioned here is
**not wired** — surface that to the user instead of inventing tool
names or pretending you can act.

## What this image bundles

The container image (built from `builder/Dockerfile`) ships:

- **openclaw** (base image) with **MiniMax M3** as the only model
  provider. No Mistral, no Moonshot — MINIMAX_API_KEY is mandatory.
- **`sqlcmd`** (go-sqlcmd) — the tool you use for every database
  interaction. See the "Database access" section below.
- **`kubectl`** — used by the db-mocker CronJob spawn and by the
  `mocker` chat skill.
- **`mock-runner` / `cron-mock-spawn`** — the hourly mock-run plumbing
  (see k8s/050-db-mocker.yaml).

## What is deliberately NOT in this image

- No `gh` CLI, no GitHub MCP, no `GITHUB_TOKEN` — this bot does not
  push code. If the user asks you to open a PR or read an issue, tell
  them this bot has no GitHub access by design.
- No terraform / aws / gcloud / aliyun CLIs and no cloud MCP servers.
- No code-server, no debug MCP, no issue-watcher / tester subsystems.

## Database access

Connection parameters are in your environment (from the `claw-mock-db`
Kubernetes secret, created by Terraform). The Azure SQL server is
**Entra-only** — there is no SQL user and no password anywhere. Your
pod carries an Azure Workload Identity token for the deploy identity
(`deploy-claw-mock-dev`, member of the server's Entra-admin group);
the webhook injects `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` /
`AZURE_FEDERATED_TOKEN_FILE` at pod start.

| Env var | Value |
|---|---|
| `SQL_SERVER_FQDN` | Azure SQL server FQDN |
| `SQL_DB_ADVENTUREWORKS` | `AdventureWorks` |
| `SQL_DB_NORTHWIND` | `Northwind` |

Connect like this:

```bash
sqlcmd -S "tcp:${SQL_SERVER_FQDN},1433" -d "${SQL_DB_ADVENTUREWORKS}" \
       --authentication-method=ActiveDirectoryDefault -l 30 -N -C -h-1 -W
```

`--authentication-method=ActiveDirectoryDefault` picks up the
workload-identity token via the DefaultAzureCredential chain.
`-N -C` = encrypt + trust server certificate (Azure SQL terminates TLS
with its own cert chain).

## Mocking

The mocking manuals live at `~/.openclaw/workspace/MOCKING/`:

- `MOCKING-AdventureWorks.md`
- `MOCKING-Northwind.md`

They define the fact/dimension table classification, per-table mock
behaviour, and the live-timing rules. Read them at the start of every
mock run. The hourly run itself is driven by the `db-mocker` CronJob —
control it via the `mocker` skill (`mocker status|start|stop|run|logs`).

After every mock run, report the number of rows you created, grouped by
database → fact/dimension → table, or the failure with the exact SQL
error message.
