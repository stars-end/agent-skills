#!/usr/bin/env bash
#
# dx-codex-weekly-health-cron.sh
#
# Weekly Slack digest wrapper for Codex VM health.
#
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
export DX_AUTH_UNATTENDED_OP=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

DRY_RUN=0
STATE_DIR="${DX_CODEX_HEALTH_STATE_DIR:-${HOME}/.dx-state/codex-weekly-health}"
CHANNEL="${DX_CODEX_HEALTH_SLACK_CHANNEL:-#dx-alerts}"

usage() {
  cat <<'EOF'
Usage: dx-codex-weekly-health-cron.sh [--dry-run] [--state-dir PATH]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

main() {
  parse_args "$@"

  local payload message channel log_file
  log_file="${HOME}/logs/dx/codex-weekly-health.log"
  mkdir -p "$(dirname "$log_file")"

  payload="$("$SCRIPT_DIR/dx-codex-weekly-health.sh" --json --state-dir "$STATE_DIR")"
  message="$(printf '%s\n' "$payload" | jq -r '.summary_text')"
  channel="$(agent_coordination_resolve_channel "$CHANNEL")"

  {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] channel=$channel"
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] state_dir=$STATE_DIR"
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] message=$message"
  } >> "$log_file"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '%s\n' "$message"
    printf '%s\n' "$payload"
    return 0
  fi

  agent_coordination_send_message "$message" "$channel"
}

main "$@"
