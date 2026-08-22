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

# Strip every bundled openclaw skill the allowlist does not name.
#
# This used to remove two by name — mcporter (a dynamic MCP gateway that
# bypasses the static MCP allowlist) and skill-creator (which teaches the
# agent to write new skill files) — and keep everything else. That is the
# wrong way round: an upstream release that adds a third ships it to the agent
# silently, and nobody finds out until it is used. The list of what may
# survive lives in BUNDLED_SKILLS_ALLOWED, and is currently empty: this bot's
# only skill, `mocker`, arrives as a reviewed ConfigMap mount.
#
# THE ASSERTION IS THE POINT. `rm -rf` on a path upstream has moved exits 0
# and removes nothing. That failure is silent and total — every bundled skill
# ships and the build stays green. So after removing, this enumerates what is
# actually loadable and fails the build on anything the allowlist does not
# name. SKILLS-LOCKED-ASSERT is what CI greps for, so deleting this block is
# itself a CI failure rather than a quiet loss of the control.
#
# SKILLS DO NOT ALL LIVE IN /app/skills. They also ship inside extensions at
# /app/extensions/<ext>/skills/<name>/ and again in the built mirror under
# /app/dist/. The old two-path `rm -rf` could not have removed those even if
# it had named them. Removal and assertion are therefore driven by the SAME
# find, so the two passes cannot disagree about what counts as a skill.
USER root
COPY BUNDLED_SKILLS_ALLOWED /usr/local/share/BUNDLED_SKILLS_ALLOWED
COPY --chmod=0755 list-loadable-skills.sh /usr/local/bin/list-loadable-skills
COPY --chmod=0755 lock-skill-dirs.sh      /usr/local/bin/lock-skill-dirs
RUN set -eu; \
    sed 's/#.*//' /usr/local/share/BUNDLED_SKILLS_ALLOWED | awk 'NF' | sort -u > /tmp/allowed; \
    find /app -name SKILL.md -not -path '*/node_modules/*' 2>/dev/null \
      | grep '/skills/' \
      | sed -E 's#(.*/skills/[^/]+)/.*#\1#' | sort -u > /tmp/roots || true; \
    while IFS= read -r root; do \
      [ -n "$root" ] || continue; \
      [ -d "$root" ] || continue; \
      name="$(basename "$root")"; \
      if grep -qxF "$name" /tmp/allowed; then \
        echo "keep   $name  ($root)"; \
      else \
        echo "strip  $name  ($root)"; \
        rm -rf "$root"; \
      fi; \
    done < /tmp/roots; \
    echo "SKILLS-LOCKED-ASSERT: verifying nothing unlisted survived"; \
    /usr/local/bin/list-loadable-skills > /tmp/remaining; \
    if [ -s /tmp/remaining ] && grep -vxF -f /tmp/allowed /tmp/remaining > /tmp/extra; then \
      echo "FATAL: bundled skills survived the strip that the allowlist does not name:" >&2; \
      cat /tmp/extra >&2; \
      exit 1; \
    fi; \
    rm -f /tmp/allowed /tmp/roots /tmp/remaining /tmp/extra; \
    echo "SKILLS-LOCKED-ASSERT: ok"

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
