#!/usr/bin/env bash

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

HOST="${BEADS_DOLT_SERVER_HOST:-100.107.173.83}"
PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
BEADS_DIR="${BEADS_DIR:-$HOME/.beads-runtime/.beads}"
LOG_FILE="$HOME/logs/dx/beads-health-alert.log"
# Active contract: no legacy sqlite/jsonl fallback in this alert path.
# Enable compatibility-only legacy diagnostics explicitly in non-canonical operators only.

mkdir -p "$(dirname "$LOG_FILE")"
{
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] beads-health-check start: contract=dolt-native-hub-spoke host=${HOST}:${PORT}"
} >>"$LOG_FILE"

if [[ ! -d "$BEADS_DIR" ]]; then
  echo "❌ active Beads runtime missing at $BEADS_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -f "$BEADS_DIR/metadata.json" || ! -f "$BEADS_DIR/config.yaml" ]]; then
  echo "❌ active Beads runtime missing metadata.json or config.yaml at $BEADS_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

cd "$HOME"

if ! command -v bd >/dev/null 2>&1; then
  echo "❌ bd CLI not found in PATH" | tee -a "$LOG_FILE"
  exit 1
fi

export BEADS_DOLT_SERVER_HOST="$HOST"
export BEADS_DOLT_SERVER_PORT="$PORT"

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️ jq is required for payload validation" | tee -a "$LOG_FILE"
  exit 1
fi

if command -v nc >/dev/null 2>&1; then
  if ! nc -z -w 2 "$HOST" "$PORT" >/dev/null 2>&1; then
    echo "❌ cannot reach Beads SQL endpoint ${HOST}:${PORT}" | tee -a "$LOG_FILE"
    exit 1
  fi
else
  if ! bash -c ">/dev/tcp/${HOST}/${PORT}" >/dev/null 2>&1; then
    echo "❌ cannot reach Beads SQL endpoint ${HOST}:${PORT}" | tee -a "$LOG_FILE"
    exit 1
  fi
fi

TEST_JSON=$(bd dolt test --json 2>&1)
if ! jq -e '.connection_ok == true' >/dev/null <<<"$TEST_JSON"; then
  echo "❌ bd dolt test reports connection not healthy" | tee -a "$LOG_FILE"
  echo "$TEST_JSON" >>"$LOG_FILE"
  exit 1
fi

STATUS_JSON=$(bd status --json 2>&1)
if ! jq -e '.summary' >/dev/null <<<"$STATUS_JSON"; then
  echo "❌ invalid bd status payload" | tee -a "$LOG_FILE"
  echo "$STATUS_JSON" >>"$LOG_FILE"
  exit 1
fi

TOTAL_ISSUES=$(jq -r '.summary.total_issues // 0' <<<"$STATUS_JSON")
OPEN_ISSUES=$(jq -r '.summary.open // 0' <<<"$STATUS_JSON")
BLOCKED_ISSUES=$(jq -r '.summary.blocked // 0' <<<"$STATUS_JSON")
READY_ISSUES=$(jq -r '.summary.ready // 0' <<<"$STATUS_JSON")

echo "✅ Beads SQL reachable on ${HOST}:${PORT}; total=${TOTAL_ISSUES} open=${OPEN_ISSUES} blocked=${BLOCKED_ISSUES} ready=${READY_ISSUES}" | tee -a "$LOG_FILE"

if [[ "$(hostname -s)" == "epyc12" ]]; then
  if command -v ss >/dev/null 2>&1; then
    if ! ss -ltnp "( sport = :$PORT )" | grep -q ":$PORT"; then
      echo "❌ expected local Dolt listener not found on TCP/$PORT on hub host" | tee -a "$LOG_FILE"
      exit 1
    fi
  fi
fi

exit 0
