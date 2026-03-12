#!/usr/bin/env bash

# Shared auth helpers for non-interactive OP + Railway workflows.

dx_auth_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

dx_auth_op_token_valid() {
  local token="${1:-}"
  [[ -n "$token" ]] || return 1
  OP_SERVICE_ACCOUNT_TOKEN="$token" op whoami >/dev/null 2>&1
}

dx_auth_secret_cache_dir() {
  printf '%s\n' "${DX_AUTH_SECRET_CACHE_DIR:-$HOME/.cache/dx/op-secrets}"
}

dx_auth_secret_cache_ttl_seconds() {
  printf '%s\n' "${DX_AUTH_SECRET_CACHE_TTL_SECONDS:-86400}"
}

dx_auth_secret_cache_ensure_dir() {
  local cache_dir
  cache_dir="$(dx_auth_secret_cache_dir)"
  mkdir -p "$cache_dir"
  chmod 700 "$cache_dir" 2>/dev/null || true
}

dx_auth_file_mtime_epoch() {
  local file_path="${1:-}"
  [[ -n "$file_path" && -e "$file_path" ]] || {
    printf '0\n'
    return 0
  }

  perl -e 'my @s = stat($ARGV[0]); print defined($s[9]) ? int($s[9]) : 0; exit 0' "$file_path" 2>/dev/null || printf '0\n'
}

dx_auth_secret_cache_fresh() {
  local cache_file="${1:-}"
  local ttl now mtime age
  [[ -f "$cache_file" ]] || return 1

  ttl="$(dx_auth_secret_cache_ttl_seconds)"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=86400
  now="$(date +%s)"
  mtime="$(dx_auth_file_mtime_epoch "$cache_file")"
  age=$((now - mtime))
  [[ "$age" -le "$ttl" ]]
}

dx_auth_secret_cache_file() {
  local cache_key="${1:-}"
  [[ -n "$cache_key" ]] || return 1
  printf '%s/%s' "$(dx_auth_secret_cache_dir)" "$cache_key"
}

dx_auth_secret_cache_lock_dir() {
  local cache_key="${1:-}"
  printf '%s.lock' "$(dx_auth_secret_cache_file "$cache_key")"
}

dx_auth_agent_item_cache_file() {
  dx_auth_secret_cache_file "agent_secrets_production.json"
}

dx_auth_agent_secret_field_for_ref() {
  local ref="${1:-}"
  case "$ref" in
    op://*/Agent-Secrets-Production/*)
      printf '%s\n' "${ref##*/Agent-Secrets-Production/}"
      ;;
    *)
      return 1
      ;;
  esac
}

dx_auth_read_field_from_item_cache() {
  local cache_file="${1:-}"
  local field_name="${2:-}"
  [[ -f "$cache_file" && -n "$field_name" ]] || return 1
  dx_auth_has_cmd python3 || return 1

  python3 - "$cache_file" "$field_name" <<'PY'
import json
import sys

path, field_name = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
for field in data.get("fields") or []:
    if field.get("label") == field_name and isinstance(field.get("value"), str):
        print(field["value"], end="")
        sys.exit(0)
sys.exit(1)
PY
}

dx_auth_refresh_agent_item_cache() {
  local cache_file lock_dir tmp_file item_json
  cache_file="$(dx_auth_agent_item_cache_file)" || return 1
  lock_dir="${cache_file}.lock"

  dx_auth_secret_cache_ensure_dir

  if ! mkdir "$lock_dir" >/dev/null 2>&1; then
    local attempt
    for attempt in 1 2 3; do
      sleep 1
      if dx_auth_secret_cache_fresh "$cache_file"; then
        return 0
      fi
    done
    [[ -f "$cache_file" ]] && return 0
    return 1
  fi

  tmp_file="$(mktemp "${cache_file}.tmp.XXXXXX")"

  dx_auth_load_op_service_account_token >/dev/null 2>&1 || {
    rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
    return 1
  }

  item_json="$(op item get "Agent-Secrets-Production" --vault dev --format json 2>/dev/null || true)"
  if [[ -z "$item_json" ]]; then
    rm -rf "$lock_dir" "$tmp_file" >/dev/null 2>&1 || true
    [[ -f "$cache_file" ]] && return 0
    return 1
  fi

  printf '%s' "$item_json" > "$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$cache_file"
  rm -rf "$lock_dir" >/dev/null 2>&1 || true
  return 0
}

