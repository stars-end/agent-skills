#!/usr/bin/env bash
# dx-alerts-digest.sh - Daily digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to #dx-alerts using OpenClaw (same as dx-job-wrapper)
# Summarizes evacuation events from recovery-commands.log
#
# Note: Dirty incident tracking is now handled by canonical-evacuate-active.sh
# which provides real-time alerts with 15/45m thresholds. This digest
# provides a daily summary of any evacuations that occurred.

set -euo pipefail

STATE_DIR="$HOME/.dx-state"
LOG_DIR="$HOME/logs/dx"
DIGEST_LOG="$LOG_DIR/digest-history.log"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"

DRY_RUN="${DRY_RUN:-false}"

mkdir -p "$LOG_DIR" "$STATE_DIR"

# Severity prefix helper
format_alert() {
    local severity="$1"
    local scope="$2"
    local message="$3"
    echo "[DX-ALERT][$severity][$scope] $message"
}

# Get evacuations from the last 24 hours
get_evacuation_summary() {
    if [[ ! -f "$RECOVERY_LOG" ]]; then
        echo "No evacuations"
        return
    fi

    # Get entries from last 24h
    local yesterday
    yesterday=$(date -u -v-1d +"%Y-%m-%d" 2>/dev/null || date -u -d "1 day ago" +"%Y-%m-%d" 2>/dev/null)

    local recent
    recent=$(awk -v cutoff="$yesterday" '$1 >= cutoff' "$RECOVERY_LOG" 2>/dev/null | tail -20)

    if [[ -z "$recent" ]]; then
        echo "No evacuations in last 24h"
        return
    fi

    echo "Recent evacuations (last 24h):"
    echo "$recent" | while IFS= read -r line; do
        echo "  $line"
    done
}

# Get count of evacuations by repo
get_evacuation_counts() {
    if [[ ! -f "$RECOVERY_LOG" ]]; then
        return
    fi

    local yesterday
    yesterday=$(date -u -v-1d +"%Y-%m-%d" 2>/dev/null || date -u -d "1 day ago" +"%Y-%m-%d" 2>/dev/null)

    local counts
    counts=$(awk -v cutoff="$yesterday" '$1 >= cutoff {print $3}' "$RECOVERY_LOG" 2>/dev/null | sort | uniq -c | sort -rn)

    if [[ -n "$counts" ]]; then
        echo "Evacuations by repo:"
        echo "$counts" | while read -r count repo; do
            echo "  - $repo: $count"
        done
    fi
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
# Returns: 0 = post digest, 1 = skip (green)
build_digest() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local lines=()
    local has_incidents=false

    lines+=("📊 DX Daily Digest - $timestamp")
    lines+=("")

    # Evacuation summary
    local evac_summary
    evac_summary=$(get_evacuation_summary)
    if [[ "$evac_summary" != "No evacuations in last 24h" && "$evac_summary" != "No evacuations" ]]; then
        has_incidents=true
        lines+=("$evac_summary")
        lines+=("")
    fi

    # Evacuation counts
    local evac_counts
    evac_counts=$(get_evacuation_counts)
    if [[ -n "$evac_counts" ]]; then
        lines+=("$evac_counts")
        lines+=("")
    fi

    # Skip if no incidents (everything green)
    if [[ "$has_incidents" == "false" ]]; then
        return 1
    fi

    # Join with newlines
    printf '%s\n' "${lines[@]}"
    return 0
}

# Main
main() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
    fi

    local digest
    if ! digest=$(build_digest); then
        # build_digest returned 1 = skip (everything green)
        echo "✅ No evacuations to report - skipping Slack post"
        exit 0
    fi

    echo "$digest"
    post_digest "$digest"
}

main "${@:-}"
