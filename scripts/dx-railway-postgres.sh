#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-auth.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-railway.sh"

ENV_NAME="${DX_RAILWAY_ENV:-dev}"
PROJECT_ID="${DX_RAILWAY_PROJECT_ID:-}"
BACKEND_SERVICE="${DX_RAILWAY_BACKEND_SERVICE:-backend}"
POSTGRES_SERVICE="${DX_RAILWAY_POSTGRES_SERVICE:-Postgres}"
REPO_ROOT="$(pwd -P)"
CONTEXT_FILE="$(dx_railway_resolve_context_file)"

usage() {
  cat <<'USAGE'
Usage:
  dx-railway-postgres.sh [global options] <mode> [mode args]

Modes:
  query --sql '<sql>'
  query --file <sql-file>
  psql
  backend-python -- <command> [args...]
  alembic-upgrade [revision]

Global options:
  --project-id <id>         Railway project id
  --env <name>              Railway environment (default: dev)
  --backend-service <name>  Backend/app service name (default: backend)
  --postgres-service <name> Postgres service name (default: Postgres)
  --context-file <path>     Explicit Railway context env file
  --repo-root <path>        Repo root for backend-python/alembic-upgrade
  --help                    Show this help

Notes:
  - Canonical automation token is RAILWAY_API_TOKEN.
  - RAILWAY_TOKEN is accepted only as a compatibility fallback.
  - Prefer explicit --project-id/--env/--service inputs or a seeded worktree context.
USAGE
}

die() {
  echo "dx-railway-postgres: $*" >&2
  exit 2
}

blocked() {
  local reason="$1"
  local needs="$2"
  echo "BLOCKED: ${reason}" >&2
  echo "NEEDS: ${needs}" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --env)
      ENV_NAME="${2:-}"
      shift 2
      ;;
    --backend-service)
      BACKEND_SERVICE="${2:-}"
      shift 2
      ;;
    --postgres-service)
      POSTGRES_SERVICE="${2:-}"
      shift 2
      ;;
    --context-file)
      CONTEXT_FILE="${2:-}"
      shift 2
      ;;
    --repo-root)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    query|psql|backend-python|alembic-upgrade)
      break
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

MODE="$1"
shift

if [[ -f "$CONTEXT_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONTEXT_FILE"
fi

PROJECT_ID="${PROJECT_ID:-${RAILWAY_PROJECT_ID:-}}"
ENV_NAME="${ENV_NAME:-${RAILWAY_ENVIRONMENT:-dev}}"

normalize_auth() {
  if [[ -z "${RAILWAY_API_TOKEN:-}" && -z "${RAILWAY_ENVIRONMENT:-}" ]]; then
    dx_railway_normalize_auth || blocked \
      "missing_railway_api_token" \
      "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN access in the same invocation"
  fi
}

fetch_service_env() {
  local service_name="$1"
  local output_file="$2"

  if ! dx_railway_exec "$PROJECT_ID" "$ENV_NAME" "$service_name" bash -lc 'env' > "$output_file" 2>/dev/null; then
    blocked \
      "missing_railway_context" \
      "explicit --project-id/--env or a seeded worktree Railway context"
  fi
}

get_env_value() {
  local file_path="$1"
  local key="$2"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* ]] || continue
    printf '%s\n' "${line#*=}"
    return 0
  done < "$file_path"

  return 1
}

build_proxy_url() {
  local source_url="$1"
  local proxy_host="$2"
  local proxy_port="$3"
  local mode="$4"

  [[ -n "$source_url" ]] || return 1
  [[ -n "$proxy_host" && -n "$proxy_port" ]] || return 1
  require_cmd python3

  python3 - "$source_url" "$proxy_host" "$proxy_port" "$mode" <<'PY'
import sys
from urllib.parse import quote, urlsplit, urlunsplit

source_url, proxy_host, proxy_port, mode = sys.argv[1:5]
parts = urlsplit(source_url)
scheme = parts.scheme or "postgresql"
if mode == "psql":
    scheme = "postgresql"
userinfo = ""
if parts.username is not None:
    userinfo = quote(parts.username, safe="")
    if parts.password is not None:
        userinfo += ":" + quote(parts.password, safe="")
    userinfo += "@"
netloc = f"{userinfo}{proxy_host}:{proxy_port}"
print(urlunsplit((scheme, netloc, parts.path, parts.query, parts.fragment)), end="")
PY
}

build_proxy_urls() {
  local source_url="$1"
  local proxy_host="$2"
  local proxy_port="$3"
  local runtime_out="$4"
  local psql_out="$5"

  printf -v "$runtime_out" '%s' "$(build_proxy_url "$source_url" "$proxy_host" "$proxy_port" runtime)"
  printf -v "$psql_out" '%s' "$(build_proxy_url "$source_url" "$proxy_host" "$proxy_port" psql)"
}

export_env_file() {
  local file_path="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || continue
    export "$line"
  done < "$file_path"
}

normalize_repo_root() {
  if [[ -d "$REPO_ROOT/backend" ]]; then
    return 0
  fi
  die "repo root '$REPO_ROOT' does not contain backend/"
}

