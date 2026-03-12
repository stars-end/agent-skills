#!/bin/bash
# opencode-cleanup.sh - Legacy OpenCode server cleanup job
# Deletes OpenCode sessions older than 24 hours
# Retired by default. Only run with:
#   SLACK_COORDINATION_ENABLE_LEGACY_OPENCODE_SERVER=1

set -e

if [[ "${SLACK_COORDINATION_ENABLE_LEGACY_OPENCODE_SERVER:-0}" != "1" ]]; then
    echo "legacy OpenCode server cleanup disabled; set SLACK_COORDINATION_ENABLE_LEGACY_OPENCODE_SERVER=1 to opt in"
    exit 0
fi

OPENCODE_URL="${OPENCODE_URL:-}"
if [[ -z "$OPENCODE_URL" ]]; then
    echo "OPENCODE_URL must be set when legacy OpenCode server cleanup is enabled" >&2
    exit 1
fi

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
