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
#   - others (default) -> C0A8YU9JW06 (#fleet-events)
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

agent_coordination_load_op_token() {
  if ! command -v op >/dev/null 2>&1; then
    return 1
  fi

  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    if OP_SERVICE_ACCOUNT_TOKEN="${OP_SERVICE_ACCOUNT_TOKEN}" op whoami >/dev/null 2>&1; then
      return 0
    fi
  fi

  local host_short
  host_short="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
  local host_full
  host_full="$(hostname 2>/dev/null || printf '%s' "$host_short")"
  local -a plain_candidates=(
    "${HOME}/.config/systemd/user/op-${host_short}-token"
    "${HOME}/.config/systemd/user/op-${host_full}-token"
    "${HOME}/.config/systemd/user/op-${CANONICAL_HOST_KEY:-}-token"
    "${HOME}/.config/systemd/user/op-macmini-token"
    "${HOME}/.config/systemd/user/op-homedesktop-wsl-token"
    "${HOME}/.config/systemd/user/op-epyc6-token"
    "${HOME}/.config/systemd/user/op-epyc12-token"
  )
  local candidate
  for candidate in "${plain_candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      local token
      token="$(cat "$candidate" 2>/dev/null || true)"
      if [[ -n "$token" ]]; then
        if OP_SERVICE_ACCOUNT_TOKEN="$token" op whoami >/dev/null 2>&1; then
          export OP_SERVICE_ACCOUNT_TOKEN="$token"
          return 0
        fi
      fi
    fi
  done

  local -a cred_candidates=(
    "${HOME}/.config/systemd/user/op-${host_short}-token.cred"
    "${HOME}/.config/systemd/user/op-${host_full}-token.cred"
    "${HOME}/.config/systemd/user/op-${CANONICAL_HOST_KEY:-}-token.cred"
    "${HOME}/.config/systemd/user/op-macmini-token.cred"
    "${HOME}/.config/systemd/user/op-homedesktop-wsl-token.cred"
    "${HOME}/.config/systemd/user/op-epyc6-token.cred"
    "${HOME}/.config/systemd/user/op-epyc12-token.cred"
  )
  if command -v systemd-creds >/dev/null 2>&1; then
    for candidate in "${cred_candidates[@]}"; do
      if [[ -r "$candidate" ]]; then
        local decrypted
        decrypted="$(systemd-creds decrypt "$candidate" 2>/dev/null || true)"
        if [[ -n "$decrypted" ]]; then
          if OP_SERVICE_ACCOUNT_TOKEN="$decrypted" op whoami >/dev/null 2>&1; then
            export OP_SERVICE_ACCOUNT_TOKEN="$decrypted"
            return 0
          fi
        fi
      fi
    done
  fi

  return 1
}

