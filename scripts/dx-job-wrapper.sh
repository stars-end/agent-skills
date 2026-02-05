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
fi

exit $EXIT_CODE
