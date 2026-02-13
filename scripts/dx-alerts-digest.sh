#!/usr/bin/env bash
# dx-alerts-digest.sh - Hourly digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to #dx-alerts using OpenClaw (same as dx-job-wrapper)
# Format: [DX-ALERT][severity][scope] message

set -euo pipefail

STATE_DIR="$HOME/.dx-state"
LOG_DIR="$HOME/logs/dx"
DIGEST_LOG="$LOG_DIR/digest-history.log"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"
DIRTY_STATE="$STATE_DIR/dirty-incidents.json"

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
    # Simple parsing - extract repo names and ages
    echo "$state" | grep -oE '"[a-zA-Z0-9_-]+":\{' | tr -d '":{' | while read -r repo; do
        local age
        age=$(echo "$state" | grep -o "\"$repo\":[^}]*age_hours\":[0-9]*" | grep -oE '[0-9]+$' || echo "0")
        echo "  - $repo: ${age}h old"
    done
}

# Get stale repos (>=48h)
get_stale_repos() {
    if [[ ! -f "$DIRTY_STATE" ]]; then
        return
    fi
    
    local state
    state=$(cat "$DIRTY_STATE")
    
    # Extract repos with age >= 48
    echo "$state" | grep -oE '"[a-zA-Z0-9_-]+":\{[^}]*"age_hours":[0-9]+' | while read -r match; do
        local repo age
        repo=$(echo "$match" | grep -oE '^[^:]+')
        age=$(echo "$match" | grep -oE '[0-9]+$')
        if [[ -n "$age" && "$age" -ge 48 ]]; then
            echo "$repo:$age"
        fi
    done
}

# Post to Slack (with local fallback)
post_digest() {
    local message="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Always log locally
    echo "--- $timestamp ---" >> "$DIGEST_LOG"
    echo "$message" >> "$DIGEST_LOG"

    # Skip if dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    # Post to Slack using OpenClaw (same as dx-job-wrapper)
    local OPENCLAW="$HOME/.local/bin/mise x node@22.21.1 -- openclaw"
    local ALERTS_CHANNEL="C0ADSSZV9M2"
    local SENT=0

    # Try OpenClaw first (integrated with dx-job-wrapper)
    if command -v "$HOME/.local/bin/mise" &> /dev/null; then
        if $OPENCLAW message send --channel slack --target "$ALERTS_CHANNEL" --message "$message" >/dev/null 2>&1; then
            SENT=1
        fi
    fi

    # Fallback to webhook if OpenClaw failed
    if [[ "$SENT" -eq 0 && -n "${DX_SLACK_WEBHOOK:-}" ]]; then
        curl -s -m 5 -X POST "$DX_SLACK_WEBHOOK" \
            -H 'Content-type: application/json' \
            -d "{\"text\":\"$message\"}" >/dev/null 2>&1 || true
    fi

    if [[ "$SENT" -eq 0 && -z "${DX_SLACK_WEBHOOK:-}" ]]; then
        echo "Slack post skipped (no OpenClaw or webhook), see $DIGEST_LOG"
    fi
}

# Main: Build and post digest
build_digest() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local lines=()
    lines+=("📊 DX Hourly Digest - $timestamp")
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
    
    # Recovery commands (last 5) - fixed subshell issue
    if [[ -f "$RECOVERY_LOG" ]]; then
        lines+=("📋 Recent Recovery Commands:")
        local recovery_lines
        mapfile -t recovery_lines < <(tail -5 "$RECOVERY_LOG" 2>/dev/null)
        for line in "${recovery_lines[@]}"; do
            lines+=("  $line")
        done
        lines+=("")
    fi
    
    # Join with newlines
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

main "${@:-}"