agent_coordination_resolve_op_ref() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    return 1
  fi
  if [[ "$value" != op://* ]]; then
    printf '%s' "$value"
    return 0
  fi
  agent_coordination_load_op_token >/dev/null 2>&1 || true
  if ! command -v op >/dev/null 2>&1; then
    return 1
  fi
  op read "$value" 2>/dev/null || true
}

agent_coordination_prepare_transport() {
  agent_coordination_load_op_token >/dev/null 2>&1 || true

  if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
    local resolved_bot
    resolved_bot="$(agent_coordination_resolve_op_ref "${SLACK_BOT_TOKEN_REF:-op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN}")"
    [[ -n "$resolved_bot" ]] && export SLACK_BOT_TOKEN="$resolved_bot"
  fi

  if [[ -z "${SLACK_APP_TOKEN:-}" ]]; then
    local resolved_app
    resolved_app="$(agent_coordination_resolve_op_ref "${SLACK_APP_TOKEN_REF:-op://dev/Agent-Secrets-Production/SLACK_APP_TOKEN}")"
    [[ -n "$resolved_app" ]] && export SLACK_APP_TOKEN="$resolved_app"
  fi

  if [[ -z "${DX_SLACK_WEBHOOK:-}" ]]; then
    local resolved_hook
    resolved_hook="$(agent_coordination_resolve_op_ref "${DX_SLACK_WEBHOOK_REF:-op://dev/Agent-Secrets-Production/DX_SLACK_WEBHOOK}")"
    [[ -n "$resolved_hook" ]] && export DX_SLACK_WEBHOOK="$resolved_hook"
  fi

  if [[ -z "${DX_ALERTS_WEBHOOK:-}" ]]; then
    local resolved_alert_hook
    resolved_alert_hook="$(agent_coordination_resolve_op_ref "${DX_ALERTS_WEBHOOK_REF:-op://dev/Agent-Secrets-Production/DX_ALERTS_WEBHOOK}")"
    [[ -n "$resolved_alert_hook" ]] && export DX_ALERTS_WEBHOOK="$resolved_alert_hook"
  fi
}

agent_coordination_transport_ready() {
  agent_coordination_prepare_transport
  if [[ -n "$(agent_coordination_slack_token)" ]]; then
    return 0
  fi
  if [[ -n "${DX_SLACK_WEBHOOK:-}" ]] || [[ -n "${DX_ALERTS_WEBHOOK:-}" ]]; then
    return 0
  fi
  return 1
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
      echo "C0A8YU9JW06"
      ;;
  esac
}

agent_coordination_resolve_channel() {
  local channel="${1:-}"
  if [[ -z "$channel" ]]; then
    channel="${DX_ALERTS_CHANNEL_ID:-$(agent_coordination_default_channel)}"
  fi
  # Human-readable alias used by Fleet Sync manifests/runbooks.
  if [[ "$channel" == "#dx-alerts" ]]; then
    channel="${DX_ALERTS_CHANNEL_ID:-C0A8YU9JW06}"
  fi
  if [[ "$channel" == "#fleet-events" ]]; then
    channel="${DX_ALERTS_CHANNEL_ID:-C0A8YU9JW06}"
  fi
  printf '%s' "$channel"
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
    if echo "${response}" | jq -e '.error == "not_in_channel"' >/dev/null 2>&1; then
      curl -s -m 5 -X POST "https://slack.com/api/conversations.join" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-type: application/json; charset=utf-8" \
        -d "{\"channel\":\"${channel}\"}" \
        >/dev/null 2>&1 || true
      response="$(curl -s -m 5 -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-type: application/json; charset=utf-8" \
        -d "$payload" || true)"
      if [[ -n "$response" ]] && echo "${response}" | jq -e '.ok == true' >/dev/null 2>&1; then
        return 0
      fi
    fi
    return 1
  fi

  if [[ "${response}" == *"\"ok\":true"* ]]; then
    return 0
  fi
  if [[ "${response}" == *"\"error\":\"not_in_channel\""* ]]; then
    curl -s -m 5 -X POST "https://slack.com/api/conversations.join" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-type: application/json; charset=utf-8" \
      -d "{\"channel\":\"${channel}\"}" \
      >/dev/null 2>&1 || true
    response="$(curl -s -m 5 -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-type: application/json; charset=utf-8" \
      -d "$payload" || true)"
    [[ "${response}" == *"\"ok\":true"* ]]
    return $?
  fi
  return 1
}

agent_coordination_send_message() {
  local message="$1"
  local channel="${2:-${DX_ALERTS_CHANNEL_ID:-$(agent_coordination_default_channel)}}"
  local webhook_url="${DX_SLACK_WEBHOOK:-}"

  agent_coordination_prepare_transport
<<<<<<< Updated upstream
  channel="$(agent_coordination_resolve_channel "$channel")"
=======
>>>>>>> Stashed changes
  webhook_url="${DX_SLACK_WEBHOOK:-${DX_ALERTS_WEBHOOK:-}}"

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
