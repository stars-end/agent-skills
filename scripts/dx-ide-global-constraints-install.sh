#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
dx-ide-global-constraints-install.sh

Installs the DX "global constraints rail" into IDE-global instruction files by symlinking:
  ~/agent-skills/dist/dx-global-constraints.md

Targets (per-user):
  ~/.codex/AGENTS.md
  ~/.claude/CLAUDE.md
  ~/.gemini/GEMINI.md
  ~/.config/opencode/AGENTS.md

Usage:
  dx-ide-global-constraints-install.sh --check
  dx-ide-global-constraints-install.sh --apply
  dx-ide-global-constraints-install.sh --apply --force

Notes:
  - Default source is: $HOME/agent-skills/dist/dx-global-constraints.md
  - Set DX_GLOBAL_CONSTRAINTS_SOURCE to override the source file.
  - This script is intentionally small and deterministic.
EOF
}

MODE="check"
FORCE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --force) FORCE="1" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

SOURCE="${DX_GLOBAL_CONSTRAINTS_SOURCE:-$HOME/agent-skills/dist/dx-global-constraints.md}"
if [[ ! -f "$SOURCE" ]]; then
  echo "❌ Missing source rail: $SOURCE" >&2
  echo "   Fix: cd ~/agent-skills && git pull origin master" >&2
  exit 1
fi

declare -a TARGETS=(
  "$HOME/.codex/AGENTS.md"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.gemini/GEMINI.md"
  "$HOME/.config/opencode/AGENTS.md"
)

fail=0

check_target() {
  local target="$1"
  local parent
  parent="$(dirname "$target")"

  if [[ ! -e "$target" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p "$parent"
      ln -s "$SOURCE" "$target"
      echo "✅ linked $target"
      return 0
    fi
    echo "❌ missing $target"
    return 1
  fi

  if [[ -L "$target" ]]; then
    local dest
    dest="$(readlink "$target")"
    if [[ "$dest" == "$SOURCE" ]]; then
      echo "✅ ok $target"
      return 0
    fi
    if [[ "$MODE" == "apply" ]]; then
      if [[ "$FORCE" == "1" ]]; then
        ln -sf "$SOURCE" "$target"
        echo "✅ relinked $target"
        return 0
      fi
      echo "❌ $target points elsewhere: $dest (use --force to relink)"
      return 1
    fi
    echo "❌ $target points elsewhere: $dest"
    return 1
  fi

  # Not a symlink
  if [[ "$MODE" == "apply" ]]; then
    if [[ "$FORCE" == "1" ]]; then
      mkdir -p "$parent"
      ln -sf "$SOURCE" "$target"
      echo "✅ replaced $target with symlink"
      return 0
    fi
    echo "❌ $target exists and is not a symlink (use --force to replace)"
    return 1
  fi

  echo "❌ $target exists and is not a symlink"
  return 1
}

echo "DX global rail source: $SOURCE"
for target in "${TARGETS[@]}"; do
  if ! check_target "$target"; then
    fail=1
  fi
done

if [[ $fail -eq 0 ]]; then
  echo "✅ DONE ($MODE)"
  exit 0
fi
echo "❌ FAILED ($MODE)"
exit 1