dx_auth_secret_cache_key_for_ref() {
  local ref="${1:-}"
  local key="${2:-}"
  if [[ -n "$key" ]]; then
    printf '%s\n' "$key"
    return 0
  fi

  case "$ref" in
    *"/RAILWAY_API_TOKEN")
      printf 'railway_api_token\n'
      ;;
    *"/GITHUB_TOKEN")
      printf 'github_token\n'
      ;;
    *"/ZAI_API_KEY")
      printf 'zai_api_key\n'
      ;;
    *)
      printf '%s\n' "$ref" | tr '/:.' '_' | tr -cd '[:alnum:]_-'
      ;;
  esac
}

dx_auth_read_secret_cached() {
  local ref="${1:-}"
  local cache_key="${2:-}"
  local cache_file secret field_name lock_dir tmp_file
  [[ -n "$ref" ]] || return 1

  field_name="$(dx_auth_agent_secret_field_for_ref "$ref" || true)"
  if [[ -n "$field_name" ]]; then
    cache_file="$(dx_auth_agent_item_cache_file)" || return 1
    if dx_auth_secret_cache_fresh "$cache_file"; then
      dx_auth_read_field_from_item_cache "$cache_file" "$field_name"
      return $?
    fi
    dx_auth_refresh_agent_item_cache || true
    if [[ -f "$cache_file" ]]; then
      dx_auth_read_field_from_item_cache "$cache_file" "$field_name"
      return $?
    fi
    return 1
  fi

  cache_key="$(dx_auth_secret_cache_key_for_ref "$ref" "$cache_key")"
  cache_file="$(dx_auth_secret_cache_file "$cache_key")" || return 1

  if dx_auth_secret_cache_fresh "$cache_file"; then
    cat "$cache_file"
    return 0
  fi

  dx_auth_secret_cache_ensure_dir
  lock_dir="$(dx_auth_secret_cache_lock_dir "$cache_key")"
  if ! mkdir "$lock_dir" >/dev/null 2>&1; then
    local attempt
    for attempt in 1 2 3; do
      sleep 1
      if dx_auth_secret_cache_fresh "$cache_file"; then
        cat "$cache_file"
        return 0
      fi
    done
    [[ -f "$cache_file" ]] && cat "$cache_file"
    [[ -f "$cache_file" ]]
    return $?
  fi

  if ! dx_auth_load_op_service_account_token; then
    rm -rf "$lock_dir" >/dev/null 2>&1 || true
    [[ -f "$cache_file" ]] && cat "$cache_file"
    [[ -f "$cache_file" ]]
    return $?
  fi

  secret="$(op read "$ref" 2>/dev/null || true)"
  if [[ -z "$secret" ]]; then
    rm -rf "$lock_dir" >/dev/null 2>&1 || true
    [[ -f "$cache_file" ]] && cat "$cache_file"
    [[ -f "$cache_file" ]]
    return $?
  fi

  tmp_file="$(mktemp "${cache_file}.tmp.XXXXXX")"
  printf '%s' "$secret" > "$tmp_file"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$cache_file"
  rm -rf "$lock_dir" >/dev/null 2>&1 || true
  printf '%s' "$secret"
}

