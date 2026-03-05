#!/usr/bin/env bash
# dx-fleet-daily-check.sh
# Backward-compatible daily Fleet Sync red-only check wrapper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
STATE_DIR="${HOME}/.dx-state/fleet"

export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
source "${SCRIPT_DIR}/lib/dx-slack-alerts.sh"

LOG_FILE="${HOME}/logs/dx-fleet-check-daily.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting daily Fleet Sync red-only audit"

TMP_REPORT="$(mktemp)"
trap 'rm -f "$TMP_REPORT"' EXIT
SUMMARY="daily audit completed with no failures"
FLEET_STATUS="green"
HOSTS_FAILED=0
FAIL_COUNT=0
WARN_COUNT=0

if ! "$SCRIPT_DIR/dx-fleet.sh" audit --daily --json --state-dir "$STATE_DIR" \
  >"$TMP_REPORT"; then
  if [[ -s "$TMP_REPORT" ]]; then
    if command -v jq >/dev/null 2>&1; then
      read -r FLEET_STATUS HOSTS_FAILED PASS_COUNT FAIL_COUNT WARN_COUNT UNKNOWN_COUNT <<<"$(jq -r '.fleet_status + " " + (.summary.hosts_failed|tostring) + " " + (.summary.pass|tostring) + " " + (.summary.red|tostring) + " " + (.summary.yellow|tostring) + " " + (.summary.unknown|tostring)' "$TMP_REPORT")"
      SUMMARY="Fleet Sync daily audit failed: status=$FLEET_STATUS hosts_failed=$HOSTS_FAILED pass=$PASS_COUNT fail=$FAIL_COUNT warn=$WARN_COUNT unknown=$UNKNOWN_COUNT"
    elif command -v python3 >/dev/null 2>&1; then
      SUMMARY="$(python3 - "$TMP_REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)
summary = payload.get("summary", {})
fleet_status = payload.get("fleet_status", "unknown")
line = (
    f"Fleet Sync daily audit failed: "
    f"status={fleet_status} "
    f"hosts_failed={summary.get('hosts_failed', 'n/a')} "
    f"pass={summary.get('pass', 'n/a')} "
    f"fail={summary.get('red', 'n/a')} "
    f"warn={summary.get('yellow', 'n/a')} "
    f"unknown={summary.get('unknown', 'n/a')}"
)
print(line)
PY
)"
    else
      SUMMARY="Fleet Sync daily audit failed: no parser (jq/python3 missing)"
    fi
  else
    SUMMARY="Fleet Sync daily audit failed; no JSON payload produced."
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: ${SUMMARY}"
  if ! agent_coordination_send_message "🚨 Fleet Sync red check: ${SUMMARY}" "${DX_ALERTS_CHANNEL_ID:-}"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport failed"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Alert sent to #dx-alerts"
  exit 1
fi

# Parse successful report to detect red fleet status explicitly
if command -v jq >/dev/null 2>&1; then
  FLEET_STATUS="$(jq -r '.fleet_status // "unknown"' "$TMP_REPORT")"
elif command -v python3 >/dev/null 2>&1; then
  FLEET_STATUS="$(python3 - "$TMP_REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)
print(payload.get("fleet_status", "unknown"))
PY
)"
else
  FLEET_STATUS="$(grep -o '\"fleet_status\"[[:space:]]*:[[:space:]]*\"[a-z]*\"' "$TMP_REPORT" | sed -E 's/.*\"fleet_status\"[[:space:]]*:[[:space:]]*\"([a-z]*)\".*/\\1/' | head -n1 || true)"
fi

if [[ "$FLEET_STATUS" == "red" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: Fleet Sync audit returned red"
  if ! agent_coordination_send_message "🚨 Fleet Sync red check: Fleet audit red status requires remediation" "${DX_ALERTS_CHANNEL_ID:-}"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport failed"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Alert sent to #dx-alerts"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fleet Sync daily audit completed: status=${FLEET_STATUS}"
exit 0
