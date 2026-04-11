#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"

json=0
if [[ "${1:-}" == "--json" ]]; then
  json=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage:
  dx-op-auth-status.sh [--json]

Classifies local 1Password readiness without printing secrets.

Modes:
  agent_ready_cache            synced cache can satisfy agent secrets
  agent_ready_service_account  service-account auth can refresh/read secrets
  human_interactive_only       GUI-backed op works, but agents should not rely on it
  blocked                     no agent-safe auth path is available
EOF
  exit 0
fi

op_cli=fail
gui_op=fail
service_account=fail
cache=fail
mode=blocked

if command -v op >/dev/null 2>&1; then
  op_cli=pass
fi

if [[ "$op_cli" == "pass" ]]; then
  if env -u OP_SERVICE_ACCOUNT_TOKEN -u OP_SESSION op whoami >/dev/null 2>&1; then
    gui_op=pass
  fi

  if dx_auth_load_op_service_account_token >/dev/null 2>&1; then
    service_account=pass
  fi
fi

if DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" "railway_api_token" >/dev/null 2>&1; then
  cache=pass
fi

if [[ "$cache" == "pass" ]]; then
  mode=agent_ready_cache
elif [[ "$service_account" == "pass" ]]; then
  mode=agent_ready_service_account
elif [[ "$gui_op" == "pass" ]]; then
  mode=human_interactive_only
fi

if [[ "$json" == "1" ]]; then
  printf '{"mode":"%s","op_cli":"%s","cache":"%s","service_account":"%s","gui_op":"%s"}\n' \
    "$mode" "$op_cli" "$cache" "$service_account" "$gui_op"
else
  printf 'mode: %s\n' "$mode"
  printf 'op_cli: %s\n' "$op_cli"
  printf 'cache: %s\n' "$cache"
  printf 'service_account: %s\n' "$service_account"
  printf 'gui_op: %s\n' "$gui_op"
fi

case "$mode" in
  agent_ready_cache|agent_ready_service_account)
    exit 0
    ;;
  human_interactive_only)
    exit 2
    ;;
  *)
    exit 1
    ;;
esac
