#!/usr/bin/env bash
set -euo pipefail

# Canonical deterministic Slack transport for Agent Coordination app.
#
# Transport policy (deterministic):
# - Use this library for deterministic scripts (alerts, audit posts, incident fanout).
# - Keep deterministic and LLM calls separate:
#   - deterministic / rule-based alerts: agent_coordination_send_message
#   - reasoning / summarization workflows: OpenClaw/LLM tools
#
# Token precedence:
# - Uses SLACK_MCP_XOXB_TOKEN if set
# - then SLACK_MCP_XOXP_TOKEN
# - then SLACK_BOT_TOKEN (preferred default from Agent-Secrets-Production)
# - then SLACK_APP_TOKEN (fallback if needed)
#
# OpenClaw tokens are still supported for non-deterministic contexts where required by
# downstream tooling.
# - Uses SLACK_BOT_TOKEN (preferred), then SLACK_APP_TOKEN if needed.
# - Resolves channel by ENVIRONMENT:
#   - production/prod -> C0AE2SPCY2Y (#railway-prod-alerts)
#   - staging       -> C0AG61W6TU5 (#railway-staging-alerts)
#   - others (default) -> C0AEC54RZ6V (#railway-dev-alerts)
#
# Optional override:
#   - DX_ALERTS_CHANNEL_ID can point to a fixed Slack channel ID.

agent_coordination_slack_token() {
  local token="${SLACK_MCP_XOXB_TOKEN:-}"
  if [[ -z "${token}" ]]; then token="${SLACK_MCP_XOXP_TOKEN:-}"; fi
  if [[ -z "${token}" ]]; then token="${SLACK_BOT_TOKEN:-}"; fi
  if [[ -z "${token}" ]]; then token="${SLACK_APP_TOKEN:-}"; fi
  printf '%s' "${token}"
}

agent_coordination_default_channel() {
  local env="${ENVIRONMENT:-dev}"

  case "$env" in
    production|prod)
      echo "C0AE2SPCY2Y"
      ;;
    staging)
      echo "C0AG61W6TU5"
      ;;
    *)
      echo "C0AEC54RZ6V"
      ;;
  esac
}

agent_coordination_post_message() {
  local message="$1"
  local channel="${2:-$(agent_coordination_default_channel)}"
  local token
  token="$(agent_coordination_slack_token)"

  if [[ -z "${token}" ]]; then
    return 1
  fi

  local payload
  payload="$(python3 - "$channel" "$message" <<'PY'
import json
import sys

channel = sys.argv[1]
message = sys.argv[2]

print(json.dumps({
    "channel": channel,
    "text": message,
}))
PY
)"

  local response
  response="$(curl -s -m 5 -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-type: application/json; charset=utf-8" \
    -d "$payload" || true)"

  if [[ -z "${response}" ]]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    if echo "${response}" | jq -e '.ok == true' >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi

  [[ "${response}" == *"\"ok\":true"* ]]
}

agent_coordination_send_message() {
  local message="$1"
  local channel="${2:-${DX_ALERTS_CHANNEL_ID:-$(agent_coordination_default_channel)}}"
  local webhook_url="${DX_SLACK_WEBHOOK:-}"

  if agent_coordination_post_message "$message" "$channel"; then
    return 0
  fi

  if [[ -n "${webhook_url}" ]]; then
    local webhook_payload
    webhook_payload="$(python3 - "$message" <<'PY'
import json
import sys

message = sys.argv[1]
print(json.dumps({"text": message}))
PY
)"
    curl -s -m 5 -X POST "${webhook_url}" \
      -H 'Content-type: application/json' \
      -d "$webhook_payload" \
      >/dev/null 2>&1 || true
    return 0
  fi

  return 1
}
