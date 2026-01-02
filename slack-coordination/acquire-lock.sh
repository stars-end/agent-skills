#!/bin/bash
# acquire-lock.sh
# Acquires a machine-wide lock for an agent session.
# Usage: ./acquire-lock.sh <agent_id>
# Returns: 0 if lock acquired, 1 if failed

AGENT_ID=${1:-"unknown_agent"}
LOCKFILE="/tmp/agent_coordinator.lock"

if [ -f "$LOCKFILE" ]; then
    # Check if process holding lock is still alive
    LOCK_CONTENT=$(cat "$LOCKFILE")
    LOCK_PID=$(echo "$LOCK_CONTENT" | cut -d: -f1)
    LOCK_AGENT=$(echo "$LOCK_CONTENT" | cut -d: -f2)

    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "❌ Locked by running agent: $LOCK_AGENT (PID $LOCK_PID)"
        exit 1
    else
        echo "⚠️  Found stale lock from $LOCK_AGENT (PID $LOCK_PID). Cleaning up."
        rm -f "$LOCKFILE"
    fi
fi

# Acquire lock
echo "$$: $AGENT_ID" > "$LOCKFILE"
echo "🔒 Lock acquired for $AGENT_ID (PID $$)"
exit 0
