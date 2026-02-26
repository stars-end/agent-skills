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
CONTEXT_FILE="${DX_RAILWAY_CONTEXT_FILE:-.dx/railway-context.env}"

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
