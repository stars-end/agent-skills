#!/usr/bin/env bash
set -euo pipefail

# Fast, git-command-free canonical repo detection.
#
# Returns:
#   0 if current working directory is within a canonical clone root (BLOCK)
#   1 otherwise
#
# Notes:
# - Uses `pwd -P` to avoid symlink bypass.
# - Intentionally blocks unconditionally inside canonical roots (submodules included).
# - Workspaces are expected under /tmp/agents/* and should never be inside canonical roots.

_dx_is_canonical_cwd_fast() {
  local real_path
  real_path="$(pwd -P)"

  local canonical_root
  for canonical_root in ~/agent-skills ~/prime-radiant-ai ~/affordabot ~/llm-common; do
    canonical_root="${canonical_root/#\~/$HOME}"
    case "$real_path" in
      "$canonical_root"|"$canonical_root"/*)
        return 0
        ;;
    esac
  done

  return 1
}

