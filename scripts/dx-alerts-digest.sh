#!/usr/bin/env bash
# dx-alerts-digest.sh - Daily digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to #dx-alerts using Slack Web API
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

post_slack_message() {
    local message="$1"
    local token="${SLACK_MCP_XOXB_TOKEN:-${SLACK_MCP_XOXP_TOKEN:-${SLACK_BOT_TOKEN:-${SLACK_APP_TOKEN:-}}}}"
    local channel="${DX_ALERTS_CHANNEL:-dx-alerts}"

    if [[ -z "$token" ]]; then
        echo "Slack token missing; cannot post digest"
        return 1
    fi

    local channel_id
    if [[ "$channel" == C* || "$channel" == U* || "$channel" == G* ]]; then
        channel_id="$channel"
    else
        local trimmed_channel="${channel#\#}"
        local response
        response=$(curl -sS -m 8 -X GET \
            -H "Authorization: Bearer $token" \
            -H 'Content-type: application/json; charset=utf-8' \
            'https://slack.com/api/conversations.list?types=public_channel,private_channel&exclude_archived=true')

        if ! jq -e '.ok == true' >/dev/null <<<"$response"; then
            echo "Slack conversation lookup failed"
            return 1
        fi

        channel_id=$(jq -r --arg name "$trimmed_channel" '.channels[] | select(.name == $name) | .id' <<<"$response" | head -n 1)
        if [[ -z "$channel_id" || "$channel_id" == "null" ]]; then
            echo "Could not resolve Slack channel '$channel'"
            return 1
        fi
    fi

    local payload
    payload=$(jq -n --arg channel_id "$channel_id" --arg text "$message" '{channel: $channel_id, text: $text}')
    local response
    response=$(curl -sS -m 8 -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $token" \
        -H 'Content-type: application/json; charset=utf-8' \
        --data-raw "$payload")

    if ! jq -e '.ok == true' >/dev/null <<<"$response"; then
        echo "Slack API postMessage failed"
        return 1
    fi

    return 0
}

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

    if ! post_slack_message "$message" >/dev/null 2>&1; then
        # Fallback to webhook if conversation lookup or API posting fails
        if command -v curl >/dev/null 2>&1 && [[ -n "${DX_SLACK_WEBHOOK:-}" ]]; then
            curl -s -m 5 -X POST "$DX_SLACK_WEBHOOK" \
                -H 'Content-type: application/json' \
                -d "{\"text\":\"$message\"}" >/dev/null 2>&1 || true
        else
            echo "Slack post skipped, see $DIGEST_LOG"
        fi
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
