#!/bin/bash
# V8 Weekly Audit - System Cron Wrapper
# Bypasses OpenClaw native cron (broken isolated sessions)
# Schedule: Sunday 7am PT (0 7 * * 0)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-audit.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting weekly V8 audit..."

# Generate the message
# NOTE: Using worktree path until PR #135 merges, then update to ${HOME}/agent-skills/scripts/dx-audit.sh
AUDIT_SCRIPT="${HOME}/agent-skills/scripts/dx-audit.sh"
[ ! -f "$AUDIT_SCRIPT" ] && AUDIT_SCRIPT="/tmp/agents/bd-rrb9/agent-skills/scripts/dx-audit.sh"
MSG=$("$AUDIT_SCRIPT" --slack 2>/dev/null)

if [ -z "$MSG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty message generated"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message generated (${#MSG} chars)"

# Send via OpenClaw CLI (system cron has full env access)
"${HOME}/.local/bin/mise" x node@22.21.1 -- openclaw message send \
    --channel slack \
    --target C0ADSSZV9M2 \
    --message "$MSG"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Audit sent successfully"
