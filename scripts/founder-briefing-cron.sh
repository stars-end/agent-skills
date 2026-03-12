#!/bin/bash
# Founder Daily Briefing - System Cron Wrapper
# Bypasses OpenClaw native cron (broken isolated sessions)
#
# Prerequisites:
#   1. V4.2 service account token at ~/.config/systemd/user/op-<canonical-host-key>-token
#   2. Created via: ~/agent-skills/scripts/create-op-credential.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"

# Optional dry-run mode for postless validation
DRY_RUN="false"
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="true"
fi

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

STATE_DIR="$HOME/.dx-state"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"
mkdir -p "$STATE_DIR"

log_founder_event() {
    local status="$1"
    local reason="$2"
    local detail="${3:-}"
    local ts
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    if [[ -n "$detail" ]]; then
        echo "${ts} | script=founder-briefing | repo=agent-skills | host=${HOSTNAME:-$(hostname -s)} | status=${status} | reason=${reason} | ${detail}" >> "$RECOVERY_LOG"
    else
        echo "${ts} | script=founder-briefing | repo=agent-skills | host=${HOSTNAME:-$(hostname -s)} | status=${status} | reason=${reason}" >> "$RECOVERY_LOG"
    fi
}

run_founder_daily() {
    local output_file="$1"
    local log_file="$2"

    "${HOME}/agent-skills/scripts/dx-founder-daily.sh" --json >"$output_file" 2>"$log_file"
}

# GitHub authentication for cron environment
if dx_auth_load_github_token >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Authenticated with GitHub via cached 1Password token"
fi

# Fallback: Try existing gh auth if available (interactive sessions)
if [[ -z "${GH_TOKEN:-}" ]]; then
    if gh auth status &>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using existing gh auth (keyring)"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: No GitHub authentication available"
    fi
fi

LOG_FILE="${HOME}/logs/founder-briefing.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting founder briefing..."
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY-RUN mode enabled"
fi

TMP_MSG=$(mktemp)
TMP_ERR=$(mktemp)

if ! run_founder_daily "$TMP_MSG" "$TMP_ERR"; then
    founder_payload="$(cat "$TMP_MSG" 2>/dev/null || true)"
    founder_status="$(echo "$founder_payload" | jq -r '.founder_pipeline.status // "failed"' 2>/dev/null || echo "failed")"
    reason="$(echo "$founder_payload" | jq -r '.founder_pipeline.reason // "execution_error"' 2>/dev/null || echo "execution_error")"
    source="$(echo "$founder_payload" | jq -r '.founder_pipeline.source // "unknown"' 2>/dev/null || echo "unknown")"

    founder_error="unknown"
    if [[ -s "$TMP_ERR" ]]; then
        founder_error="$(sed -n '1,6p' "$TMP_ERR" | tr '\n' '; ' | sed 's/"/\\"/g' | cut -c1-400)"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Founder daily failed; status=${founder_status} source=${source} reason=${reason}"
    if [[ -n "$founder_error" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR details: ${founder_error}"
    fi

    log_founder_event "failure" "$reason" "source=${source} status=${founder_status} error=founder_daily_script_failed"
    rm -f "$TMP_MSG" "$TMP_ERR"
    exit 1
fi

MSG="$(cat "$TMP_MSG")"
rm -f "$TMP_MSG" "$TMP_ERR"

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -z "$MSG" ]]; then
        MSG='{"founder_pipeline":{"status":"ok","source":"unknown","reason":"dry-run"}}'
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY-RUN payload (not posted):"
    echo "$MSG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DRY-RUN pipeline: $(echo "$MSG" | jq -c '{status:.founder_pipeline.status // "ok",source:.founder_pipeline.source // "unknown",reason:.founder_pipeline.reason // "none"}' 2>/dev/null || true)"
    log_founder_event "success" "dry-run" "no_post"
    exit 0
fi

if [[ -z "$MSG" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty message generated"
    log_founder_event "failure" "empty_message" "exit=1"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message generated (${#MSG} chars)"

# Send via Agent Coordination Slack transport.
if agent_coordination_send_message "$MSG" "${DX_ALERTS_CHANNEL_ID:-}"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message sent successfully"
    log_founder_event "success" "posted" "chars=${#MSG}"
    exit 0
else
    founder_status="$(echo "$MSG" | jq -r '.founder_pipeline.status // "ok"' 2>/dev/null || echo "ok")"
    founder_source="$(echo "$MSG" | jq -r '.founder_pipeline.source // "unknown"' 2>/dev/null || echo "unknown")"
    founder_reason="$(echo "$MSG" | jq -r '.founder_pipeline.reason // "transport_blocked"' 2>/dev/null || echo "transport_blocked")"
    if [[ "$founder_status" == "ok" ]]; then
        founder_reason="transport_unavailable"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport unavailable"
    log_founder_event "failure" "$founder_reason" "source=${founder_source} status=${founder_status} error=agent_coordination_send_message"
    exit 1
fi
