#!/usr/bin/env bash
# dx-fleet-daily-check.sh
# Deterministic daily red-only Fleet Sync runtime check with fast alerting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
AUDIT_ROOT="${ROOT_DIR}"
FLEET_MANIFEST="${ROOT_DIR}/configs/fleet-sync.manifest.yaml"
MCP_MANIFEST="${ROOT_DIR}/configs/mcp-tools.yaml"
STATE_DIR="${HOME}/.dx-state/fleet-sync"

export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
source "${SCRIPT_DIR}/lib/dx-slack-alerts.sh"

LOG_FILE="${HOME}/logs/dx-fleet-check-daily.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec >>"$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting daily Fleet Sync red-only check"

if [[ ! -f "$FLEET_MANIFEST" || ! -f "$MCP_MANIFEST" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Missing Fleet Sync manifest files"
  exit 1
fi

TMP_REPORT="$(mktemp)"
trap 'rm -f "$TMP_REPORT"' EXIT

if ! "$SCRIPT_DIR/dx-fleet-check.sh" \
  --json \
  --red-only \
  --manifest "$FLEET_MANIFEST" \
  --mcp-manifest "$MCP_MANIFEST" \
  --state-dir "$STATE_DIR" \
  >"$TMP_REPORT"; then
  if [[ -s "$TMP_REPORT" ]]; then
    SUMMARY="$(python3 - "$TMP_REPORT" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)

config_drift = payload.get("checks", {}).get("config_drift", "n/a")
v_mismatch = payload.get("checks", {}).get("tool_version_mismatch", "n/a")
stale_tools = payload.get("checks", {}).get("tool_health_stale", "n/a")
dolt_stale = payload.get("checks", {}).get("dolt_stale", "n/a")
tool_ok = payload.get("tools", {}).get("overall_ok", False)
line = (
    f"Fleet Sync red-only check failed | tool_ok={tool_ok} "
    f"config_drift={config_drift} v_mismatch={v_mismatch} "
    f"stale_tools={stale_tools} dolt_stale={dolt_stale}"
)
print(line)
PY
)"
  else
    SUMMARY="Fleet Sync red-only check failed; no JSON payload produced."
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: ${SUMMARY}"
  if ! agent_coordination_send_message "🚨 Fleet Sync red check: ${SUMMARY}" "${DX_ALERTS_CHANNEL_ID:-}"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport failed"
    exit 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Alert sent to #dx-alerts"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fleet Sync red-only check passed"
exit 0
