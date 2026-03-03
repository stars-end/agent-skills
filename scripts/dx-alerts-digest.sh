#!/usr/bin/env bash
# dx-alerts-digest.sh - Daily digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to #dx-alerts using Agent Coordination (Slack API) with webhook fallback
# Summarizes evacuation events from recovery-commands.log
#
# Note: Dirty incident tracking is now handled by canonical-evacuate-active.sh
# which provides real-time alerts with 15/45m thresholds. This digest
# provides a daily summary of any evacuations that occurred.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

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

recent_recovery_entries() {
    if [[ ! -f "$RECOVERY_LOG" ]]; then
        return 0
    fi

    python3 - "$RECOVERY_LOG" <<'PY'
import datetime as dt
import sys

path = sys.argv[1]
now = dt.datetime.now(dt.timezone.utc)
cutoff = now - dt.timedelta(hours=24)

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue
        ts = line.split(" | ", 1)[0].strip()
        try:
            when = dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
        if when >= cutoff:
            print(line)
PY
}

# Get evacuations from the last 24 hours
get_evacuation_summary() {
    if [[ ! -f "$RECOVERY_LOG" ]]; then
        echo "No evacuations"
        return
    fi

    local recent
    recent=$(recent_recovery_entries | tail -20)

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

    local counts
    counts=$(recent_recovery_entries | awk -F ' \\| ' '{gsub(/^ +| +$/, "", $2); if ($2 != "") print $2}' | sort | uniq -c | sort -rn)

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

    # Post to Slack via deterministic Agent Coordination transport.
    if ! agent_coordination_send_message "$message" "${DX_ALERTS_CHANNEL_ID:-}" >/dev/null 2>&1; then
        echo "Slack post skipped (no Agent Coordination transport or webhook), see $DIGEST_LOG"
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
