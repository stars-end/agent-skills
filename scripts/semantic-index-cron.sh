#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SEMANTIC_INDEX_CRON_LOG_DIR:-$HOME/.cache/agent-semantic-indexes/logs}"
mkdir -p "$LOG_DIR"

"$SCRIPT_DIR/semantic-index-refresh" \
  --all \
  --timeout-init "${SEMANTIC_INDEX_TIMEOUT_INIT:-120}" \
  --timeout-doctor "${SEMANTIC_INDEX_TIMEOUT_DOCTOR:-120}" \
  --timeout-index "${SEMANTIC_INDEX_TIMEOUT_INDEX:-1800}" \
  --timeout-status "${SEMANTIC_INDEX_TIMEOUT_STATUS:-60}" \
  --timeout-daemon-stop "${SEMANTIC_INDEX_TIMEOUT_DAEMON_STOP:-60}" \
  >>"$LOG_DIR/semantic-index-cron.log" 2>&1
