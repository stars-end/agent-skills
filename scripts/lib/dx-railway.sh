#!/usr/bin/env bash

# dx-railway.sh — Shared Railway execution helpers for worktree-safe non-interactive use.
#
# Canonical contract surface for downstream repos:
#   dx_railway_resolve_context_file   — find railway-context.env from worktree or cwd
#   dx_railway_normalize_auth         — ensure RAILWAY_API_TOKEN is exported
#   dx_railway_exec                   — run a command via `railway run -p/-e/-s`
#
# Source this file after dx-auth.sh:
#   source "$SCRIPT_DIR/lib/dx-auth.sh"
#   source "$SCRIPT_DIR/lib/dx-railway.sh"

dx_railway_resolve_context_file() {
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

dx_railway_normalize_auth() {
  if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ -n "${RAILWAY_TOKEN:-}" ]]; then
    export RAILWAY_API_TOKEN="$RAILWAY_TOKEN"
    return 0
  fi

  dx_auth_load_railway_api_token >/dev/null 2>&1 || true

  if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
    return 0
  fi

  return 1
}

dx_railway_exec() {
  local project_id="$1"
  local env_name="$2"
  local service_name="${3:-}"
  shift 3

  if [[ -n "$project_id" ]]; then
    if [[ -n "$service_name" ]]; then
      railway run -p "$project_id" -e "$env_name" -s "$service_name" -- "$@"
    else
      railway run -p "$project_id" -e "$env_name" -- "$@"
    fi
    return $?
  fi

  if railway status >/dev/null 2>&1; then
    if [[ -n "$service_name" ]]; then
      railway run -s "$service_name" -- "$@"
    else
      railway run -- "$@"
    fi
    return $?
  fi

  return 1
}
