#!/usr/bin/env bash

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

HOST="${BEADS_DOLT_SERVER_HOST:-100.107.173.83}"
PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
REPO="${HOME}/bd"
LOG_FILE="$HOME/logs/dx/beads-health-alert.log"

mkdir -p "$(dirname "$LOG_FILE")"
{
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] bead-health-check: hub=${HOST}:${PORT}"
} >>"$LOG_FILE"

if [[ ! -d "$REPO/.git" ]]; then
  echo "❌ canonical Beads repo missing at $REPO" | tee -a "$LOG_FILE"
  exit 1
fi

cd "$REPO"

if [[ ! -d "$REPO/.beads/dolt/.dolt" ]]; then
  echo "❌ dolt data-dir is not initialized under ~/bd/.beads/dolt (missing .dolt metadata)" | tee -a "$LOG_FILE"
  exit 1
fi

export BEADS_DOLT_SERVER_HOST="$HOST"
export BEADS_DOLT_SERVER_PORT="$PORT"

if command -v nc >/dev/null 2>&1; then
  if ! nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
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
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️ jq is required for payload validation" | tee -a "$LOG_FILE"
  exit 1
fi
if ! jq -e '.connection_ok == true' >/dev/null <<<"$TEST_JSON"; then
  echo "❌ bd dolt test reports connection not healthy" | tee -a "$LOG_FILE"
  echo "$TEST_JSON" >>"$LOG_FILE"
  exit 1
fi

STATUS_JSON=$(bd status --json 2>&1)
TOTAL_ISSUES=$(jq -r '.summary.total_issues // "unknown"' <<<"$STATUS_JSON")

if ! jq -e '.summary' >/dev/null <<<"$STATUS_JSON"; then
  echo "❌ invalid bd status payload" | tee -a "$LOG_FILE"
  echo "$STATUS_JSON" >>"$LOG_FILE"
  exit 1
fi

echo "✅ Beads SQL reachable on ${HOST}:${PORT}; total_issues=${TOTAL_ISSUES}" | tee -a "$LOG_FILE"

if command -v ss >/dev/null 2>&1; then
  if ! ss -ltnp "( sport = :$PORT )" | grep -q ":$PORT"; then
    echo "⚠️  no local listener currently found on TCP/$PORT" | tee -a "$LOG_FILE"
  fi
fi

exit 0
