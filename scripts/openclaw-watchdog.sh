#!/usr/bin/env bash
#
# Keep ai.openclaw.gateway loaded on macOS launchd hosts.
# Safe no-op on non-macOS hosts.
#
set -euo pipefail

LABEL="ai.openclaw.gateway"
UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"
TARGET="${DOMAIN}/${LABEL}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

timestamp() {
    date -u +"%Y-%m-%d %H:%M:%S UTC"
}

log() {
    echo "[$(timestamp)] $*"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    exit 0
fi

if [[ ! -f "$PLIST" ]]; then
    log "watchdog: plist missing, skipping: $PLIST"
    exit 0
fi

if launchctl print "$TARGET" >/dev/null 2>&1; then
    # Service is known; kickstart only if explicitly requested.
    if [[ "${1:-}" == "--repair" ]]; then
        launchctl kickstart -k "$TARGET" >/dev/null 2>&1 || true
    fi
    exit 0
fi

log "watchdog: bootstrapping missing gateway service"
launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
launchctl kickstart -k "$TARGET" >/dev/null 2>&1 || true

if launchctl print "$TARGET" >/dev/null 2>&1; then
    log "watchdog: gateway service restored"
else
    log "watchdog: gateway restore failed"
fi
