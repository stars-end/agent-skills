#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
dx-agents-skills-install.sh

Populate $HOME/.agents/skills/ with symlinks to skills from ~/agent-skills so
Codex (and any agent that follows the .agents/skills convention) can discover them.

Usage:
  dx-agents-skills-install.sh --check
  dx-agents-skills-install.sh --apply
  dx-agents-skills-install.sh --apply --force

Notes:
  - This script only links; it does not copy secrets or modify other dotfiles.
  - Skills are sourced from: ~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md
  - Symlinks are supported by Codex skill discovery.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEST_DIR="${DEST_DIR:-$HOME/.agents/skills}"
declare -a CATEGORIES=( core extended health infra railway dispatch )

extract_name() {
  local skill_md="$1"
  local name
  name="$(grep -E '^name:' "$skill_md" | head -n 1 | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  echo "$name"
}

link_one() {
  local name="$1"
  local src_dir="$2"
  local target="$DEST_DIR/$name"

  if [[ ! -e "$target" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      ln -s "$src_dir" "$target"
      echo "✅ linked $target -> $src_dir"
      return 0
    fi
    echo "❌ missing $target"
    return 1
  fi

  if [[ -L "$target" ]]; then
    local dest
    dest="$(readlink "$target")"
    if [[ "$dest" == "$src_dir" ]]; then
      echo "✅ ok $target"
      return 0
    fi
    if [[ "$MODE" == "apply" ]]; then
      if [[ "$FORCE" == "1" ]]; then
        ln -sfn "$src_dir" "$target"
        echo "✅ relinked $target -> $src_dir"
        return 0
      fi
      echo "⚠️  $target points elsewhere: $dest (use --force to relink)"
      return 1
    fi
    echo "❌ $target points elsewhere: $dest"
    return 1
  fi

  # Not a symlink.
  if [[ "$MODE" == "apply" ]]; then
    if [[ "$FORCE" == "1" ]]; then
      rm -rf "$target"
      ln -s "$src_dir" "$target"
      echo "✅ replaced $target with link -> $src_dir"
      return 0
    fi
    echo "⚠️  $target exists and is not a symlink (use --force to replace)"
    return 1
  fi
  echo "❌ $target exists and is not a symlink"
  return 1
}

if [[ "$MODE" == "apply" ]]; then
  mkdir -p "$DEST_DIR"
fi

echo "Agents skills dir: $DEST_DIR"
echo "Source repo: $REPO_ROOT"

fail=0
count=0

for cat in "${CATEGORIES[@]}"; do
  base="$REPO_ROOT/$cat"
  [[ -d "$base" ]] || continue

  while IFS= read -r skill_md; do
    name="$(extract_name "$skill_md")"
    [[ -n "$name" ]] || continue
    src_dir="$(cd "$(dirname "$skill_md")" && pwd)"
    count=$((count + 1))
    if ! link_one "$name" "$src_dir"; then
      fail=1
    fi
  done < <(find "$base" -maxdepth 2 -name "SKILL.md" | sort)
done

echo ""
echo "Skills scanned: $count"

if [[ $fail -eq 0 ]]; then
  echo "✅ DONE ($MODE)"
  exit 0
fi
echo "❌ FAILED ($MODE)"
exit 1

