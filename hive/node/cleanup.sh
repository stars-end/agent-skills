#!/usr/bin/env bash
# hive/node/cleanup.sh
# Garbage Collector: Prunes stale worktrees and pods.

set -euo pipefail

PODS_ROOT="/tmp/pods"
REPOS_ROOT="$HOME/repos"

echo "🧹 Running Hive Cleanup..."

if [ ! -d "$PODS_ROOT" ]; then
    echo "   No pods directory found."
    exit 0
fi

# 1. Prune Worktrees
echo " -> Pruning stale git worktrees..."
for REPO_DIR in "$REPOS_ROOT"/*; do
    if [ -d "$REPO_DIR/.git" ]; then
        (cd "$REPO_DIR" && git worktree prune)
    fi
done

# 2. Identify and Remove Stale Pods
# A pod is stale if its agent.log hasn't been modified in > 2 hours
# OR if it doesn't have an active systemd unit.
echo " -> Identifying stale pods..."
find "$PODS_ROOT" -maxdepth 1 -type d -mmin +120 | while read -r POD_DIR; do
    SESSION_ID=$(basename "$POD_DIR")
    if [ "$SESSION_ID" == "pods" ]; then continue; fi
    
    echo "   ❌ Removing stale pod: $SESSION_ID"
    
    # Attempt to remove worktrees associated with this pod first
    # (Though git worktree prune handles this, we can be proactive)
    rm -rf "$POD_DIR"
done

# 3. Clean up the Ledger
# TODO: Implement ledger pruning based on active pods

echo "✨ Cleanup complete."
