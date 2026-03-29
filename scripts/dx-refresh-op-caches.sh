#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/canonical-targets.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
export DX_AUTH_UNATTENDED_OP=1

dx_op_cache_stamp_file() {
  printf '%s\n' "${DX_OP_CACHE_STAMP_FILE:-$HOME/.cache/dx/op-cache-refresh.env}"
}

write_stamp() {
  local stamp_file tmp_file
  stamp_file="$(dx_op_cache_stamp_file)"
  mkdir -p "$(dirname "$stamp_file")"
  tmp_file="$(mktemp "${stamp_file}.tmp.XXXXXX")"
  {
    printf 'DX_OP_CACHE_SOURCE_HOST=%s\n' "${CANONICAL_HOST_KEY:-unknown}"
    printf 'DX_OP_CACHE_SOURCE_SSH=%s\n' "${CANONICAL_VM_LINUX2:-}"
    printf 'DX_OP_CACHE_REFRESHED_AT=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  } > "$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$stamp_file"
}

main() {
  dx_auth_load_op_service_account_token >/dev/null
  dx_auth_refresh_agent_item_cache >/dev/null
  agent_coordination_refresh_transport_cache >/dev/null
  write_stamp

  printf 'refreshed auth cache: %s\n' "$(dx_auth_agent_item_cache_file)"
  printf 'refreshed alerts cache: %s\n' "$(agent_coordination_cache_file)"
  printf 'wrote stamp: %s\n' "$(dx_op_cache_stamp_file)"
}

main "$@"
