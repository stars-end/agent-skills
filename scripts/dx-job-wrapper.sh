#!/usr/bin/env bash
#
# dx-job-wrapper.sh
#
# Wraps a command with run-state tracking and structured logging.
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

log() {
    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] $1" >> "$LOG_FILE"
}

slack_alert_fail_once() {
    local timestamp="$1"
    local exit_code="$2"

    # Opt-in-ish: only attempt if a token exists.
    # On macmini this is usually set via launchctl env so scheduled jobs can alert.
    local token="${SLACK_BOT_TOKEN:-${SLACK_MCP_XOXB_TOKEN:-}}"
    if [[ -z "${token:-}" ]]; then
        return 0
    fi

    # Default to #all-stars-end (C09MQGMFKDE) but allow override.
    local channel="${DX_SLACK_CHANNEL:-C09MQGMFKDE}"

    # Avoid spam: alert only once per distinct failure timestamp.
    local alerted_file="$STATE_DIR/$JOB_NAME.last_fail_alerted"
    if [[ -f "$alerted_file" ]]; then
        if [[ "$(cat "$alerted_file" 2>/dev/null || true)" == "$timestamp (exit $exit_code)" ]]; then
            return 0
        fi
    fi

    local text="DX job failed: ${JOB_NAME} (exit ${exit_code}) at ${timestamp} UTC. Log: ${LOG_FILE}"

    # Use python for JSON escaping if available; otherwise best-effort with minimal escaping.
    local payload=""
    if command -v python3 >/dev/null 2>&1; then
        payload="$(python3 - <<PY
import json
print(json.dumps({"channel": "${channel}", "text": "${text}"}))
PY
)" || payload=""
    fi
    if [[ -z "${payload:-}" ]]; then
        # Minimal escape: backslash and double-quote.
        local esc_text="${text//\\/\\\\}"
        esc_text="${esc_text//\"/\\\"}"
        payload="{\"channel\":\"${channel}\",\"text\":\"${esc_text}\"}"
    fi

    # Best-effort; never fail the job because Slack is down.
    curl -sS -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-type: application/json; charset=utf-8" \
        --data "$payload" >/dev/null 2>&1 || true

    echo "$timestamp (exit $exit_code)" > "$alerted_file" 2>/dev/null || true
}

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

if [[ $EXIT_CODE -eq 0 ]]; then
    log "✅ Job succeeded"
    echo "$TIMESTAMP" > "$STATE_DIR/$JOB_NAME.last_ok"
else
    log "❌ Job failed with exit code $EXIT_CODE"
    echo "$TIMESTAMP (exit $EXIT_CODE)" > "$STATE_DIR/$JOB_NAME.last_fail"
    slack_alert_fail_once "$TIMESTAMP" "$EXIT_CODE"
fi

exit $EXIT_CODE
