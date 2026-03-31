#!/usr/bin/env bash
#
# tldr-contained.sh
#
# Containment wrapper for llm-tldr that redirects all runtime state
# (.tldr/ and .tldrignore) outside the project tree via symlinks.
#
# Usage:
#   tldr-contained warm <path>
#   tldr-contained semantic <query> <path>
#   tldr-contained structure <path> --lang python
#   tldr-contained context <entry> --project <path>
#
# MCP mode (no arguments or --project flag):
#   The MCP server (tldr-mcp) receives --project per call, so the
#   containment happens inside the server. Point your MCP config at
#   this wrapper instead of tldr-mcp directly.
#
# State location:
#   $TLDR_STATE_HOME/<project-hash>/
#   Default: ~/.cache/tldr-state/
#
set -euo pipefail

TLDR_STATE_HOME="${TLDR_STATE_HOME:-${HOME}/.cache/tldr-state}"

_resolve_project_root() {
  local target
  target="$(cd "$(dirname "${BASH_SOURCE[1]:-$1}")" 2>/dev/null && pwd)"

  while [[ "$target" != "/" ]]; do
    if [[ -d "$target/.git" ]]; then
      echo "$target"
      return 0
    fi
    if [[ -f "$target/pyproject.toml" ]] || [[ -f "$target/package.json" ]] || \
       [[ -f "$target/Cargo.toml" ]] || [[ -f "$target/go.mod" ]] || \
       [[ -d "$target/.tldr" ]]; then
      echo "$target"
      return 0
    fi
    target="$(dirname "$target")"
  done

  return 1
}

_setup_symlinks() {
  local project_root="$1"
  local hash
  hash="$(echo "$project_root" | md5 | cut -d' ' -f1)"

  local state_dir="${TLDR_STATE_HOME}/${hash}"
  local tldr_target="${state_dir}/.tldr"
  local tldrignore_target="${state_dir}/.tldrignore"

  mkdir -p "$tldr_target"

  local project_tldr="${project_root}/.tldr"
  local project_tldrignore="${project_root}/.tldrignore"

  if [[ -L "$project_tldr" ]]; then
    if [[ "$(readlink "$project_tldr")" != "$tldr_target" ]]; then
      rm -f "$project_tldr"
      ln -s "$tldr_target" "$project_tldr"
    fi
  elif [[ -e "$project_tldr" ]]; then
    if [[ -d "$project_tldr" ]]; then
      mv "$project_tldr" "$tldr_target" 2>/dev/null || rm -rf "$project_tldr"
    else
      rm -f "$project_tldr"
    fi
    ln -s "$tldr_target" "$project_tldr"
  else
    ln -s "$tldr_target" "$project_tldr"
  fi

  if [[ -L "$project_tldrignore" ]]; then
    if [[ "$(readlink "$project_tldrignore")" != "$tldrignore_target" ]]; then
      rm -f "$project_tldrignore"
      ln -s "$tldrignore_target" "$project_tldrignore"
    fi
  elif [[ -e "$project_tldrignore" ]]; then
    mv "$project_tldrignore" "$tldrignore_target" 2>/dev/null || true
    ln -s "$tldrignore_target" "$project_tldrignore"
  else
    ln -s "$tldrignore_target" "$project_tldrignore"
  fi
}

_detect_project_from_args() {
  local i=0
  local args=("$@")
  while [[ $i -lt ${#args[@]} ]]; do
    local arg="${args[$i]}"
    if [[ "$arg" == --project ]] && [[ $((i + 1)) -lt ${#args[@]} ]]; then
      local val="${args[$((i + 1))]}"
      if [[ -d "$val" ]]; then
        local resolved
        resolved="$(cd "$val" 2>/dev/null && pwd)" || true
        if [[ -n "$resolved" ]]; then
          echo "$resolved"
          return 0
        fi
      fi
    elif [[ "${arg:0:1}" != "-" ]] && [[ -d "$arg" ]]; then
      local resolved
      resolved="$(cd "$arg" 2>/dev/null && pwd)" || true
      if [[ -n "$resolved" ]]; then
        echo "$resolved"
        return 0
      fi
    fi
    ((i++))
  done
  return 1
}

_subcommand="$1"
shift 2>/dev/null || true

if [[ -z "${_subcommand:-}" ]] || [[ "${_subcommand:-}" == "help" ]] || [[ "${_subcommand:-}" == "--help" ]] || [[ "${_subcommand:-}" == "-h" ]]; then
  exec llm-tldr "$_subcommand" "$@"
fi

project_root=""

case "$_subcommand" in
  warm|semantic|tree|structure|calls|cfg|dfg|slice|dead|arch|context|impact|search|change_impact|diagnostics|extract|imports|importers)
    project_root="$(_detect_project_from_args "$@")" || true
    if [[ -z "$project_root" ]]; then
      project_root="$(_resolve_project_root "$0")" || true
    fi
    ;;
  mcp|serve|daemon)
    project_root="$(_resolve_project_root "$0")" || true
    ;;
  *)
    project_root="$(_detect_project_from_args "$@")" || true
    if [[ -z "$project_root" ]]; then
      project_root="$(_resolve_project_root "$0")" || true
    fi
    ;;
esac

if [[ -n "$project_root" && -d "$project_root" ]]; then
  _setup_symlinks "$project_root"
fi

exec llm-tldr "$_subcommand" "$@"
