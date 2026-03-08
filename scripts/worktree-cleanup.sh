#!/bin/bash
set -e

# Usage: worktree-cleanup.sh <beads_id>
# Example: worktree-cleanup.sh bd-123
#
# V8.6: Safety checks before destructive cleanup:
# - Check for tmux-attached sessions
# - Check for fresh session locks
# - Skip if either condition detected

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_NAME="$1"

if [ -z "$MODEL_NAME" ]; then
    echo "Usage: $0 <beads_id>"
    exit 1
fi

WORKTREE_ROOT="/tmp/agents/$MODEL_NAME"

# V8.6: Check if tmux session is attached to any worktree in this root
is_tmux_attached_to_root() {
    local root="$1"
    command -v tmux >/dev/null 2>&1 || return 1

    while IFS=$'\t' read -r attached pane_path; do
        [[ "$attached" == "1" ]] || continue
        [[ "$pane_path" == "$root"* ]] && return 0
    done < <(tmux list-panes -a -F '#{session_attached}	#{pane_current_path}' 2>/dev/null || true)

    return 1
}

# V8.6: Check for fresh session locks in any worktree
has_fresh_session_lock() {
    local root="$1"
    local lock_file
    local now lock_ts age
    local threshold=14400  # 4 hours

    now=$(date +%s)

    while IFS= read -r lock_file; do
        [[ -f "$lock_file" ]] || continue
        lock_ts=$(cat "$lock_file" 2>/dev/null | cut -d':' -f1 || echo "0")
        [[ "$lock_ts" =~ ^[0-9]+$ ]] || lock_ts=0
        age=$((now - lock_ts))
        if [[ "$age" -lt "$threshold" ]]; then
            return 0
        fi
    done < <(find "$root" -name ".dx-session-lock" -type f 2>/dev/null || true)

    return 1
}

if [ -d "$WORKTREE_ROOT" ]; then
    # V8.6: Safety checks
    if is_tmux_attached_to_root "$WORKTREE_ROOT"; then
        echo "SKIP: tmux session attached to $WORKTREE_ROOT"
        echo "Reason: tmux_attached"
        echo "Action: Detach tmux session or wait for it to close before cleanup"
        exit 0
    fi

    if has_fresh_session_lock "$WORKTREE_ROOT"; then
        echo "SKIP: fresh session lock detected in $WORKTREE_ROOT"
        echo "Reason: session_lock_fresh"
        echo "Action: Wait for session lock to expire (4h) or remove manually"
        exit 0
    fi

    echo "removing worktree at $WORKTREE_ROOT..."

    # Prune git worktree metadata first (if inside a repo)
    # Use find to locate git worktrees inside the root
    find "$WORKTREE_ROOT" -name ".git" -type f 2>/dev/null | while read gitfile; do
        dir=$(dirname "$gitfile")
        echo "Pruning worktree at $dir"
        git -C "$dir" worktree prune 2>/dev/null || true
    done

    # Remove the directory
    rm -rf "$WORKTREE_ROOT"
    echo "Cleanup complete: $WORKTREE_ROOT"
    echo "Status: success"
else
    echo "Worktree root not found: $WORKTREE_ROOT"
    echo "Status: not_found"
fi
