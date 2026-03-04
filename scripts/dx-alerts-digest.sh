#!/usr/bin/env bash
# dx-alerts-digest.sh - Daily digest for DX alerts
# Usage: dx-alerts-digest.sh [--dry-run]
#
# Posts to #dx-alerts using Agent Coordination (Slack API) with webhook fallback.
# Summarizes events from recovery-commands.log, including:
#  - canonical-evacuate-active
#  - canonical-sync-v8
#  - founder-briefing failures and transport failures
#
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

parse_recent_events() {
    local cutoff_epoch
    cutoff_epoch=$(date -u +%s)
    cutoff_epoch=$(( cutoff_epoch - 24*60*60 ))

    python3 - "$RECOVERY_LOG" "$cutoff_epoch" <<'PY'
import datetime
import json
import re
import sys

path = sys.argv[1]
cutoff = int(sys.argv[2])

if not path or not path:
    print("[]")
    sys.exit(0)

records = []

key_value_pat = re.compile(r"^(?P<k>[^=]+)=(?P<v>.*)$")

with open(path, "r", encoding="utf-8", errors="ignore") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue

        parts = [p.strip() for p in line.split(" | ")]
        if not parts:
            continue

        ts_str = parts[0]
        try:
            when = int(datetime.datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp())
        except Exception:
            continue

        if when < cutoff:
            continue

        rec = {
            "ts": ts_str,
            "status": "unknown",
            "reason": "unknown",
            "script": "legacy",
            "repo": "unknown",
            "host": "unknown",
            "branch": "",
            "raw": line,
        }

        kv_seen = False
        for part in parts[1:]:
            m = key_value_pat.match(part)
            if not m:
                continue
            k = m.group("k")
            v = m.group("v")
            kv_seen = True
            rec[k] = v

        # Legacy parser path (pre-schema logs)
        if not kv_seen and len(parts) >= 2:
            rec["script"] = "canonical-sync-v8-legacy"
            rec["repo"] = parts[1]
            if len(parts) >= 3:
                rec["branch"] = parts[2]
            if len(parts) >= 4:
                rec["reason"] = parts[3]
            # Legacy reason/status ambiguity fallback
            if len(parts) >= 4 and parts[3]:
                rec["status"] = parts[3]
        elif not kv_seen and len(parts) >= 4:
            # Some scripts log 4-part legacy with status in final field
            rec["script"] = "canonical-sync-v8-legacy"
            rec["repo"] = parts[1]
            rec["reason"] = parts[2] if len(parts) > 2 else "unknown"
            rec["status"] = parts[3]

        # Normalize status to canonical labels where missing
        if rec["status"] in ("", None):
            rec["status"] = rec.get("result", "unknown")

        records.append(rec)

# sort ascending by ts (newest first)
records.sort(key=lambda r: r.get("ts", ""), reverse=True)
print(json.dumps(records))
PY
}

recent_recovery_entries() {
    if [[ ! -f "$RECOVERY_LOG" ]]; then
        echo "[]"
        return
    fi

    parse_recent_events
}

build_digest() {
    local events_json
    events_json=$(recent_recovery_entries)

    local evacuation_count founder_fail_count
    evacuation_count=$(echo "$events_json" | jq '[.[] | select((.script // "" | test("canonical-(evacuate|sync)")) and ((.status // "") == "failed" or (.status // "") == "evacuated"))] | length')
    founder_fail_count=$(echo "$events_json" | jq '[.[] | select(.script == "founder-briefing" and .status == "failure")] | length')

    local has_incidents=false
    if (( evacuation_count > 0 || founder_fail_count > 0 )); then
        has_incidents=true
    fi

    local lines=()
    lines+=("📊 DX Daily Digest - $(date -u +"%Y-%m-%dT%H:%M:%SZ")")
    lines+=("")

    # Evacuation summary
    if (( evacuation_count > 0 )); then
        lines+=("Recent evacuations (last 24h):")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            lines+=("  $line")
        done < <(echo "$events_json" | jq -r '[.[] | select((.script // "" | test("canonical-(evacuate|sync)")) and ((.status // "") == "failed" or (.status // "") == "evacuated")) | "\(.ts) | \(.repo) | \(.status) | \(.reason) | branch=\(.branch // "") | host=\(.host // "")"] | .[]')
        lines+=("")
    fi

    local evac_counts
    evac_counts=$(echo "$events_json" | jq -r 'reduce (.[] | select((.script // "" | test("canonical-(evacuate|sync)")) and ((.status // "") == "failed" or (.status // "") == "evacuated")) ) as $event ({}; .[($event.repo // "unknown")] += 1) | to_entries | sort_by(.key) | .[] | "\(.key): \(.value)"' 2>/dev/null || true)
    if [[ -n "$evac_counts" ]]; then
        lines+=("Evacuations by repo:")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            lines+=("  - $line")
        done <<< "$evac_counts"
        lines+=("")
    fi

    # Founder transport failures (high priority)
    if (( founder_fail_count > 0 )); then
        lines+=("Founder briefing failures (last 24h):")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            lines+=("  $line")
        done < <(echo "$events_json" | jq -r '[.[] | select(.script == "founder-briefing" and .status == "failure") | "\(.ts) | \(.host // "?") | \(.reason // "transport") | \(.raw)"] | .[]')
        lines+=("")
    fi

    if [[ "$has_incidents" == "false" ]]; then
        return 1
    fi

    printf '%s\n' "${lines[@]}"
    return 0
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
main() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
    fi

    local digest
    if ! digest=$(build_digest); then
        # build_digest returned 1 = skip (everything green)
        echo "✅ No evacuations or founder failures to report - skipping Slack post"
        exit 0
    fi

    echo "$digest"
    post_digest "$digest"
}

main "${@:-}"
