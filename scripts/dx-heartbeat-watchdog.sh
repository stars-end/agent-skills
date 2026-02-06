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
    # Use internal tool if available, or just log to stdout for now
    # slack_conversations_add_message --channel "$CHANNEL" --text "$msg"
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
            log_slack "🚨 EGREGIOUS: @fengning DX Pulse missing for >6h ($((age/3600))h). Next: dx-schedule-install.sh --apply"
        elif [[ $age -gt $PULSE_WARN_THRESHOLD ]]; then
            log_slack "⚠️ WARN: DX Pulse missing for >3h ($((age/3600))h). Next: dx-schedule-install.sh --apply"
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
            log_slack "🚨 EGREGIOUS: @fengning DX Daily missing for today. Next: dx-schedule-install.sh --apply"
        elif [[ "$hour" -ge $DAILY_WARN_HOUR ]]; then
            log_slack "⚠️ WARN: DX Daily missing for today. Next: dx-schedule-install.sh --apply"
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
