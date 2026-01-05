#!/bin/bash
# opencode-cleanup.sh - Session cleanup cron job
# Deletes OpenCode sessions older than 24 hours
# Run via cron: 0 2 * * * /home/feng/agent-skills/slack-coordination/opencode-cleanup.sh

set -e

OPENCODE_URL="${OPENCODE_URL:-http://localhost:4105}"
MAX_AGE_HOURS=24
LOG_FILE="$HOME/.local/log/opencode-cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

cleanup() {
    echo "[$(date -Iseconds)] Starting OpenCode session cleanup..." >> "$LOG_FILE"
    
    # Get all sessions
    sessions=$(curl -s "$OPENCODE_URL/session" | python3 -c "
import json, sys, time
data = json.load(sys.stdin)
now = time.time() * 1000  # ms
max_age_ms = ${MAX_AGE_HOURS} * 3600 * 1000
for session in data:
    updated = session.get('time', {}).get('updated', now)
    if (now - updated) > max_age_ms:
        print(session['id'])
")
    
    # Delete each stale session
    count=0
    for sid in $sessions; do
        curl -s -X DELETE "$OPENCODE_URL/session/$sid" > /dev/null
        echo "[$(date -Iseconds)] Deleted stale session: $sid" >> "$LOG_FILE"
        ((count++))
    done
    
    echo "[$(date -Iseconds)] Cleanup complete. Deleted $count sessions." >> "$LOG_FILE"
}

cleanup
