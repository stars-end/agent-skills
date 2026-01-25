#!/usr/bin/env bash
# dx-worktree.sh
#
# A wrapper around git worktrees that hides complexity from agents.
# Primary goal: keep canonical clones clean and put all work in a workspace path.
#
# Usage:
#   dx-worktree create <beads-id> <repo>        # prints workspace path
#   dx-worktree cleanup <beads-id>              # removes /tmp/agents/<beads-id>
#   dx-worktree prune <repo>                    # prunes worktree metadata for a repo
#   dx-worktree explain                         # prints policy + recovery commands
#
# Notes:
# - Never writes secrets.
# - Does not require the caller to know any git worktree internals.

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"

cmd="${1:-explain}"
shift || true

die() { echo "dx-worktree: $*" >&2; exit 2; }

ensure_repo_exists() {
  local repo="$1"
  if [[ ! -d "$HOME/$repo/.git" ]]; then
    die "canonical repo missing at $HOME/$repo (expected clean trunk clone)"
  fi
}

create() {
  local beads_id="${1:-}"
  local repo="${2:-}"
  [[ -n "$beads_id" && -n "$repo" ]] || die "usage: dx-worktree create <beads-id> <repo>"

  ensure_repo_exists "$repo"

  # Ensure toolchain + wrappers are present (best-effort).
  "$AGENTS_ROOT/scripts/dx-toolchain.sh" ensure >/dev/null 2>&1 || true
  "$AGENTS_ROOT/scripts/dx-ensure-bins.sh" >/dev/null 2>&1 || true

  local path
  path="$(worktree-setup.sh "$beads_id" "$repo")"
  if [[ -z "$path" ]]; then
    die "worktree-setup failed"
  fi

  echo "$path"
}

cleanup() {
  local beads_id="${1:-}"
  [[ -n "$beads_id" ]] || die "usage: dx-worktree cleanup <beads-id>"
  worktree-cleanup.sh "$beads_id"
}

prune_repo() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || die "usage: dx-worktree prune <repo>"
  ensure_repo_exists "$repo"
  git -C "$HOME/$repo" worktree prune || true
  echo "✅ pruned worktree metadata for $repo"
}

explain() {
  cat <<'EOF'
Worktree policy (agent-skills):

1) Canonical clones must stay clean + on master:
   ~/agent-skills, ~/prime-radiant-ai, ~/affordabot, ~/llm-common

2) All agent work happens in a workspace path (worktree):
   /tmp/agents/<beads-id>/<repo>

3) Agents should NOT run `git worktree ...` directly.
   Use:
     dx-worktree create <beads-id> <repo>

Recovery:
- If your workspace is dirty and you need to switch tasks:
    ~/.agent/skills/dirty-repo-bootstrap/snapshot.sh
- If a workspace is broken/stuck:
    dx-worktree cleanup <beads-id>
    dx-worktree prune <repo>

ru sync integration:
- ru sync should operate only on canonical clones in ~/<repo>.
- Worktrees under /tmp/agents are NOT synced by ru.

auto-checkpoint integration:
- Optional. Recommended: do NOT auto-commit/push from canonical clones.
- If you must checkpoint, do it in the workspace, or use dirty-repo-bootstrap snapshot.
EOF
}

case "$cmd" in
  create) create "$@" ;;
  cleanup) cleanup "$@" ;;
  prune) prune_repo "$@" ;;
  explain|help|-h|--help) explain ;;
  *) die "unknown command: $cmd" ;;
esac

