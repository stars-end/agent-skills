#!/usr/bin/env bash
#
# worktree-cleanup.sh (V8.6 - bd-kuhj.8)
#
# Safe worktree cleanup with protection for active sessions.
# Honors: tmux attachment, working hours, git locks, session locks.
#
# Usage: worktree-cleanup.sh <beads_id> [--force]
#
# Exit codes:
#   0 - Success (cleaned or nothing to clean)
#   1 - General error
#   2 - Skipped (protected worktree)
#
set -euo pipefail

BEADS_ID="${1:-}"
FORCE_MODE="${2:-}"

if [[ -z "$BEADS_ID" ]]; then
    echo "Usage: $0 <beads_id> [--force]"
    exit 1
fi

WORKTREE_ROOT="/tmp/agents/$BEADS_ID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

is_tmux_attached_to_path() {
    local target_path="$1"
    command -v tmux >/dev/null 2>&1 || return 1

    while IFS=$'\t' read -r attached pane_path; do
        [[ "$attached" == "1" ]] || continue
        [[ "$pane_path" == "$target_path"* ]] && return 0
    done < <(tmux list-panes -a -F '#{session_attached}	#{pane_current_path}' 2>/dev/null || true)

    return 1
}

is_working_hours() {
    # Default: 8 AM - 6 PM local time
    local start_hour="${WORKTREE_CLEANUP_PROTECT_START:-8}"
    local end_hour="${WORKTREE_CLEANUP_PROTECT_END:-18}"
    local current_hour
    current_hour=$(date +%H)
    
    [[ "$current_hour" -ge "$start_hour" && "$current_hour" -lt "$end_hour" ]]
}

has_git_locks() {
    local path="$1"
    [[ -f "$path/.git/index.lock" ]]
}

has_git_merge_rebase() {
    local path="$1"
    [[ -f "$path/.git/MERGE_HEAD" ]] || \
    [[ -f "$path/.git/REBASE_HEAD" ]] || \
    [[ -f "$path/.git/CHERRY_PICK_HEAD" ]] || \
    [[ -f "$path/.git/REVERT_HEAD" ]]
}

has_active_session_lock() {
    local path="$1"
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$path" >/dev/null 2>&1
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
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | beads_id=$BEADS_ID | action=skip | reason=$reason | details=$details | path=$path" >> "$log_file"
}

if [[ ! -d "$WORKTREE_ROOT" ]]; then
    log "Worktree root not found: $WORKTREE_ROOT"
    exit 0
fi

log "Checking worktree: $WORKTREE_ROOT"

# Check for force mode
if [[ "$FORCE_MODE" == "--force" ]]; then
    log "Force mode enabled - bypassing protection checks"
else
    # bd-kuhj.8: Protection checks
    
    # 1. Tmux attachment check
    if is_tmux_attached_to_path "$WORKTREE_ROOT"; then
        log "SKIP: $WORKTREE_ROOT (tmux session attached)"
        write_skip_log "$WORKTREE_ROOT" "tmux_attached" "active_tmux_session"
        exit 2
    fi
    
    # 2. Working hours protection
    if is_working_hours; then
        if [[ "${WORKTREE_CLEANUP_ALLOW_WORKING_HOURS:-0}" != "1" ]]; then
            log "SKIP: $WORKTREE_ROOT (working hours protection)"
            write_skip_log "$WORKTREE_ROOT" "working_hours" "protected_time_window"
            exit 2
        fi
    fi
    
    # 3. Check subdirectories for git locks and active states
    for worktree_dir in "$WORKTREE_ROOT"/*/ ; do
        [[ -d "$worktree_dir" ]] || continue
        
        if has_git_locks "$worktree_dir"; then
            log "SKIP: $worktree_dir (index.lock present)"
            write_skip_log "$worktree_dir" "git_lock" ".git/index.lock"
            exit 2
        fi
        
        if has_git_merge_rebase "$worktree_dir"; then
            log "SKIP: $worktree_dir (merge/rebase in progress)"
            write_skip_log "$worktree_dir" "merge_rebase" "git_operation_in_progress"
            exit 2
        fi
        
        if has_active_session_lock "$worktree_dir"; then
            log "SKIP: $worktree_dir (active session lock)"
            write_skip_log "$worktree_dir" "session_lock" "dx-session-lock"
            exit 2
        fi
    done
fi

log "Removing worktree at $WORKTREE_ROOT..."

# Prune git worktree metadata first (if inside a repo)
# Use find to locate git worktrees inside the root
find "$WORKTREE_ROOT" -name ".git" -type f 2>/dev/null | while read -r gitfile; do
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
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | beads_id=$BEADS_ID | action=removed | reason=cleanup | path=$WORKTREE_ROOT" >> "$log_file"
