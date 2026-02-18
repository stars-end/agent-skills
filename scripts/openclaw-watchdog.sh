#!/usr/bin/env bash
#
# openclaw-watchdog.sh - Ensure OpenClaw gateway service is running
#
# Usage: openclaw-watchdog.sh [--repair]
#
# Checks if the OpenClaw gateway LaunchAgent is loaded and running.
# With --repair, will attempt to load/restart the service.
#
# Exit codes:
#   0 - Service is healthy
#   1 - Service is not healthy (and not repaired or repair failed)
#   2 - Service was repaired successfully
#
set -euo pipefail

SERVICE_LABEL="ai.openclaw.gateway"
PLIST_PATH="$HOME/Library/LaunchAgents/${SERVICE_LABEL}.plist"
REPAIR_MODE="${1:-}"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1"
}

check_loaded() {
    launchctl print "gui/$(id -u)/${SERVICE_LABEL}" &>/dev/null
}

check_running() {
    # Check both launchd state AND actual process
    local launchd_status process_status

    launchd_status=$(launchctl print "gui/$(id -u)/${SERVICE_LABEL}" 2>/dev/null | grep -E "^\s*state = running" || true)
    process_status=$(pgrep -f "openclaw.*gateway" || true)

    [[ -n "$launchd_status" && -n "$process_status" ]]
}

repair_service() {
    log "Attempting to repair ${SERVICE_LABEL}..."

    # Check if plist exists
    if [[ ! -f "$PLIST_PATH" ]]; then
        log "ERROR: Plist not found at $PLIST_PATH"
        return 1
    fi

    # Try to unload first (in case it's in a bad state)
    launchctl unload "$PLIST_PATH" 2>/dev/null || true

    # Load the service
    if launchctl load "$PLIST_PATH" 2>&1; then
        sleep 2
        if check_running; then
            log "SUCCESS: ${SERVICE_LABEL} repaired and running"
            return 0
        else
            log "ERROR: ${SERVICE_LABEL} loaded but not running"
            return 1
        fi
    else
        log "ERROR: Failed to load ${SERVICE_LABEL}"
        return 1
    fi
}

# Main logic
log "Checking ${SERVICE_LABEL}..."

if check_running; then
    log "OK: ${SERVICE_LABEL} is running"
    exit 0
fi

if check_loaded; then
    log "WARN: ${SERVICE_LABEL} is loaded but not running"
else
    log "WARN: ${SERVICE_LABEL} is not loaded"
fi

# Service is unhealthy
if [[ "$REPAIR_MODE" == "--repair" ]]; then
    if repair_service; then
        exit 2  # Repaired successfully
    else
        exit 1  # Repair failed
    fi
else
    log "Run with --repair to attempt automatic repair"
    exit 1
fi
