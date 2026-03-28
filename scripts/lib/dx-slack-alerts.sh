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
#
# Local cache contract:
# - Slack transport secrets are cached in a local file to avoid repeated OP API calls
#   from hot-path checks and alerting loops.
# - Default TTL is 24h and can be tuned via DX_ALERTS_CACHE_TTL_SECONDS.

AGENT_COORDINATION_SELF_PATH="${BASH_SOURCE[0]:-$0}"
AGENT_COORDINATION_LIB_DIR="$(cd "$(dirname "${AGENT_COORDINATION_SELF_PATH}")" && pwd)"
# shellcheck disable=SC1091
source "${AGENT_COORDINATION_LIB_DIR}/dx-auth.sh" 2>/dev/null || true

agent_coordination_slack_token() {
  local token="${SLACK_MCP_XOXB_TOKEN:-}"
  if [[ -z "${token}" ]]; then token="${SLACK_MCP_XOXP_TOKEN:-}"; fi
  if [[ -z "${token}" ]]; then token="${SLACK_BOT_TOKEN:-}"; fi
  if [[ -z "${token}" ]]; then token="${SLACK_APP_TOKEN:-}"; fi
  printf '%s' "${token}"
}

agent_coordination_cache_file() {
  printf '%s' "${DX_ALERTS_CACHE_FILE:-$HOME/.cache/dx/alerts-transport.env}"
}

agent_coordination_cache_ttl_seconds() {
  printf '%s' "${DX_ALERTS_CACHE_TTL_SECONDS:-86400}"
}

agent_coordination_cache_cooldown_seconds() {
  printf '%s' "${DX_ALERTS_CACHE_COOLDOWN_SECONDS:-300}"
}

agent_coordination_file_mtime_epoch() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo 0
    return 0
  fi
  perl -e 'my @s = stat($ARGV[0]); print defined($s[9]) ? int($s[9]) : 0; exit 0' "$file" 2>/dev/null || echo 0
}

agent_coordination_cache_fresh() {
  local cache_file="$1"
  local ttl now mtime age
  ttl="$(agent_coordination_cache_ttl_seconds)"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=86400
  [[ -f "$cache_file" ]] || return 1
  mtime="$(agent_coordination_file_mtime_epoch "$cache_file")"
  now="$(date +%s)"
  age=$((now - mtime))
  [[ "$age" -le "$ttl" ]]
}

agent_coordination_load_transport_cache() {
  # Arg1: require fresh cache (1/0). Defaults to 1.
  local require_fresh="${1:-1}"
  local cache_file key value
  cache_file="$(agent_coordination_cache_file)"
  [[ -f "$cache_file" ]] || return 1
  if [[ "$require_fresh" == "1" ]] && ! agent_coordination_cache_fresh "$cache_file"; then
    return 1
  fi

  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    case "$key" in
      SLACK_BOT_TOKEN)
        [[ -n "${SLACK_BOT_TOKEN:-}" ]] || export SLACK_BOT_TOKEN="$value"
        ;;
      SLACK_APP_TOKEN)
        [[ -n "${SLACK_APP_TOKEN:-}" ]] || export SLACK_APP_TOKEN="$value"
        ;;
      DX_SLACK_WEBHOOK)
        [[ -n "${DX_SLACK_WEBHOOK:-}" ]] || export DX_SLACK_WEBHOOK="$value"
        ;;
      DX_ALERTS_WEBHOOK)
        [[ -n "${DX_ALERTS_WEBHOOK:-}" ]] || export DX_ALERTS_WEBHOOK="$value"
        ;;
    esac
  done < "$cache_file"
}

agent_coordination_transport_values_present() {
  if [[ -n "$(agent_coordination_slack_token)" ]]; then
    return 0
  fi
  if [[ -n "${DX_SLACK_WEBHOOK:-}" ]] || [[ -n "${DX_ALERTS_WEBHOOK:-}" ]]; then
    return 0
  fi
  return 1
}

agent_coordination_refresh_cooldown_file() {
  printf '%s.cooldown' "$(agent_coordination_cache_file)"
}

