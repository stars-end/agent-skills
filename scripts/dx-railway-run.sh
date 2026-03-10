#!/usr/bin/env bash
# dx-railway-run.sh
# Run commands with Railway context from a worktree without requiring local `railway link`.
#
# Usage:
#   dx-railway-run.sh -- <command> [args...]
#   dx-railway-run.sh --env dev --service backend -- <command> [args...]

set -euo pipefail

ENV_NAME="${DX_RAILWAY_ENV:-dev}"
SERVICE_NAME="${DX_RAILWAY_SERVICE:-backend}"
PROJECT_ID="${DX_RAILWAY_PROJECT_ID:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"

resolve_context_file() {
  local explicit local_file worktree_base context_base cwd rel beads_id repo_name candidate
  local worktree_base_real

  explicit="${DX_RAILWAY_CONTEXT_FILE:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  worktree_base="${DX_WORKTREE_BASE:-/tmp/agents}"
  context_base="${DX_WORKTREE_CONTEXT_BASE:-$worktree_base/.dx-context}"
  cwd="$(pwd -P)"
  worktree_base_real="$(cd "$worktree_base" 2>/dev/null && pwd -P || true)"

  # Resolve <worktree-base>/<beads-id>/<repo>/... to external context store.
  if [[ "$cwd" == "$worktree_base/"* ]]; then
    rel="${cwd#"$worktree_base/"}"
  elif [[ -n "$worktree_base_real" && "$cwd" == "$worktree_base_real/"* ]]; then
    rel="${cwd#"$worktree_base_real/"}"
  else
    rel=""
  fi

  if [[ -n "$rel" ]]; then
    if [[ "$rel" == */* ]]; then
      beads_id="${rel%%/*}"
      rel="${rel#*/}"
      repo_name="${rel%%/*}"
    fi
    if [[ -n "${beads_id:-}" && -n "${repo_name:-}" ]]; then
      candidate="$context_base/$beads_id/$repo_name/railway-context.env"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

  local_file=".dx/railway-context.env"
  if [[ -f "$local_file" ]]; then
    printf '%s\n' "$local_file"
    return 0
  fi

  printf '%s\n' "$local_file"
}

CONTEXT_FILE="$(resolve_context_file)"

die() {
  echo "dx-railway-run: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_NAME="${2:-}"
      shift 2
      ;;
    --service)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --context-file)
      CONTEXT_FILE="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown option: $1 (use -- to separate command)"
      ;;
  esac
done

[[ $# -gt 0 ]] || die "missing command. Example: dx-railway-run.sh -- make dev"
command -v railway >/dev/null 2>&1 || die "railway CLI not found in PATH"

# If already inside Railway shell context, just run directly.
if [[ -n "${RAILWAY_ENVIRONMENT:-}" ]]; then
  exec "$@"
fi

if [[ -z "${RAILWAY_API_TOKEN:-}" ]]; then
  dx_auth_load_railway_api_token >/dev/null 2>&1 || true
fi

# Use active local link if present.
if railway status >/dev/null 2>&1; then
  exec railway run -- "$@"
fi

if [[ -f "$CONTEXT_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONTEXT_FILE"
fi

PROJECT_ID="${PROJECT_ID:-${RAILWAY_PROJECT_ID:-}}"
ENV_NAME="${ENV_NAME:-${RAILWAY_ENVIRONMENT:-dev}}"
SERVICE_NAME="${SERVICE_NAME:-${RAILWAY_SERVICE:-backend}}"

if [[ -z "$PROJECT_ID" ]]; then
  die "missing Railway project id. Run dx-worktree create again, or set DX_RAILWAY_PROJECT_ID / RAILWAY_PROJECT_ID."
fi

if [[ -n "$SERVICE_NAME" ]]; then
  exec railway run -p "$PROJECT_ID" -e "$ENV_NAME" -s "$SERVICE_NAME" -- "$@"
fi
exec railway run -p "$PROJECT_ID" -e "$ENV_NAME" -- "$@"
