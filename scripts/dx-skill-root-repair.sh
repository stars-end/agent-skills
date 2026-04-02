#!/usr/bin/env bash
set -euo pipefail

# dx-skill-root-repair.sh
# Deterministic cleanup/repair for user skill roots across client lanes.
#
# Goals for this wave:
# - remove archived parallelize-cloud-work links if present
# - ensure design-md/reactcomponents/stitch-loop point to canonical extended paths
# - prune broken links for touched names only
# - preserve Codex .system content

MODE="check"

usage() {
  cat <<'USAGE'
Usage:
  dx-skill-root-repair.sh --check
  dx-skill-root-repair.sh --apply
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
 done

# Canonical source of truth is always ~/agent-skills unless explicitly overridden.
# Worktree runs must pass CANONICAL_ROOT=<worktree>/agent-skills when desired.
CANONICAL_ROOT="${CANONICAL_ROOT:-$HOME/agent-skills}"
if [[ ! -d "$CANONICAL_ROOT" ]]; then
  echo "ERROR: canonical root missing: $CANONICAL_ROOT" >&2
  exit 1
fi

declare -a ROOTS=(
  "$HOME/.agents/skills"
  "$HOME/.codex/skills"
  "$HOME/.claude/skills"
)

declare -a MIGRATED=(design-md reactcomponents stitch-loop)
ARCHIVED_NAME="parallelize-cloud-work"

skill_target() {
  local name="$1"
  printf '%s/extended/%s\n' "$CANONICAL_ROOT" "$name"
}

ensure_dir() {
  local root="$1"
  if [[ "$MODE" == "apply" ]]; then
    mkdir -p "$root"
  fi
}

remove_path() {
  local p="$1"
  if [[ "$MODE" == "apply" ]]; then
    rm -rf "$p"
    echo "removed $p"
  else
    echo "would remove $p"
  fi
}

link_skill() {
  local root="$1"
  local name="$2"
  local target
  target="$(skill_target "$name")"
  local link="$root/$name"

  if [[ ! -d "$target" ]]; then
    echo "ERROR: missing target for $name: $target" >&2
    return 1
  fi

  if [[ -L "$link" ]]; then
    local dest
    dest="$(readlink "$link")"
    if [[ "$dest" == "$target" ]]; then
      echo "ok $link -> $target"
      return 0
    fi
    if [[ "$MODE" == "apply" ]]; then
      ln -sfn "$target" "$link"
      echo "relinked $link -> $target"
      return 0
    fi
    echo "would relink $link -> $target (was $dest)"
    return 1
  fi

  if [[ -e "$link" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      rm -rf "$link"
      ln -s "$target" "$link"
      echo "replaced $link -> $target"
      return 0
    fi
    echo "would replace non-link $link -> $target"
    return 1
  fi

  if [[ "$MODE" == "apply" ]]; then
    ln -s "$target" "$link"
    echo "linked $link -> $target"
    return 0
  fi
  echo "missing $link"
  return 1
}

prune_broken_touched_name() {
  local root="$1"
  local name="$2"
  local p="$root/$name"
  if [[ -L "$p" && ! -e "$p" ]]; then
    remove_path "$p"
  fi
}

status=0
for root in "${ROOTS[@]}"; do
  ensure_dir "$root"
  if [[ ! -d "$root" ]]; then
    echo "skip missing root $root"
    continue
  fi

  # Remove archived entry if present (link, file, or dir)
  if [[ -e "$root/$ARCHIVED_NAME" || -L "$root/$ARCHIVED_NAME" ]]; then
    remove_path "$root/$ARCHIVED_NAME"
  fi

  for name in "${MIGRATED[@]}"; do
    prune_broken_touched_name "$root" "$name"
    if ! link_skill "$root" "$name"; then
      status=1
    fi
  done
 done

if [[ "$MODE" == "check" ]]; then
  # report broken links for touched names only
  for root in "${ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    for name in "${MIGRATED[@]}" "$ARCHIVED_NAME"; do
      p="$root/$name"
      if [[ -L "$p" && ! -e "$p" ]]; then
        echo "broken $p"
        status=1
      fi
    done
  done
fi

exit $status
