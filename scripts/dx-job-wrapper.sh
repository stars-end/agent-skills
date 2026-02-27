#!/usr/bin/env bash
#
# dx-job-wrapper.sh
#
# Wraps a command with run-state tracking, structured logging, and Slack alerts.
#
# Usage:
#   dx-job-wrapper.sh <job_name> -- <command...>
#
set -u

JOB_NAME="${1:-}"
shift || true

# Check for -- separator
if [[ "${1:-}" == "--" ]]; then
    shift
else
    echo "Usage: dx-job-wrapper <job_name> -- <command...>"
    exit 1
fi

if [[ -z "$JOB_NAME" ]]; then
    echo "Error: job_name is required"
    exit 1
fi

COMMAND=("$@")
if [[ ${#COMMAND[@]} -eq 0 ]]; then
    echo "Error: no command provided"
    exit 1
fi

STATE_DIR="$HOME/.dx-state"
LOG_DIR="$HOME/logs/dx"
mkdir -p "$STATE_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/$JOB_NAME.log"
LOCK_DIR="$STATE_DIR/locks/${JOB_NAME}.lock"
LOCK_TTL_SECONDS="${DX_JOB_LOCK_TTL_SECONDS:-21600}"
LOCK_ACQUIRED=0

log() {
    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] $1" >> "$LOG_FILE"
}

file_mtime_epoch() {
    local path="$1"
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        stat -f '%m' "$path"
    elif stat -c '%Y' "$path" >/dev/null 2>&1; then
        stat -c '%Y' "$path"
    else
        echo "0"
    fi
}

release_lock() {
    if [[ "$LOCK_ACQUIRED" -eq 1 ]]; then
        rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true
    fi
}

acquire_lock() {
    mkdir -p "$(dirname "$LOCK_DIR")"

    if mkdir "$LOCK_DIR" >/dev/null 2>&1; then
        LOCK_ACQUIRED=1
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$LOCK_DIR/started_at"
        return 0
    fi

    local now_ts lock_mtime age
    now_ts=$(date +%s)
    lock_mtime=$(file_mtime_epoch "$LOCK_DIR")
    age=$((now_ts - lock_mtime))

    if [[ "$LOCK_TTL_SECONDS" =~ ^[0-9]+$ ]] && [[ "$age" -gt "$LOCK_TTL_SECONDS" ]]; then
        log "⚠️  Removing stale lock for $JOB_NAME (age=${age}s, ttl=${LOCK_TTL_SECONDS}s)"
        rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true
        if mkdir "$LOCK_DIR" >/dev/null 2>&1; then
            LOCK_ACQUIRED=1
            printf '%s\n' "$$" > "$LOCK_DIR/pid"
            printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$LOCK_DIR/started_at"
            return 0
        fi
    fi

    log "⏭️  Skipping job: $JOB_NAME lock is already held"
    return 1
}

trap release_lock EXIT INT TERM

if ! acquire_lock; then
    exit 0
fi

# Determine previous state before running
PREV_STATE="ok"
if [[ -f "$STATE_DIR/${JOB_NAME}.last_fail" ]]; then
    PREV_STATE="fail"
fi

log "--- Starting job: $JOB_NAME ---"
log "Command: ${COMMAND[*]}"

# Run command and capture output + exit code
TMP_OUT=$(mktemp)

# Execute
set +e
"${COMMAND[@]}" > "$TMP_OUT" 2>&1
EXIT_CODE=$?
set -e

# Append output to log
cat "$TMP_OUT" >> "$LOG_FILE"
rm -f "$TMP_OUT"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CURR_STATE="ok"

if [[ $EXIT_CODE -eq 0 ]]; then
    log "✅ Job succeeded"
    echo "$TIMESTAMP" > "$STATE_DIR/$JOB_NAME.last_ok"
    # Remove fail marker if it exists
    rm -f "$STATE_DIR/$JOB_NAME.last_fail"
else
    log "❌ Job failed with exit code $EXIT_CODE"
    echo "$TIMESTAMP (exit $EXIT_CODE)" > "$STATE_DIR/$JOB_NAME.last_fail"
    CURR_STATE="fail"
fi

# Slack alerting on state transitions
SLACK_WEBHOOK_URL="${DX_SLACK_WEBHOOK:-}"
OPENCLAW="$HOME/.local/bin/mise x node@22.21.1 -- openclaw"
ALERTS_CHANNEL="C0ADSSZV9M2"

if [[ "$PREV_STATE" != "$CURR_STATE" ]]; then
    EMOJI="✅"
    MSG="DX job '$JOB_NAME' recovered on $(hostname -s)"
    if [[ "$CURR_STATE" == "fail" ]]; then
        EMOJI="🚨"
        MSG="DX job '$JOB_NAME' failed on $(hostname -s) (exit $EXIT_CODE)"
    fi

    # Try integrated OpenClaw messenger first
    SENT_INTEGRATED=0
    if command -v "$HOME/.local/bin/mise" &> /dev/null; then
        if $OPENCLAW message send --channel slack --target "$ALERTS_CHANNEL" --message "${EMOJI} ${MSG}" >/dev/null 2>&1; then
            SENT_INTEGRATED=1
        fi
    fi

    # Fallback to legacy webhook if necessary
    if [[ "$SENT_INTEGRATED" -eq 0 && -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -s -m 5 -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-type: application/json' \
            -d "{\"text\": \"${EMOJI} ${MSG}\"}" \
            >/dev/null 2>&1 || true
    fi
fi

# Update Cron Jobs section in Heartbeat
HEARTBEAT="$STATE_DIR/HEARTBEAT.md"
if [[ -f "$HEARTBEAT" ]]; then
    FAILED_JOBS=$(find "$STATE_DIR" -name "*.last_fail" -maxdepth 1 -exec basename {} \; | sed 's/\.last_fail//' | tr '\n' ',' | sed 's/,$//')
    if [[ -z "$FAILED_JOBS" ]]; then FAILED_JOBS="none"; fi

    hb_status="OK"
    if [[ "$FAILED_JOBS" != "none" ]]; then hb_status="ERROR"; fi
    
    tmpfile=$(mktemp)
    awk -v status="$hb_status" -v failed="$FAILED_JOBS" -v now="$TIMESTAMP" '
        BEGIN { in_section=0 }
        $0 == "### Cron Jobs" {
            in_section=1
            print $0
            print "<!-- Updated by dx-job-wrapper.sh -->"
            print "Status: " status
            print "Last check: " now
            print "Failed jobs: " failed
            print ""
            next
        }
        /^### / && in_section { in_section=0 }
        !in_section { print }
    ' "$HEARTBEAT" > "$tmpfile" && mv "$tmpfile" "$HEARTBEAT"
fi

exit $EXIT_CODE
