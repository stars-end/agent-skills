#!/bin/bash
# V8 Weekly Audit - System Cron Wrapper
# Bypasses OpenClaw native cron (broken isolated sessions)
# Schedule: Sunday 7am PT (0 7 * * 0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-audit.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting weekly V8 audit (includes Fleet Sync V2.1 checks)..."

# Generate the message
AUDIT_SCRIPT="${HOME}/agent-skills/scripts/dx-audit.sh"
MSG=$("$AUDIT_SCRIPT" --slack 2>/dev/null)

if [ -z "$MSG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty message generated"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message generated (${#MSG} chars)"

# Send via Agent Coordination Slack transport.
if agent_coordination_send_message "$MSG" "${DX_ALERTS_CHANNEL_ID:-}"; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Audit sent successfully"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport unavailable"
  exit 1
fi
