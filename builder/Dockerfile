# Custom openclaw image for the claw-mock database-mocking agent.
# Based on the claw-code builder but WITHOUT everything that doesn't
# belong to database mocking:
#   - no gh CLI / github-mcp-server (bot has no GitHub access)
#   - no terraform / aws / gcloud / aliyun CLIs and their MCP wrappers
#   - no code-server, no debug MCP, no issue-watcher/tester subsystem
#   - no Mistral / Moonshot keys — MiniMax M3 is the only model
#
# What IS here: the openclaw base, kubectl (for the db-mocker CronJob
# spawn + chat skill), sqlcmd (go-sqlcmd) for talking to Azure SQL, and
# the db-mocker scripts.
#
# Args come from .github/workflows/deploy.yml build step.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Strip openclaw skills that expand the agent's capabilities at runtime:
#   - mcporter      — dynamic MCP-server gateway (loads tools over HTTP/stdio,
#                     bypasses our static MCP allowlist)
#   - skill-creator — guides the agent to write new skill files
USER root
RUN rm -rf /app/skills/mcporter /app/skills/skill-creator

# kubectl — needed by the db-mocker CronJob (finds the main pod and
# kubectl-execs the mock-runner into it) and by the `mocker` chat skill.
ARG KUBECTL_VERSION
ARG SQLCMD_VERSION
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates bzip2 tzdata \
 && ln -snf /usr/share/zoneinfo/Europe/Zurich /etc/localtime \
 && echo "Europe/Zurich" > /etc/timezone \
 && ARCH=$(dpkg --print-architecture) \
 && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
 && chmod 0755 /usr/local/bin/kubectl \
 && /usr/local/bin/kubectl version --client=true --output=yaml | head -3 \
 && curl -fsSL -o /tmp/sqlcmd.tar.bz2 \
      "https://github.com/microsoft/go-sqlcmd/releases/download/v${SQLCMD_VERSION}/sqlcmd-linux-${ARCH}.tar.bz2" \
 && tar -xjf /tmp/sqlcmd.tar.bz2 -C /usr/local/bin \
 && chmod 0755 /usr/local/bin/sqlcmd \
 && rm -f /tmp/sqlcmd.tar.bz2 \
 && /usr/local/bin/sqlcmd --version \
 && apt-get purge -y --auto-remove curl \
 && rm -rf /var/lib/apt/lists/*

# db-mocker scripts:
#   cron-mock-spawn  — runs in the db-mocker CronJob pod; finds the main
#                      claw-mock pod and backgrounds mock-runner there
#                      (so the CronJob pod itself exits immediately).
#   mock-runner      — runs inside the main pod; executes the hourly
#                      mock turn via `openclaw agent --local --deliver`.
#
# Paths are relative to the build context, which deploy.yml sets to
# ./builder (not the repo root) — so no `builder/` prefix here. With the
# prefix, buildx looked for builder/builder/* and failed the build with
# "/builder/mock-prompt.md: not found".
COPY cron-mock-spawn.sh /usr/local/bin/cron-mock-spawn
COPY mock-runner.sh     /usr/local/bin/mock-runner
COPY mock-prompt.md     /usr/local/share/claw-mock/mock-prompt.md
RUN chmod 0755 /usr/local/bin/cron-mock-spawn /usr/local/bin/mock-runner \
 && chown -R 1000:1000 /usr/local/share/claw-mock

# Issue #15 — bot logs and messages must carry Zürich local time
# (CET/CEST, DST handled by the IANA zone) instead of the base image's UTC.
ENV TZ=Europe/Zurich

USER 1000
