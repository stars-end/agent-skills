#!/bin/bash
# release-lock.sh
# Releases the machine-wide lock if held by this process.
# Usage: ./release-lock.sh

LOCKFILE="/tmp/agent_coordinator.lock"

if [ ! -f "$LOCKFILE" ]; then
    echo "ℹ️  No lock file found."
    exit 0
fi

LOCK_CONTENT=$(cat "$LOCKFILE")
LOCK_PID=$(echo "$LOCK_CONTENT" | cut -d: -f1)

if [ "$LOCK_PID" == "$$" ]; then
    rm -f "$LOCKFILE"
    echo "🔓 Lock released for PID $$"
    exit 0
else
    echo "⚠️  Lock held by another process (PID $LOCK_PID). Not releasing."
    exit 0 # Not an error, just didn't own it
fi
