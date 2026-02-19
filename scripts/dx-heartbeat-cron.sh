#!/bin/bash
# V8 Heartbeat - System Cron Wrapper
# Bypasses OpenClaw native cron (broken isolated sessions)
# Schedule: Every 2hours 6am-4pm (0 6-16/2 * * *)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-heartbeat.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting heartbeat check..."

# Use openclaw agent CLI to read and summarize HEARTBEAT.md
# We use the full path to mise and openclaw
OPENCLAW="${HOME}/.local/bin/mise x node@22.21.1 -- openclaw"

# Run agent turn to get summary
# Redirect stderr to avoid capturing doctor warnings
RESPONSE=$($OPENCLAW agent \
  --agent all-stars-end \
  --message "You are running a DX health pulse. Read ${HOME}/.dx-state/HEARTBEAT.md. If ALL status sections OK and no failed jobs, respond ONLY with 'HEARTBEAT_OK'. If any issues, output a 1-3 line summary with emojis (🚨/⚠️). Do NOT fix anything." \
  2>/dev/null)

if [ "$RESPONSE" == "HEARTBEAT_OK" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Heartbeat OK"
    exit 0
fi

if [ -z "$RESPONSE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty response from agent"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Detect issues: $RESPONSE"

# Send alert to Slack
$OPENCLAW message send \
    --channel slack \
    --target C0ADSSZV9M2 \
    --message "$RESPONSE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Alert sent successfully"

# Push heartbeat to remote for GHA dead-man's switch
"${HOME}/agent-skills/scripts/dx-heartbeat-push.sh"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Remote heartbeat push complete"