dx_auth_load_op_service_account_token() {
  dx_auth_has_cmd op || return 1

  if [[ "${DX_AUTH_OP_TOKEN_VERIFIED:-0}" == "1" && -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && dx_auth_op_token_valid "${OP_SERVICE_ACCOUNT_TOKEN}"; then
    export DX_AUTH_OP_TOKEN_VERIFIED=1
    return 0
  fi

  local host_short host_full explicit_file candidate token decrypted
  host_short="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
  host_full="$(hostname 2>/dev/null || printf '%s' "$host_short")"
  explicit_file="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-}"

  if [[ -n "$explicit_file" && -r "$explicit_file" ]]; then
    token="$(cat "$explicit_file" 2>/dev/null || true)"
    if dx_auth_op_token_valid "$token"; then
      export OP_SERVICE_ACCOUNT_TOKEN="$token"
      export DX_AUTH_OP_TOKEN_VERIFIED=1
      return 0
    fi
  fi

  local -a plain_candidates=(
    "${HOME}/.config/systemd/user/op-${host_short}-token"
    "${HOME}/.config/systemd/user/op-${host_full}-token"
    "${HOME}/.config/systemd/user/op-${CANONICAL_HOST_KEY:-}-token"
    "${HOME}/.config/systemd/user/op_token"
    "${HOME}/.config/systemd/user/op-macmini-token"
    "${HOME}/.config/systemd/user/op-homedesktop-wsl-token"
    "${HOME}/.config/systemd/user/op-epyc6-token"
    "${HOME}/.config/systemd/user/op-epyc12-token"
  )

  for candidate in "${plain_candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      token="$(cat "$candidate" 2>/dev/null || true)"
      if dx_auth_op_token_valid "$token"; then
        export OP_SERVICE_ACCOUNT_TOKEN="$token"
        export DX_AUTH_OP_TOKEN_VERIFIED=1
        return 0
      fi
    fi
  done

  dx_auth_has_cmd systemd-creds || return 1

  local -a cred_candidates=(
    "${HOME}/.config/systemd/user/op-${host_short}-token.cred"
    "${HOME}/.config/systemd/user/op-${host_full}-token.cred"
    "${HOME}/.config/systemd/user/op-${CANONICAL_HOST_KEY:-}-token.cred"
    "${HOME}/.config/systemd/user/op_token.cred"
    "${HOME}/.config/systemd/user/op-macmini-token.cred"
    "${HOME}/.config/systemd/user/op-homedesktop-wsl-token.cred"
    "${HOME}/.config/systemd/user/op-epyc6-token.cred"
    "${HOME}/.config/systemd/user/op-epyc12-token.cred"
  )

  for candidate in "${cred_candidates[@]}"; do
    if [[ -r "$candidate" ]]; then
      decrypted="$(systemd-creds decrypt "$candidate" 2>/dev/null || true)"
      if dx_auth_op_token_valid "$decrypted"; then
        export OP_SERVICE_ACCOUNT_TOKEN="$decrypted"
        export DX_AUTH_OP_TOKEN_VERIFIED=1
        return 0
      fi
    fi
  done

  return 1
}

dx_auth_load_railway_api_token() {
  dx_auth_has_cmd railway || return 1

  if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
    return 0
  fi

  local token
  token="$(dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" "railway_api_token" || true)"
  [[ -n "$token" ]] || return 1

  export RAILWAY_API_TOKEN="$token"
  return 0
}

dx_auth_load_github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    return 0
  fi

  local token
  token="$(dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/GITHUB_TOKEN" "github_token" || true)"
  [[ -n "$token" ]] || return 1

  export GH_TOKEN="$token"
  return 0
}

dx_auth_load_zai_api_key() {
  if [[ -n "${ZAI_API_KEY:-}" && "${ZAI_API_KEY}" != op://* ]]; then
    return 0
  fi

  local ref="${ZAI_API_KEY:-op://dev/Agent-Secrets-Production/ZAI_API_KEY}"
  local token
  token="$(dx_auth_read_secret_cached "$ref" "zai_api_key" || true)"
  [[ -n "$token" ]] || return 1

  export ZAI_API_KEY="$token"
  return 0
}
