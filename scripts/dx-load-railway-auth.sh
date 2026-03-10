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
  - loads OP_SERVICE_ACCOUNT_TOKEN using canonical fallback paths
  - loads RAILWAY_API_TOKEN from 1Password in the same invocation
  - executes the requested command with both variables exported
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
    dx_auth_load_op_service_account_token
    dx_auth_load_railway_api_token
    op whoami
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

dx_auth_load_op_service_account_token || {
  echo "BLOCKED: missing_op_service_account_token" >&2
  echo "NEEDS: readable OP service-account credential file or OP_SERVICE_ACCOUNT_TOKEN_FILE" >&2
  exit 1
}

dx_auth_load_railway_api_token || {
  echo "BLOCKED: missing_railway_api_token" >&2
  echo "NEEDS: op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN access in same shell invocation" >&2
  exit 1
}

exec "$@"
