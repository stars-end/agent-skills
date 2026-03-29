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

dx_op_cache_stamp_file() {
  printf '%s\n' "${DX_OP_CACHE_STAMP_FILE:-$HOME/.cache/dx/op-cache-refresh.env}"
}

install_file() {
  local src_file="${1:-}"
  local dest_file="${2:-}"
  [[ -n "$src_file" && -n "$dest_file" ]] || return 1

  mkdir -p "$(dirname "$dest_file")"
  chmod 700 "$(dirname "$dest_file")" 2>/dev/null || true
  install -m 600 "$src_file" "$dest_file"
}

main() {
  local source_ssh source_secret source_alerts source_stamp
  local local_secret local_alerts local_stamp
  local tmp_dir

  source_ssh="${DX_OP_CACHE_SOURCE_SSH:-${CANONICAL_VM_LINUX2:-fengning@epyc12}}"
  source_secret="${DX_OP_CACHE_SOURCE_SECRET_FILE:-~/.cache/dx/op-secrets/agent_secrets_production.json}"
  source_alerts="${DX_OP_CACHE_SOURCE_ALERTS_FILE:-~/.cache/dx/alerts-transport.env}"
  source_stamp="${DX_OP_CACHE_SOURCE_STAMP_FILE:-~/.cache/dx/op-cache-refresh.env}"

  local_secret="$(dx_auth_agent_item_cache_file)"
  local_alerts="$(agent_coordination_cache_file)"
  local_stamp="$(dx_op_cache_stamp_file)"

  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir' >/dev/null 2>&1 || true" EXIT

  scp -q "$source_ssh:$source_secret" "$tmp_dir/agent_secrets_production.json"
  scp -q "$source_ssh:$source_alerts" "$tmp_dir/alerts-transport.env"
  scp -q "$source_ssh:$source_stamp" "$tmp_dir/op-cache-refresh.env"

  install_file "$tmp_dir/agent_secrets_production.json" "$local_secret"
  install_file "$tmp_dir/alerts-transport.env" "$local_alerts"
  install_file "$tmp_dir/op-cache-refresh.env" "$local_stamp"

  printf 'synced auth cache from %s -> %s\n' "$source_ssh" "$local_secret"
  printf 'synced alerts cache from %s -> %s\n' "$source_ssh" "$local_alerts"
  printf 'synced stamp from %s -> %s\n' "$source_ssh" "$local_stamp"
}

main "$@"
