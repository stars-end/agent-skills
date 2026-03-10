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

dx_auth_load_op_service_account_token() {
  dx_auth_has_cmd op || return 1

  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && dx_auth_op_token_valid "${OP_SERVICE_ACCOUNT_TOKEN}"; then
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

  dx_auth_load_op_service_account_token || return 1

  local token
  token="$(op read "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" 2>/dev/null || true)"
  [[ -n "$token" ]] || return 1

  export RAILWAY_API_TOKEN="$token"
  return 0
}
