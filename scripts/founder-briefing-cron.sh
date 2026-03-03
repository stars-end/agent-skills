#!/bin/bash
# Founder Daily Briefing - System Cron Wrapper
# Bypasses OpenClaw native cron (broken isolated sessions)
#
# Prerequisites:
#   1. V4.2 service account token at ~/.config/systemd/user/op-$(hostname)-token
#   2. Created via: ~/agent-skills/scripts/create-op-credential.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Load V4.2 service account token (canonical pattern from cc-glm-headless.sh)
if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    TOKEN_FILE="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-$HOME/.config/systemd/user/op-$(hostname)-token}"
    if [[ -f "$TOKEN_FILE" ]]; then
        export OP_SERVICE_ACCOUNT_TOKEN=$(cat "$TOKEN_FILE")
    fi
fi

# GitHub authentication for cron environment
if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    GH_TOKEN=$(op read "op://dev/Agent-Secrets-Production/GITHUB_TOKEN" 2>/dev/null) || true
    if [[ -n "${GH_TOKEN:-}" ]]; then
        export GH_TOKEN
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Authenticated with GitHub via 1Password Service Account"
    fi
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

# Generate the message
MSG=$("${HOME}/agent-skills/scripts/dx-founder-daily.sh" --slack 2>/dev/null)

if [ -z "$MSG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Empty message generated"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message generated (${#MSG} chars)"

# Send via Agent Coordination Slack transport.
if agent_coordination_send_message "$MSG" "${DX_ALERTS_CHANNEL_ID:-}"; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Message sent successfully"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Slack transport unavailable"
  exit 1
fi
