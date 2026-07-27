#!/bin/bash
# mock-runner: backgrounded subprocess inside the claw-mock container.
#
# Runs one hourly database-mock turn: `openclaw agent --local --deliver`
# with the mock prompt. The agent reads the MOCKING-*.md manuals from the
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
trap 'rm -rf "$LOCK_DIR"' EXIT

{
  echo "[$(date -Iseconds)] mock run starting (session $SESSION_ID)"
  timeout -k 60 "$TIMEOUT_SECONDS" openclaw agent \
    --local \
    --session-id "$SESSION_ID" \
    --timeout "$TIMEOUT_SECONDS" \
    --deliver \
    --message-file /usr/local/share/claw-mock/mock-prompt.md
  rc=$?
  echo "[$(date -Iseconds)] mock run finished rc=$rc"
} >> "$LOG_FILE" 2>&1