agent_coordination_refresh_on_cooldown() {
  local cooldown_file until now
  cooldown_file="$(agent_coordination_refresh_cooldown_file)"
  [[ -f "$cooldown_file" ]] || return 1
  until="$(cat "$cooldown_file" 2>/dev/null || true)"
  [[ "$until" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  [[ "$now" -lt "$until" ]]
}

agent_coordination_set_refresh_cooldown() {
  local cooldown_file now cooldown until
  cooldown_file="$(agent_coordination_refresh_cooldown_file)"
  cooldown="$(agent_coordination_cache_cooldown_seconds)"
  [[ "$cooldown" =~ ^[0-9]+$ ]] || cooldown=300
  now="$(date +%s)"
  until=$((now + cooldown))
  mkdir -p "$(dirname "$cooldown_file")"
  printf '%s\n' "$until" > "$cooldown_file"
}

agent_coordination_clear_refresh_cooldown() {
  local cooldown_file
  cooldown_file="$(agent_coordination_refresh_cooldown_file)"
  rm -f "$cooldown_file" >/dev/null 2>&1 || true
}

agent_coordination_refresh_transport_cache() {
  local cache_file lock_dir tmp_file item_json
  cache_file="$(agent_coordination_cache_file)"
  lock_dir="${cache_file}.lock"

  if agent_coordination_refresh_on_cooldown; then
    return 1
  fi

  mkdir -p "$(dirname "$cache_file")"
  if ! mkdir "$lock_dir" >/dev/null 2>&1; then
    # Another process is refreshing; fall back to cache if available.
    sleep 1
    agent_coordination_load_transport_cache 1 >/dev/null 2>&1 || true
    return 0
  fi

  tmp_file="$(mktemp "${cache_file}.tmp.XXXXXX")"
  trap 'rm -rf "${lock_dir:-}" "${tmp_file:-}" >/dev/null 2>&1 || true' RETURN

  if ! agent_coordination_load_op_token >/dev/null 2>&1; then
    agent_coordination_set_refresh_cooldown
    rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
    return 1
  fi
  if command -v dx_auth_refresh_agent_item_cache >/dev/null 2>&1; then
    if ! dx_auth_refresh_agent_item_cache >/dev/null 2>&1; then
      agent_coordination_set_refresh_cooldown
      rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
      return 1
    fi
    item_json="$(cat "$(dx_auth_agent_item_cache_file)" 2>/dev/null || true)"
  else
    if ! command -v op >/dev/null 2>&1; then
      agent_coordination_set_refresh_cooldown
      rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
      return 1
    fi

    item_json="$(dx_auth_run_op item get "Agent-Secrets-Production" --vault dev --format json 2>/dev/null || true)"
    if [[ -z "$item_json" ]]; then
      agent_coordination_set_refresh_cooldown
      rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  AC_ITEM_JSON="$item_json" python3 - "$tmp_file" <<'PY'
import json
import os
import sys

out_path = sys.argv[1]
raw = os.environ.get("AC_ITEM_JSON", "")
data = json.loads(raw) if raw else {}
fields = data.get("fields") or []
wanted = {
    "SLACK_BOT_TOKEN": "",
    "SLACK_APP_TOKEN": "",
    "DX_SLACK_WEBHOOK": "",
    "DX_ALERTS_WEBHOOK": "",
}
for f in fields:
    label = f.get("label")
    value = f.get("value")
    if label in wanted and isinstance(value, str):
        wanted[label] = value

with open(out_path, "w", encoding="utf-8") as fh:
    for k, v in wanted.items():
        fh.write(f"{k}={v}\n")
PY

  if ! grep -qE '^(SLACK_BOT_TOKEN|SLACK_APP_TOKEN|DX_SLACK_WEBHOOK|DX_ALERTS_WEBHOOK)=.+' "$tmp_file" 2>/dev/null; then
    agent_coordination_set_refresh_cooldown
    rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
    return 1
  fi

  chmod 600 "$tmp_file"
  mv "$tmp_file" "$cache_file"
  agent_coordination_clear_refresh_cooldown
  return 0
}

agent_coordination_load_op_token() {
  if ! command -v canonical_op_token_plaintext_candidates >/dev/null 2>&1; then
    local lib_dir canonical_targets
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    canonical_targets="${lib_dir%/lib}/canonical-targets.sh"
    if [[ -r "$canonical_targets" ]]; then
      # shellcheck disable=SC1090
      source "$canonical_targets"
    fi
  fi

  if command -v dx_auth_load_op_service_account_token >/dev/null 2>&1; then
    dx_auth_load_op_service_account_token >/dev/null 2>&1 && return 0
  fi

  if ! command -v op >/dev/null 2>&1; then
    return 1
  fi

  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    if dx_auth_op_token_valid "${OP_SERVICE_ACCOUNT_TOKEN}"; then
      return 0
    fi
  fi

  local -a plain_candidates=()
  if command -v canonical_op_token_plaintext_candidates >/dev/null 2>&1; then
    mapfile -t plain_candidates < <(canonical_op_token_plaintext_candidates "$HOME")
  else
    plain_candidates=(
      "${HOME}/.config/systemd/user/op-macmini-token"
      "${HOME}/.config/systemd/user/op-homedesktop-wsl-token"
      "${HOME}/.config/systemd/user/op-epyc6-token"
      "${HOME}/.config/systemd/user/op-epyc12-token"
      "${HOME}/.config/systemd/user/op_token"
    )
  fi
  local candidate
  for candidate in "${plain_candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      local token
      token="$(cat "$candidate" 2>/dev/null || true)"
      if [[ -n "$token" ]]; then
        if dx_auth_op_token_valid "$token"; then
          export OP_SERVICE_ACCOUNT_TOKEN="$token"
          return 0
        fi
      fi
    fi
  done

  local -a cred_candidates=()
  if command -v canonical_op_token_cred_candidates >/dev/null 2>&1; then
    mapfile -t cred_candidates < <(canonical_op_token_cred_candidates "$HOME")
  else
    cred_candidates=(
      "${HOME}/.config/systemd/user/op-macmini-token.cred"
      "${HOME}/.config/systemd/user/op-homedesktop-wsl-token.cred"
      "${HOME}/.config/systemd/user/op-epyc6-token.cred"
      "${HOME}/.config/systemd/user/op-epyc12-token.cred"
      "${HOME}/.config/systemd/user/op_token.cred"
    )
  fi
  if command -v systemd-creds >/dev/null 2>&1; then
    for candidate in "${cred_candidates[@]}"; do
      if [[ -r "$candidate" ]]; then
        local decrypted
        decrypted="$(systemd-creds decrypt "$candidate" 2>/dev/null || true)"
        if [[ -n "$decrypted" ]]; then
          if dx_auth_op_token_valid "$decrypted"; then
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
  if command -v dx_auth_read_secret_cached >/dev/null 2>&1; then
    dx_auth_read_secret_cached "$value"
    return $?
  fi
  agent_coordination_load_op_token >/dev/null 2>&1 || true
  if ! command -v op >/dev/null 2>&1; then
    return 1
  fi
  dx_auth_run_op read "$value" 2>/dev/null || true
}

agent_coordination_prepare_transport() {
  # 1) Keep explicit env values as highest precedence.
  if agent_coordination_transport_values_present; then
    return 0
  fi

  # 2) Load fresh cache (24h TTL by default).
  agent_coordination_load_transport_cache 1 >/dev/null 2>&1 || true
  if agent_coordination_transport_values_present; then
    return 0
  fi

  # 3) Refresh cache in a single OP API call (with cooldown on failures), then load.
  agent_coordination_refresh_transport_cache >/dev/null 2>&1 || true
  agent_coordination_load_transport_cache 1 >/dev/null 2>&1 || true
  if agent_coordination_transport_values_present; then
    return 0
  fi

  # 4) Fallback to stale cache if refresh failed (e.g., rate-limited).
  agent_coordination_load_transport_cache 0 >/dev/null 2>&1 || true
  if agent_coordination_transport_values_present; then
    return 0
  fi

  # 5) Last-resort legacy per-ref lookup (used if custom refs are configured).
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
  return 0
}

agent_coordination_transport_ready() {
  agent_coordination_prepare_transport
  if agent_coordination_transport_values_present; then
    return 0
  fi
  return 1
}

agent_coordination_dx_alerts_channel() {
  printf '%s' "${DX_ALERTS_CHANNEL_ID:-C0ADSSZV9M2}"
}

agent_coordination_fleet_events_channel() {
  printf '%s' "${FLEET_EVENTS_CHANNEL_ID:-C0A8YU9JW06}"
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
    channel="$(agent_coordination_default_channel)"
  fi
  # Human-readable alias used by Fleet Sync manifests/runbooks.
  if [[ "$channel" == "#dx-alerts" ]]; then
    channel="$(agent_coordination_dx_alerts_channel)"
  fi
  if [[ "$channel" == "#fleet-events" ]]; then
    channel="$(agent_coordination_fleet_events_channel)"
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
  channel="$(agent_coordination_resolve_channel "$channel")"
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
