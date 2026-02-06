#!/usr/bin/env bash
#
# dx-heartbeat-watchdog.sh
#
# Detects missing Slack heartbeats (dx-pulse, dx-daily).
# macmini only.
#
set -euo pipefail

# Config
PULSE_WARN_THRESHOLD=10800  # 3h
PULSE_FAIL_THRESHOLD=21600  # 6h
DAILY_WARN_HOUR=6
DAILY_FAIL_HOUR=8

CHANNEL="C09MQGMFKDE" # #all-stars-end (assumed; verify if needed)
STATE_DIR="$HOME/.dx-state"

log_slack() {
    local msg="$1"
    echo "Slack alert: $msg"

    local token="${SLACK_BOT_TOKEN:-${SLACK_MCP_XOXB_TOKEN:-}}"
    if [[ -z "${token:-}" ]]; then
        return 0
    fi

    local payload=""
    if command -v python3 >/dev/null 2>&1; then
        payload="$(python3 - <<PY
import json
print(json.dumps({"channel": "${CHANNEL}", "text": "${msg}"}))
PY
)" || payload=""
    fi
    if [[ -z "${payload:-}" ]]; then
        local esc="${msg//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        payload="{\"channel\":\"${CHANNEL}\",\"text\":\"${esc}\"}"
    fi

    curl -sS -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-type: application/json; charset=utf-8" \
        --data "$payload" >/dev/null 2>&1 || true
}

rate_limit_key() {
    local key="$1"
    local today
    today="$(date +%Y-%m-%d)"
    local f="$STATE_DIR/dx-heartbeat-watchdog.${key}.last_sent"
    mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
    if [[ -f "$f" && "$(cat "$f" 2>/dev/null || true)" == "$today" ]]; then
        return 1
    fi
    echo "$today" > "$f" 2>/dev/null || true
    return 0
}

check_pulse() {
    local f="$STATE_DIR/dx-pulse.last_ok"
    local now=$(date +%s)
    local last_ok=0
    
    if [[ -f "$f" ]]; then
        # Handle ISO timestamp from dx-job-wrapper
        local ts_str=$(cat "$f" | cut -d' ' -f1)
        last_ok=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts_str" +%s 2>/dev/null || date -d "$ts_str" +%s 2>/dev/null || echo 0)
    fi

    local age=$((now - last_ok))
    local hour=$(date +%H)
    
    # Only monitor during 06:00-16:00
    if [[ "$hour" -ge 6 && "$hour" -le 16 ]]; then
        if [[ $age -gt $PULSE_FAIL_THRESHOLD ]]; then
            if rate_limit_key "pulse.fail"; then
                log_slack "🚨 EGREGIOUS: @fengning DX Pulse missing for >6h ($((age/3600))h). Next: dx-schedule-install.sh --apply"
            fi
        elif [[ $age -gt $PULSE_WARN_THRESHOLD ]]; then
            if rate_limit_key "pulse.warn"; then
                log_slack "⚠️ WARN: DX Pulse missing for >3h ($((age/3600))h). Next: dx-schedule-install.sh --apply"
            fi
        fi
    fi
}

check_daily() {
    local f="$STATE_DIR/dx-daily.last_ok"
    local now=$(date +%s)
    local today_start=$(date -v0H -v0M -v0S +%s 2>/dev/null || date -d "00:00:00" +%s 2>/dev/null || echo 0)
    local last_ok=0
    
    if [[ -f "$f" ]]; then
        local ts_str=$(cat "$f" | cut -d' ' -f1)
        last_ok=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts_str" +%s 2>/dev/null || date -d "$ts_str" +%s 2>/dev/null || echo 0)
    fi

    local hour=$(date +%H)
    
    if [[ $last_ok -lt $today_start ]]; then
        if [[ "$hour" -ge $DAILY_FAIL_HOUR ]]; then
            if rate_limit_key "daily.fail"; then
                log_slack "🚨 EGREGIOUS: @fengning DX Daily missing for today. Next: dx-schedule-install.sh --apply"
            fi
        elif [[ "$hour" -ge $DAILY_WARN_HOUR ]]; then
            if rate_limit_key "daily.warn"; then
                log_slack "⚠️ WARN: DX Daily missing for today. Next: dx-schedule-install.sh --apply"
            fi
        fi
    fi
}

# Only run on macmini
HOSTNAME=$(hostname -s)
if [[ "$HOSTNAME" != "macmini" && "$HOSTNAME" != "Fengs-Mac-mini-3" ]]; then
    exit 0
fi

check_pulse
check_daily
