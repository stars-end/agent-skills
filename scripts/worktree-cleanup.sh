#!/usr/bin/env bash
#
# worktree-cleanup.sh (V8.6 - bd-kuhj.8)
#
# Manual worktree cleanup - safe by default, no automation protections.
# Use worktree-cleanup-automation.sh for cron jobs (has working-hours/tmux protections).
#
# Usage: worktree-cleanup.sh <beads_id>
#
# Exit codes:
#   0 - Success (cleaned or nothing to clean)
#   1 - General error
#   2 - Skipped (protected: git locks or active session)
#
set -euo pipefail

BEADS_ID="${1:-}"

if [[ -z "$BEADS_ID" ]]; then
    echo "Usage: $0 <beads_id>"
    exit 1
fi

WORKTREE_ROOT="/tmp/agents/$BEADS_ID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

# Get the actual git directory for a worktree
# In linked worktrees, .git is a file pointing to the gitdir
get_git_dir() {
    local worktree_path="$1"
    local git_file_or_dir="$worktree_path/.git"
    
    if [[ -d "$git_file_or_dir" ]]; then
        # Regular repo: .git is a directory
        echo "$git_file_or_dir"
    elif [[ -f "$git_file_or_dir" ]]; then
        # Linked worktree: .git contains "gitdir: /path/to/.git/worktrees/..."
        local gitdir_line
        gitdir_line=$(head -1 "$git_file_or_dir" 2>/dev/null || true)
        if [[ "$gitdir_line" =~ ^gitdir:\ (.+)$ ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            # Fallback: just read the file content
            cat "$git_file_or_dir"
        fi
    else
        # No .git at all
        echo ""
    fi
}

has_git_locks() {
    local worktree_path="$1"
    local git_dir
    git_dir="$(get_git_dir "$worktree_path")"
    [[ -n "$git_dir" && -f "$git_dir/index.lock" ]]
}

has_git_merge_rebase() {
    local worktree_path="$1"
    local git_dir
    git_dir="$(get_git_dir "$worktree_path")"
    [[ -z "$git_dir" ]] && return 1
    
    [[ -f "$git_dir/MERGE_HEAD" ]] || \
    [[ -f "$git_dir/REBASE_HEAD" ]] || \
    [[ -f "$git_dir/CHERRY_PICK_HEAD" ]] || \
    [[ -f "$git_dir/REVERT_HEAD" ]] || \
    [[ -f "$git_dir/BISECT_LOG" ]]
}

has_active_session_lock() {
    local worktree_path="$1"
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$worktree_path" >/dev/null 2>&1
        return $?
    fi
    return 1
}

write_skip_log() {
    local path="$1"
    local reason="$2"
    local details="$3"
    local log_file="$HOME/.dx-state/worktree-cleanup.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | beads_id=$BEADS_ID | action=skip | reason=$reason | details=$details | path=$path | mode=manual" >> "$log_file"
}

if [[ ! -d "$WORKTREE_ROOT" ]]; then
    log "Worktree root not found: $WORKTREE_ROOT"
    exit 0
fi

log "Checking worktree: $WORKTREE_ROOT"

# Check subdirectories for git locks and active states
for worktree_dir in "$WORKTREE_ROOT"/*/ ; do
    [[ -d "$worktree_dir" ]] || continue
    
    if has_git_locks "$worktree_dir"; then
        log "SKIP: $worktree_dir (index.lock present)"
        write_skip_log "$worktree_dir" "git_lock" ".git/index.lock"
        exit 2
    fi
    
    if has_git_merge_rebase "$worktree_dir"; then
        log "SKIP: $worktree_dir (merge/rebase/bisect in progress)"
        write_skip_log "$worktree_dir" "merge_rebase" "git_operation_in_progress"
        exit 2
    fi
    
    if has_active_session_lock "$worktree_dir"; then
        log "SKIP: $worktree_dir (active session lock)"
        write_skip_log "$worktree_dir" "session_lock" "dx-session-lock"
        exit 2
    fi
done

log "Removing worktree at $WORKTREE_ROOT..."

# Prune git worktree metadata first
find "$WORKTREE_ROOT" -type f -name ".git" 2>/dev/null | while read -r gitfile; do
    dir=$(dirname "$gitfile")
    log "Pruning worktree at $dir"
    git -C "$dir" worktree prune 2>/dev/null || true
done

# Remove the directory
rm -rf "$WORKTREE_ROOT"
log "Cleanup complete: $WORKTREE_ROOT"

# Log successful cleanup
log_file="$HOME/.dx-state/worktree-cleanup.log"
mkdir -p "$(dirname "$log_file")"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | beads_id=$BEADS_ID | action=removed | reason=cleanup | path=$WORKTREE_ROOT | mode=manual" >> "$log_file"
