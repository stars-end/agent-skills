#!/bin/bash
# can-dispatch.sh
# Checks if an agent should be dispatched based on locks and load.
# Usage: ./can-dispatch.sh
# Returns: 0 (True/Safe) or 1 (False/Unsafe)

# 1. Check Lock File
LOCKFILE="/tmp/agent_coordinator.lock"
if [ -f "$LOCKFILE" ]; then
    LOCK_CONTENT=$(cat "$LOCKFILE")
    LOCK_PID=$(echo "$LOCK_CONTENT" | cut -d: -f1)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "❌ Machine locked by PID $LOCK_PID"
        exit 1
    fi
    # Stale lock will be handled by acquire-lock, but strictly speaking "cannot dispatch" right now until cleaned
    echo "⚠️  Stale lock found. Proceed with caution (acquire-lock will clean)."
fi

# 2. Check System Load
# Load threshold: 80% of cores. Simplified to raw number '4' for typical 4-8 core dev machines.
# Adjust per machine if needed.
MAX_LOAD=4.0
CURRENT_LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)

if (( $(echo "$CURRENT_LOAD > $MAX_LOAD" | bc -l) )); then
    echo "❌ System load too high: $CURRENT_LOAD (Max: $MAX_LOAD)"
    exit 1
fi

# 3. Check for specific process names (extra guard)
if pgrep -f "claude" > /dev/null; then
    # Exclude self if running inside claude? No, usually this is called BEFORE starting claude.
    # But if we are running IN claude, we are already running.
    # This script is intended for EXTERNAL dispatchers or PRE-checks.
    # Use argument --ignore-self if needed.
    echo "ℹ️  'claude' process found running."
    # We fail if we want STRICT single agent.
    # But if WE are the agent calling this to check if we can spawn a SUB-task... different context.
    # Assuming this is "Can I start a NEW independent session?" -> Fail.
    echo "❌ Agent process 'claude' already active."
    exit 1
fi

echo "✅ Safe to dispatch"
exit 0