normalize_auth
require_cmd railway

case "$MODE" in
  query)
    require_cmd psql
    SQL_STRING=""
    SQL_FILE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --sql)
          SQL_STRING="${2:-}"
          shift 2
          ;;
        --file)
          SQL_FILE="${2:-}"
          shift 2
          ;;
        *)
          die "query: unknown option $1"
          ;;
      esac
    done
    [[ -n "$SQL_STRING" || -n "$SQL_FILE" ]] || die "query requires --sql or --file"

    tmp_pg_env="$(mktemp)"
    trap 'rm -f "$tmp_pg_env"' EXIT
    fetch_service_env "$POSTGRES_SERVICE" "$tmp_pg_env"
    source_url="$(get_env_value "$tmp_pg_env" DATABASE_URL || true)"
    proxy_host="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_DOMAIN || true)"
    proxy_port="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_PORT || true)"
    [[ -n "$source_url" ]] || blocked "missing_postgres_database_url" "DATABASE_URL from Railway Postgres service env"
    [[ -n "$proxy_host" && -n "$proxy_port" ]] || blocked "missing_postgres_proxy_coordinates" "RAILWAY_TCP_PROXY_DOMAIN and RAILWAY_TCP_PROXY_PORT from Railway Postgres service env"
    build_proxy_urls "$source_url" "$proxy_host" "$proxy_port" RUNTIME_URL PSQL_URL

    if [[ -n "$SQL_STRING" ]]; then
      exec psql "$PSQL_URL" -v ON_ERROR_STOP=1 -c "$SQL_STRING"
    fi
    exec psql "$PSQL_URL" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
    ;;

  psql)
    require_cmd psql
    tmp_pg_env="$(mktemp)"
    trap 'rm -f "$tmp_pg_env"' EXIT
    fetch_service_env "$POSTGRES_SERVICE" "$tmp_pg_env"
    source_url="$(get_env_value "$tmp_pg_env" DATABASE_URL || true)"
    proxy_host="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_DOMAIN || true)"
    proxy_port="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_PORT || true)"
    [[ -n "$source_url" ]] || blocked "missing_postgres_database_url" "DATABASE_URL from Railway Postgres service env"
    [[ -n "$proxy_host" && -n "$proxy_port" ]] || blocked "missing_postgres_proxy_coordinates" "RAILWAY_TCP_PROXY_DOMAIN and RAILWAY_TCP_PROXY_PORT from Railway Postgres service env"
    build_proxy_urls "$source_url" "$proxy_host" "$proxy_port" RUNTIME_URL PSQL_URL
    exec psql "$PSQL_URL"
    ;;

  backend-python)
    [[ $# -gt 0 ]] || die "backend-python requires a command after the mode"
    if [[ "$1" == "--" ]]; then
      shift
    fi
    [[ $# -gt 0 ]] || die "backend-python requires a command after --"
    normalize_repo_root

    tmp_backend_env="$(mktemp)"
    tmp_pg_env="$(mktemp)"
    trap 'rm -f "$tmp_backend_env" "$tmp_pg_env"' EXIT
    fetch_service_env "$BACKEND_SERVICE" "$tmp_backend_env"
    fetch_service_env "$POSTGRES_SERVICE" "$tmp_pg_env"
    source_url="$(get_env_value "$tmp_backend_env" DATABASE_URL || get_env_value "$tmp_pg_env" DATABASE_URL || true)"
    proxy_host="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_DOMAIN || true)"
    proxy_port="$(get_env_value "$tmp_pg_env" RAILWAY_TCP_PROXY_PORT || true)"
    [[ -n "$source_url" ]] || blocked "missing_backend_database_url" "DATABASE_URL from backend or Postgres Railway service env"
    [[ -n "$proxy_host" && -n "$proxy_port" ]] || blocked "missing_postgres_proxy_coordinates" "RAILWAY_TCP_PROXY_DOMAIN and RAILWAY_TCP_PROXY_PORT from Railway Postgres service env"
    build_proxy_urls "$source_url" "$proxy_host" "$proxy_port" RUNTIME_URL PSQL_URL

    (
      export_env_file "$tmp_backend_env"
      export DATABASE_URL="$RUNTIME_URL"
      export RAILWAY_DATABASE_URL="$RUNTIME_URL"
      export APP_DATABASE_URL="$RUNTIME_URL"
      cd "$REPO_ROOT"
      exec "$@"
    )
    ;;

  alembic-upgrade)
    REVISION="${1:-head}"
    normalize_repo_root
    exec "$0" \
      --project-id "$PROJECT_ID" \
      --env "$ENV_NAME" \
      --backend-service "$BACKEND_SERVICE" \
      --postgres-service "$POSTGRES_SERVICE" \
      --context-file "$CONTEXT_FILE" \
      --repo-root "$REPO_ROOT" \
      backend-python -- bash -lc "cd backend && poetry run alembic upgrade ${REVISION}"
    ;;

  *)
    die "unknown mode: $MODE"
    ;;
esac
