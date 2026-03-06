#!/usr/bin/env bash
# dx-worktree.sh (V8.6)
#
# A wrapper around git worktrees that hides complexity from agents.
# Primary goal: keep canonical clones clean and put all work in a workspace path.
#
# Workspace-First Contract (DX V8.6):
#   - Canonical repos under ~/ are clean mirrors (read-only for agents)
#   - All mutating work happens in /tmp/agents/<beads-id>/<repo>
#   - Recovery uses named worktree paths, not stash
#
# Usage:
#   dx-worktree create <beads-id> <repo>              # prints workspace path
#   dx-worktree open <beads-id> <repo> [-- <cmd...>]  # print path or exec command
#   dx-worktree resume <beads-id> <repo> [-- <cmd...>] # same as open
#   dx-worktree evacuate-canonical <repo>             # recover dirty canonical
#   dx-worktree cleanup <beads-id>                    # removes /tmp/agents/<beads-id>
#   dx-worktree prune <repo>                          # prunes worktree metadata
#   dx-worktree explain                               # prints policy + recovery commands
#
# Notes:
# - Never writes secrets.
# - Does not require the caller to know any git worktree internals.

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"
WORKSPACE_BASE="/tmp/agents"
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")

cmd="${1:-explain}"
shift || true

die() { echo "dx-worktree: $*" >&2; exit 2; }

is_canonical_repo() {
  local repo="$1"
  local canonical
  for canonical in "${CANONICAL_REPOS[@]}"; do
    if [[ "$repo" == "$canonical" ]]; then
      return 0
    fi
  done
  return 1
}

ensure_repo_exists() {
  local repo="$1"
  if [[ ! -d "$HOME/$repo/.git" ]]; then
    die "canonical repo missing at $HOME/$repo (expected clean trunk clone)"
  fi
}

iso_timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

create() {
  local beads_id="${1:-}"
  local repo="${2:-}"
  [[ -n "$beads_id" && -n "$repo" ]] || die "usage: dx-worktree create <beads-id> <repo>"
  
  ensure_repo_exists "$repo"
  
  # Ensure toolchain + wrappers are present (best-effort).
  "$AGENTS_ROOT/scripts/dx-toolchain.sh" ensure >/dev/null 2>&1 || true
  "$AGENTS_ROOT/scripts/dx-ensure-bins.sh" >/dev/null 2>&1 || true
  
  local path setup_out setup_rc
  set +e
  setup_out="$("$AGENTS_ROOT/scripts/worktree-setup.sh" "$beads_id" "$repo" 2>&1)"
  setup_rc=$?
  set -e
  if [[ "$setup_rc" -ne 0 ]]; then
    die "worktree-setup failed (rc=$setup_rc): $setup_out"
  fi
  path="$setup_out"
  if [[ -z "$path" ]]; then
    die "worktree-setup failed"
  fi
  
  # Best-effort trust to avoid gh/tooling failures on untrusted .mise.toml.
  if command -v mise >/dev/null 2>&1 && [[ -d "$path" ]]; then
    mise trust "$path" >/dev/null 2>&1 || true
  fi
  
  echo "$path"
}

