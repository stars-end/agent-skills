#!/usr/bin/env bash
#
# dx-schedule-install.sh
#
# ⚠️  DEPRECATED: This script is V7.8 only and references non-existent schedules/ directory.
#
# For V8+, cron schedules are installed via:
#   - dx-hydrate.sh (calls install-v8-cron.sh)
#   - Direct crontab management by dx-hydrate.sh
#
# This script is kept for historical reference but will not work without
# the schedules/v7.8/ directory which was removed in V8.
#
# See: docs/DX_FLEET_SPEC_V8.md for current V8 cron approach.
#
# Idempotent installer for DX V7.8 schedules.
#
# Usage:
#   dx-schedule-install.sh [--dry-run|--apply] [--host local|...]
#
set -euo pipefail

MODE="dry-run"
HOST_TARGET="local"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) MODE="apply" ;;
        --dry-run) MODE="dry-run" ;;
        --host) HOST_TARGET="$2"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

OS_TYPE=$(uname -s)
AGENTSKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ "$MODE" == "dry-run" ]]; then
    log "🔍 Running in DRY-RUN mode (no changes will be applied)"
fi

install_macmini() {
    local source_dir="$AGENTSKILLS_DIR/schedules/v7.8/macmini"
    local target_dir="$HOME/Library/LaunchAgents"
    mkdir -p "$target_dir"

    log "Checking launchd plists from $source_dir"

    for plist in "$source_dir"/*.plist; do
        local base_plist=$(basename "$plist")
        local target_plist="$target_dir/$base_plist"
        
        # Expand placeholders in a temporary file for comparison
        local expanded_source=$(mktemp)
        sed "s|__HOME__|$HOME|g" "$plist" > "$expanded_source"
        
        if [[ -f "$target_plist" ]]; then
            if diff -q "$expanded_source" "$target_plist" >/dev/null; then
                log "✅ $base_plist: No drift"
            else
                log "⚠️ $base_plist: Drift detected"
                if [[ "$MODE" == "apply" ]]; then
                    log "  Applying update..."
                    launchctl unload "$target_plist" 2>/dev/null || true
                    cp "$expanded_source" "$target_plist"
                    launchctl load "$target_plist"
                fi
            fi
        else
            log "➕ $base_plist: New schedule"
            if [[ "$MODE" == "apply" ]]; then
                log "  Installing..."
                cp "$expanded_source" "$target_plist"
                launchctl load "$target_plist"
            fi
        fi
        rm -f "$expanded_source"
    done
}

install_linux_local() {
    local source_file="$AGENTSKILLS_DIR/schedules/v7.8/linux/crontab.txt"
    local tmp_cron=$(mktemp)
    
    log "Preparing crontab from $source_file"
    
    # Replace __HOME__ with actual $HOME
    sed "s|__HOME__|$HOME|g" "$source_file" > "$tmp_cron"
    
    local current_cron=$(mktemp)
    crontab -l > "$current_cron" 2>/dev/null || touch "$current_cron"
    
    if diff -q "$tmp_cron" "$current_cron" >/dev/null; then
        log "✅ Crontab: No drift"
    else
        log "⚠️ Crontab: Drift detected"
        if [[ "$MODE" == "apply" ]]; then
            log "  Applying crontab..."
            crontab "$tmp_cron"
        fi
    fi
    
    rm -f "$tmp_cron" "$current_cron"
}

install_remote() {
    local host="$1"
    local source_file="$AGENTSKILLS_DIR/schedules/v7.8/linux/crontab.txt"
    
    log "Processing remote host: $host"
    
    # Get remote HOME
    local remote_home
    remote_home=$(ssh "$host" "echo \$HOME")
    
    local tmp_cron=$(mktemp)
    sed "s|__HOME__|$remote_home|g" "$source_file" > "$tmp_cron"
    
    local current_cron=$(mktemp)
    ssh "$host" "crontab -l" > "$current_cron" 2>/dev/null || touch "$current_cron"
    
    if diff -q "$tmp_cron" "$current_cron" >/dev/null; then
        log "✅ $host Crontab: No drift"
    else
        log "⚠️ $host Crontab: Drift detected"
        if [[ "$MODE" == "apply" ]]; then
            log "  Applying crontab to $host..."
            scp "$tmp_cron" "$host:/tmp/new_crontab"
            ssh "$host" "crontab /tmp/new_crontab && rm /tmp/new_crontab"
        fi
    fi
    
    rm -f "$tmp_cron" "$current_cron"
}

if [[ "$HOST_TARGET" == "local" ]]; then
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        install_macmini
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        install_linux_local
    else
        log "❌ Unsupported local OS: $OS_TYPE"
        exit 1
    fi
else
    # For now, assume remote targets are Linux
    install_remote "$HOST_TARGET"
fi

log "✨ Schedule installation check complete ($MODE)"
