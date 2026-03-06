#!/usr/bin/env bash
#
# dx-audit-cron.sh
#
# Cron wrapper for Fleet audit posting.
<<<<<<< Updated upstream
# Produces deterministic one-message payloads for #fleet-events.
=======
# Produces deterministic one-message payloads for #dx-alerts.
>>>>>>> Stashed changes
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

MODE="weekly"
DRY_RUN=0
STATE_DIR="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"

usage() {
  cat <<'EOF'
Usage:
  dx-audit-cron.sh --daily [--state-dir PATH] [--dry-run]
  dx-audit-cron.sh --weekly [--state-dir PATH] [--dry-run]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --daily)
        MODE="daily"
        shift
        ;;
      --weekly)
        MODE="weekly"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --state-dir)
        STATE_DIR="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

render_payload() {
  "$SCRIPT_DIR/dx-fleet.sh" audit "--$MODE" --json --state-dir "$STATE_DIR" 2>&1
}

main() {
  local payload
  local message
  local manifest_channel
  local log_file="${HOME}/logs/dx-audit.log"
<<<<<<< Updated upstream
  local channel="#fleet-events"
=======
  local channel="#dx-alerts"
>>>>>>> Stashed changes
  local audit_exit=0
  mkdir -p "$(dirname "$log_file")"

  set +e
  payload="$(render_payload)"
  audit_exit=$?
  set -e
  if ! printf '%s\n' "$payload" | jq -e '.mode' >/dev/null 2>&1; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: invalid JSON from dx-audit.sh" >&2
    echo "$payload" >> "$log_file"
    exit 1
  fi

  message="$(printf '%s\n' "$payload" | jq -r '.slack_message // ""')"
  if [[ -z "$message" ]]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: no slack_message in payload" >&2
    exit 1
  fi
  manifest_channel="$(printf '%s\n' "$payload" | jq -r '.slack_channel // empty')"
  if [[ -n "$manifest_channel" ]]; then
    channel="$manifest_channel"
  fi
<<<<<<< Updated upstream
  channel="$(agent_coordination_resolve_channel "${DX_ALERTS_CHANNEL_ID:-$channel}")"
=======
>>>>>>> Stashed changes

  {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] mode=$MODE"
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] channel=${DX_ALERTS_CHANNEL_ID:-$channel}"
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] message=$message"
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] state_dir=$STATE_DIR"
  } >> "$log_file"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "$message"
    printf '%s\n' "$payload"
    return "$audit_exit"
  fi

<<<<<<< Updated upstream
  if agent_coordination_send_message "$message" "$channel"; then
=======
  if agent_coordination_send_message "$message" "${DX_ALERTS_CHANNEL_ID:-$channel}"; then
>>>>>>> Stashed changes
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] audit message sent to $channel"
    return "$audit_exit"
  fi

  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: transport unavailable for channel=$channel" >&2
  if [[ "$audit_exit" -ne 0 ]]; then
    return "$audit_exit"
  fi
  return 1
}

parse_args "$@"
main