open() {
  local beads_id="${1:-}"
  local repo="${2:-}"
  shift 2 2>/dev/null || die "usage: dx-worktree open <beads-id> <repo> [-- <command...>]"
  
  [[ -n "$beads_id" && -n "$repo" ]] || die "usage: dx-worktree open <beads-id> <repo> [-- <command...>]"
  
  ensure_repo_exists "$repo"
  
  local workspace_path="$WORKSPACE_BASE/$beads_id/$repo"
  
  # Create workspace if it doesn't exist
  if [[ ! -d "$workspace_path" ]]; then
    workspace_path="$(create "$beads_id" "$repo")"
  fi
  
  # Check if command execution requested
  if [[ "${1:-}" == "--" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "usage: dx-worktree open <beads-id> <repo> -- <command...>"
    fi
    # Exec the command in the workspace
    cd "$workspace_path"
    exec "$@"
  fi
  
  # No command: print structured output
  local branch="unknown"
  # Git worktrees have .git as a file (not a directory), so use git rev-parse
  if (cd "$workspace_path" && git rev-parse --git-dir >/dev/null 2>&1); then
    branch="$(cd "$workspace_path" && git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  fi
  
  cat <<EOF
repo=$repo
workspace_path=$workspace_path
branch=$branch
EOF
}

resume() {
  # Alias for open (same behavior)
  open "$@"
}

evacuate_canonical() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || die "usage: dx-worktree evacuate-canonical <repo>"
  
  ensure_repo_exists "$repo"
  is_canonical_repo "$repo" || die "$repo is not a canonical repo"
  
  local repo_path="$HOME/$repo"
  local timestamp
  timestamp="$(iso_timestamp)"
  local recovery_branch="recovery/canonical-$repo-$timestamp"
  local workspace_path="$WORKSPACE_BASE/recovery-$timestamp/$repo"
  
  # Check for skip conditions
  if [[ -f "$repo_path/.git/index.lock" ]]; then
    cat <<EOF
repo=$repo
workspace_path=
branch=
reason=index_lock
timestamp=$timestamp
skipped=true
EOF
    return 0
  fi
  
  if [[ -f "$repo_path/.git/MERGE_HEAD" ]] || [[ -f "$repo_path/.git/REBASE_HEAD" ]] || [[ -f "$repo_path/.git/CHERRY_PICK_HEAD" ]]; then
    cat <<EOF
repo=$repo
workspace_path=
branch=
reason=merge_rebase_in_progress
timestamp=$timestamp
skipped=true
EOF
    return 0
  fi
  
  # Check for session lock
  if [[ -x "$AGENTS_ROOT/scripts/dx-session-lock.sh" ]]; then
    if "$AGENTS_ROOT/scripts/dx-session-lock.sh" is-fresh "$repo_path" >/dev/null 2>&1; then
      cat <<EOF
repo=$repo
workspace_path=
branch=
reason=session_lock
timestamp=$timestamp
skipped=true
EOF
      return 0
    fi
  fi
  
  # Check if repo is clean (nothing to do)
  if (cd "$repo_path" && git diff --quiet && git diff --cached --quiet 2>/dev/null); then
    cat <<EOF
repo=$repo
workspace_path=
branch=
reason=clean
timestamp=$timestamp
skipped=true
EOF
    return 0
  fi
  
  # Create recovery worktree
  mkdir -p "$(dirname "$workspace_path")"
  
  if ! (cd "$repo_path" && git worktree add "$workspace_path" -b "$recovery_branch" HEAD 2>/dev/null); then
    die "failed to create recovery worktree at $workspace_path"
  fi
  
  # Preserve dirty state to recovery worktree
  cd "$repo_path"
  
  # Save unstaged changes
  git diff --quiet || git diff > "$workspace_path/.recovery.patch"
  
  # Save staged changes  
  git diff --cached --quiet || git diff --cached > "$workspace_path/.recovery-staged.patch"
  
  # Save untracked files (copy them to recovery worktree)
  local untracked_list
  untracked_list="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
  if [[ -n "$untracked_list" ]]; then
    echo "$untracked_list" > "$workspace_path/.recovery-untracked.txt"
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if [[ -f "$file" ]]; then
        mkdir -p "$workspace_path/$(dirname "$file")"
        cp "$file" "$workspace_path/$file"
      fi
    done <<< "$untracked_list"
  fi
  
  # Reset canonical to clean state
  git reset --hard HEAD
  git clean -fd
  git checkout master 2>/dev/null || git checkout main 2>/dev/null || true
  git pull --ff-only 2>/dev/null || true
  
  # Build recovery commands
  local recovery_cmds=()
  recovery_cmds+=("cd $workspace_path")
  [[ -f "$workspace_path/.recovery.patch" ]] && recovery_cmds+=("git apply .recovery.patch")
  [[ -f "$workspace_path/.recovery-staged.patch" ]] && recovery_cmds+=("git apply .recovery-staged.patch")
  
  cat <<EOF
repo=$repo
workspace_path=$workspace_path
branch=$recovery_branch
reason=evacuated
timestamp=$timestamp
skipped=false
recovery_command=${recovery_cmds[*]:-cd $workspace_path}
staged_patch=$([[ -f "$workspace_path/.recovery-staged.patch" ]] && echo ".recovery-staged.patch" || echo "none")
untracked_files=$([[ -f "$workspace_path/.recovery-untracked.txt" ]] && echo ".recovery-untracked.txt" || echo "none")
EOF
}

cleanup() {
  local beads_id="${1:-}"
  [[ -n "$beads_id" ]] || die "usage: dx-worktree cleanup <beads-id>"
  "$AGENTS_ROOT/scripts/worktree-cleanup.sh" "$beads_id"
}

prune_repo() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || die "usage: dx-worktree prune <repo>"
  ensure_repo_exists "$repo"
  git -C "$HOME/$repo" worktree prune || true
  echo "✅ pruned worktree metadata for $repo"
}

cleanup() {
  local beads_id="${1:-}"
  [[ -n "$beads_id" ]] || die "usage: dx-worktree cleanup <beads-id>"
  "$AGENTS_ROOT/scripts/worktree-cleanup.sh" "$beads_id"
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
Worktree policy (DX V8.6 - Workspace-First):

1) Canonical repos MUST stay clean + on master:
   ~/agent-skills, ~/prime-radiant-ai, ~/affordabot, ~/llm-common

2) All mutating work happens in workspace paths:
   /tmp/agents/<beads-id>/<repo>

3) Workspace-First Commands:
   dx-worktree create <beads-id> <repo>           # create workspace
   dx-worktree open <beads-id> <repo>             # show workspace status
   dx-worktree open <beads-id> <repo> -- <cmd>    # exec command in workspace
   dx-worktree resume <beads-id> <repo>           # alias for open

4) Recovery (never use stash for canonical repos):
   dx-worktree evacuate-canonical <repo>          # recover dirty canonical

5) Manual IDE Sessions:
   dx-worktree open bd-123 agent-skills -- opencode
   dx-worktree open bd-123 prime-radiant-ai -- antigravity
   dx-worktree open bd-123 affordabot -- codex
   dx-worktree open bd-123 llm-common -- claude

6) Governed Dispatch:
   dx-runner and dx-batch will REJECT canonical paths with:
   reason_code=canonical_worktree_forbidden
   remedy=dx-worktree create <beads-id> <repo>

7) Normal Operations Still Work:
   - git fetch, git pull --ff-only in canonical repos
   - railway status, railway run, railway shell
   - normal shell startup
   - loading skills from ~/agent-skills

The only behavior blocked: mutating agent execution against canonical roots.
EOF
}

case "$cmd" in
  create) create "$@" ;;
  open) open "$@" ;;
  resume) resume "$@" ;;
  evacuate-canonical) evacuate_canonical "$@" ;;
  cleanup) cleanup "$@" ;;
  prune) prune_repo "$@" ;;
  explain|help|-h|--help) explain ;;
  *) die "unknown command: $cmd" ;;
esac
