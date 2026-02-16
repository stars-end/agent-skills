#!/usr/bin/env bash
set -euo pipefail

# dx-agents-skills-install.sh
#
# Populate $HOME/.agents/skills/ with symlinks to skills from ~/agent-skills so
# Codex (and any agent that follows the .agents/skills convention) can discover them.
#
# IMPORTANT: This script ALWAYS uses the CANONICAL ~/agent-skills path for symlinks,
# never the current working directory. This ensures skills remain accessible even
# when the script is run from a worktree under /tmp/agents/...
#
# Usage:
#   dx-agents-skills-install.sh --check
#   dx-agents-skills-install.sh --apply
#   dx-agents-skills-install.sh --apply --force
#   dx-agents-skills-install.sh --repair  (alias for --apply --force)
#
# Notes:
#   - This script only links; it does not copy secrets or modify other dotfiles.
#   - Skills are sourced from: ~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md
#   - Symlinks are supported by Codex skill discovery.

usage() {
  cat >&2 <<'EOF'
dx-agents-skills-install.sh

Populate $HOME/.agents/skills/ with symlinks to skills from ~/agent-skills.

Usage:
  dx-agents-skills-install.sh --check       # Check current state
  dx-agents-skills-install.sh --apply       # Create missing links
  dx-agents-skills-install.sh --apply --force  # Replace incorrect links
  dx-agents-skills-install.sh --repair      # Alias for --apply --force
  dx-agents-skills-install.sh --doctor      # Check for broken/ephemeral links

Notes:
  - Skills are ALWAYS linked from ~/agent-skills (canonical), never /tmp/agents/
  - Run --doctor to find broken symlinks or links pointing to ephemeral paths
EOF
}

MODE="check"
FORCE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --force) FORCE="1" ;;
    --repair) MODE="apply"; FORCE="1" ;;
    --doctor) MODE="doctor" ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

# CRITICAL: Always use canonical ~/agent-skills, NOT the script's current directory.
# This ensures symlinks work even when the script is run from a worktree.
CANONICAL_REPO="$HOME/agent-skills"

if [[ ! -d "$CANONICAL_REPO" ]]; then
  echo "ERROR: Canonical repo not found at $CANONICAL_REPO" >&2
  echo "Please clone agent-skills to ~/agent-skills first." >&2
  exit 1
fi

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

  # Check if target exists (as file/dir OR as valid symlink)
  if [[ -L "$target" ]]; then
    # It's a symlink - check where it points
    local dest
    dest="$(readlink "$target")"
    if [[ "$dest" == "$src_dir" ]]; then
      echo "✅ ok $target"
      return 0
    fi
    # Symlink points elsewhere (or is broken)
    if [[ "$MODE" == "apply" ]]; then
      if [[ "$FORCE" == "1" ]]; then
        ln -sfn "$src_dir" "$target"
        echo "✅ relinked $target -> $src_dir"
        return 0
      fi
      # Check if broken
      if [[ ! -e "$target" ]]; then
        echo "❌ $target is BROKEN: $dest (use --force or --repair)"
      else
        echo "⚠️  $target points elsewhere: $dest (use --force to relink)"
      fi
      return 1
    fi
    if [[ ! -e "$target" ]]; then
      echo "❌ $target is BROKEN: $dest"
    else
      echo "❌ $target points elsewhere: $dest"
    fi
    return 1
  fi

  # Not a symlink
  if [[ -e "$target" ]]; then
    # It's a regular file/directory
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
  fi

  # Target doesn't exist at all
  if [[ "$MODE" == "apply" ]]; then
    ln -s "$src_dir" "$target"
    echo "✅ linked $target -> $src_dir"
    return 0
  fi
  echo "❌ missing $target"
  return 1
}

if [[ "$MODE" == "apply" ]]; then
  mkdir -p "$DEST_DIR"
fi

# Doctor mode: check for broken/ephemeral links
if [[ "$MODE" == "doctor" ]]; then
  echo "Checking $DEST_DIR for broken or ephemeral symlinks..."
  echo ""

  broken=0
  ephemeral=0

  if [[ ! -d "$DEST_DIR" ]]; then
    echo "❌ Skills directory does not exist: $DEST_DIR"
    exit 1
  fi

  for link in "$DEST_DIR"/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    name="$(basename "$link")"

    # Check if target exists
    if [[ ! -e "$link" ]]; then
      echo "❌ BROKEN: $name -> $target"
      broken=$((broken + 1))
      continue
    fi

    # Check if target points to /tmp/agents
    if [[ "$target" == /tmp/agents/* ]]; then
      echo "⚠️  EPHEMERAL: $name -> $target"
      ephemeral=$((ephemeral + 1))
      continue
    fi

    echo "✅ OK: $name"
  done

  echo ""
  echo "Summary: $((broken + ephemeral)) issues found"
  [[ $broken -gt 0 ]] && echo "  - $broken broken symlinks"
  [[ $ephemeral -gt 0 ]] && echo "  - $ephemeral ephemeral symlinks (pointing to /tmp/agents)"

  if [[ $((broken + ephemeral)) -gt 0 ]]; then
    echo ""
    echo "Run: dx-agents-skills-install.sh --repair"
    exit 1
  fi
  exit 0
fi

echo "Agents skills dir: $DEST_DIR"
echo "Source repo: $CANONICAL_REPO"

fail=0
count=0

for cat in "${CATEGORIES[@]}"; do
  base="$CANONICAL_REPO/$cat"
  [[ -d "$base" ]] || continue

  while IFS= read -r skill_md; do
    name="$(extract_name "$skill_md")"
    [[ -n "$name" ]] || continue
    # CRITICAL: Construct canonical path, don't use pwd which could be a worktree
    skill_dir="$(dirname "$skill_md")"
    skill_name="$(basename "$skill_dir")"
    src_dir="$CANONICAL_REPO/$cat/$skill_name"
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

