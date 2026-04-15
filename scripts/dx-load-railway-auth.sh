#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"

usage() {
  cat <<'EOF'
Usage:
  dx-load-railway-auth.sh --check
  dx-load-railway-auth.sh -- <command> [args...]

Behavior:
  - loads OP_SERVICE_ACCOUNT_TOKEN when a canonical unattended token is available
  - loads RAILWAY_API_TOKEN from the synced cache or 1Password in the same invocation
  - executes the requested command with resolved variables exported

Policy:
  - macOS GUI-backed op is for human bootstrap only
  - agent/cron paths should succeed from cache or service-account auth
  - use dx-op-auth-status.sh to distinguish GUI, cache, and service-account modes
EOF
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --check)
    op_service_loaded=0
    if dx_auth_load_op_service_account_token >/dev/null 2>&1; then
      op_service_loaded=1
    else
      unset OP_SERVICE_ACCOUNT_TOKEN DX_AUTH_OP_TOKEN_VERIFIED
    fi
    dx_auth_load_railway_api_token
    if [[ "$op_service_loaded" == "1" ]]; then
      if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && dx_auth_op_token_valid "$OP_SERVICE_ACCOUNT_TOKEN"; then
        echo "OP: service-account-token verified"
      else
        echo "OP: service-account-token invalid" >&2
        exit 1
      fi
    else
      echo "OP: cache-only/no-service-account-token"
    fi
    railway whoami
    exit 0
    ;;
  --)
    shift
    ;;
esac

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

if ! dx_auth_load_op_service_account_token >/dev/null 2>&1; then
  unset OP_SERVICE_ACCOUNT_TOKEN DX_AUTH_OP_TOKEN_VERIFIED
fi

dx_auth_load_railway_api_token || {
  echo "BLOCKED: missing_railway_api_token" >&2
  echo "NEEDS: synced OP cache with RAILWAY_API_TOKEN or service-account refresh access" >&2
  echo "CHECK: ~/agent-skills/scripts/dx-op-auth-status.sh --json" >&2
  exit 1
}

exec "$@"
