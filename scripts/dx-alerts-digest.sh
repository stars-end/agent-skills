#!/usr/bin/env bash
# dx-alerts-digest.sh - Hourly digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to Agent Coordination Slack channel with format:
# [DX-ALERT][severity][scope] message

set -euo pipefail

STATE_DIR="$HOME/.dx-state"
LOG_DIR="$HOME/logs/dx"
DIGEST_LOG="$LOG_DIR/digest-history.log"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"
DIRTY_STATE="$STATE_DIR/dirty-incidents.json"

# Config (can be overridden by env)
DX_ALERTS_CHANNEL="${DX_ALERTS_CHANNEL:-}"  # Channel ID or webhook URL
DRY_RUN="${DRY_RUN:-false}"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# Severity prefix helper
format_alert() {
    local severity="$1"
    local scope="$2"
    local message="$3"
    echo "[DX-ALERT][$severity][$scope] $message"
}

# Get dirty incidents summary
get_dirty_summary() {
    if [[ ! -f "$DIRTY_STATE" ]]; then
        echo "No dirty incidents"
        return
    fi

    local state
    state=$(cat "$DIRTY_STATE")
    if [[ "$state" == "{}" ]]; then
        echo "No dirty incidents"
        return
    fi

    echo "Dirty canonicals:"
    # Parse JSON entries - extract repo names and ages
    # Format: {"repo":{"age_hours":N,...}}
    echo "$state" | tr ',' '\n' | grep -E '"[a-z]+"' | head -10 | while read -r line; do
        if [[ "$line" =~ ^\"([a-zA-Z0-9_-]+)\":\{ ]]; then
            local repo="${BASH_REMATCH[1]}"
            local age
            age=$(echo "$line" | grep -oE '"age_hours":[0-9]+' | cut -d: -f2 || echo "?")
            echo "  - $repo: ${age}h old"
        fi
    done
}

# Get stale repos (>=48h)
get_stale_repos() {
    if [[ ! -f "$DIRTY_STATE" ]]; then
        return
    fi

    local state
    state=$(cat "$DIRTY_STATE")

    # Parse and filter for repos with age >= 48
    echo "$state" | tr ',' '\n' | grep -E '"age_hours":[0-9]+' | while read -r line; do
        if [[ "$line" =~ \"([a-zA-Z0-9_-]+)\".*:.*\"age_hours\":([0-9]+) ]]; then
            local repo="${BASH_REMATCH[1]}"
            local age="${BASH_REMATCH[2]}"
            if [[ -n "$age" && "$age" -ge 48 ]]; then
                echo "$repo:$age"
            fi
        fi
    done
}

# Log recovery command
log_recovery() {
    local repo="$1"
    local rescue_ref="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$timestamp | $repo | $rescue_ref" >> "$RECOVERY_LOG"
}

# Post to Slack (with local fallback)
post_digest() {
    local message="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Always log locally
    echo "--- $timestamp ---" >> "$DIGEST_LOG"
    echo "$message" >> "$DIGEST_LOG"

    # Post to Slack if configured
    if [[ -n "$DX_ALERTS_CHANNEL" && "$DRY_RUN" != "true" ]]; then
        curl -s -X POST "$DX_ALERTS_CHANNEL" \
            -H 'Content-type: application/json' \
            -d "{\"text\":\"$message\"}" 2>/dev/null || \
            echo "Slack post failed, see $DIGEST_LOG"
    fi
}

# Main: Build and post digest
build_digest() {
    local lines=()
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    lines+=("DX Hourly Digest - $timestamp")
    lines+=("")

    # Dirty incidents
    local dirty_summary
    dirty_summary=$(get_dirty_summary)
    lines+=("$dirty_summary")
    lines+=("")

    # Stale warnings
    local stale
    stale=$(get_stale_repos)
    if [[ -n "$stale" ]]; then
        lines+=("$(format_alert "high" "fleet" "Stale repos >=48h:")")
        while IFS= read -r line; do
            lines+=("  - $line")
        done <<< "$stale"
        lines+=("")
    fi

    # Recovery commands (last 5)
    if [[ -f "$RECOVERY_LOG" ]]; then
        lines+=("Recent Recovery Commands:")
        tail -5 "$RECOVERY_LOG" | while read -r line; do
            lines+=("  $line")
        done
    fi

    printf '%s\n' "${lines[@]}"
}

# Main
main() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
    fi

    local digest
    digest=$(build_digest)
    echo "$digest"
    post_digest "$digest"
}

main "${1:-}"
