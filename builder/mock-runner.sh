#!/bin/bash
# mock-runner: backgrounded subprocess inside the claw-mock container.
#
# Runs one hourly database-mock turn: `openclaw agent --local --deliver`
# with the mock prompt. The agent reads the MOCK-*.md manuals from the
# workspace, mocks the databases via sqlcmd, and its final message — the
# per-database / per-fact-dimension / per-table row-count summary (or the
# failure with the SQL error) — is delivered to the main session's
# channel (Telegram).
#
# A mkdir lock prevents overlapping runs if a previous run is still
# going when the next hourly tick fires.
set -uo pipefail

STATE_ROOT="${HOME:-/home/node}/.openclaw"
LOCK_DIR="$STATE_ROOT/.mock-lock"
LOG_DIR="$STATE_ROOT/mock-logs"
LOG_FILE="$LOG_DIR/mock-$(date +%Y%m%d-%H%M).log"
SESSION_ID="mock-run-$(date +%Y%m%d-%H%M)"
TIMEOUT_SECONDS="${MOCK_RUN_TIMEOUT:-3500}"

mkdir -p "$LOG_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date -Iseconds)] mock lock held — previous run still active; skipping this tick" >> "$LOG_FILE"
  exit 0
fi
echo "$BASHPID $(date -Iseconds)" > "$LOCK_DIR/owner"

# The turn gets a state directory of its own. openclaw 2026.10 refuses
# `agent --local` while a Gateway runs on the same state directory:
#
#   A Gateway is running for this state directory (pid 7, port 18789). Run
#   without --local to use it, or stop the Gateway first
#
# and the Gateway always runs in this pod, on ~/.openclaw — so every hourly
# run would die before the model is called, with a healthy pod and a green
# CronJob. Both Gateway locks live under the state directory, so a turn on
# another OPENCLAW_STATE_DIR does not collide with it. The config and the
# workspace (the MOCK-*.md manuals, TOOLS.md, the mocker skill) stay the
# Gateway's own, named explicitly because both default to paths under the
# state directory. One run is one session, so the directory goes with it.
AGENT_STATE_DIR="${TMPDIR:-/tmp}/openclaw-agent-runs/$SESSION_ID"
mkdir -p "$AGENT_STATE_DIR"
trap 'rm -rf "$LOCK_DIR" "$AGENT_STATE_DIR"' EXIT

# Where the run report goes. Each run uses its own --session-id, so it has no
# channel binding of its own and bare --deliver fails with
# "Delivering to Telegram requires target <chatId>". The target is derived from
# the paired owner in the persistent config rather than hardcoded, so pairing
# once is enough — render-config.sh carries commands.ownerAllowFrom forward
# across redeploys.
#
# If nobody has paired yet the run still happens; the report just stays in this
# log instead of being delivered.
TELEGRAM_TARGET="$(python3 - "$STATE_ROOT/openclaw.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for entry in (cfg.get("commands", {}).get("ownerAllowFrom") or []):
    if isinstance(entry, str) and entry.startswith("telegram:"):
        print(entry.split(":", 1)[1].strip())
        break
PY
)"

DELIVERY_ARGS=()
if [ -n "$TELEGRAM_TARGET" ]; then
  DELIVERY_ARGS=(--deliver --reply-channel telegram --reply-to "$TELEGRAM_TARGET")
fi

{
  echo "[$(date -Iseconds)] mock run starting (session $SESSION_ID)"
  if [ -n "$TELEGRAM_TARGET" ]; then
    echo "[$(date -Iseconds)] report will be delivered to telegram:$TELEGRAM_TARGET"
  else
    echo "[$(date -Iseconds)] no paired telegram owner found — report stays in this log"
  fi
  OPENCLAW_STATE_DIR="$AGENT_STATE_DIR" \
  OPENCLAW_CONFIG_PATH="$STATE_ROOT/openclaw.json" \
  OPENCLAW_WORKSPACE_DIR="$STATE_ROOT/workspace" \
  timeout -k 60 "$TIMEOUT_SECONDS" openclaw agent \
    --local \
    --session-id "$SESSION_ID" \
    --timeout "$TIMEOUT_SECONDS" \
    "${DELIVERY_ARGS[@]}" \
    --message-file /usr/local/share/claw-mock/mock-prompt.md
  rc=$?
  echo "[$(date -Iseconds)] mock run finished rc=$rc"
} >> "$LOG_FILE" 2>&1
