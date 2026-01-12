#!/bin/bash
set -e

# Usage: worktree-cleanup.sh <beads_id>
# Example: worktree-cleanup.sh bd-123

MODEL_NAME="$1"

if [ -z "$MODEL_NAME" ]; then
    echo "Usage: $0 <beads_id>"
    exit 1
fi

WORKTREE_ROOT="/tmp/agents/$MODEL_NAME"

if [ -d "$WORKTREE_ROOT" ]; then
    echo "removing worktree at $WORKTREE_ROOT..."
    
    # Prune git worktree metadata first (if inside a repo)
    # Use find to locate git worktrees inside the root
    find "$WORKTREE_ROOT" -name ".git" -type f | while read gitfile; do
        dir=$(dirname "$gitfile")
        echo "Pruning worktree at $dir"
        git -C "$dir" worktree prune || true
        # Also force remove from main repo if we can find it? 
        # Actually 'git worktree prune' usually handles it if the folder is gone, 
        # but better to explicit remove if we know the main repo. 
        # Since we don't know the main repo path here easily, we rely on standard deletion 
        # and subsequent prunes.
    done

    # Remove the directory
    rm -rf "$WORKTREE_ROOT"
    echo "Cleanup complete: $WORKTREE_ROOT"
else
    echo "Worktree root not found: $WORKTREE_ROOT"
fi
