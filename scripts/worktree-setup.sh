#!/bin/bash
# worktree-setup.sh <beads-id> <repo-name>
# Creates an isolated git worktree for a specific agent task.
# Usage: ./worktree-setup.sh bd-123 prime-radiant-ai

set -e

BEADS_ID=$1
REPO_NAME=$2

if [ -z "$BEADS_ID" ] || [ -z "$REPO_NAME" ]; then
    echo "Usage: $0 <beads-id> <repo-name>" >&2
    exit 1
fi

# Base directory for all agent worktrees
WORKTREE_BASE="/tmp/agents"
TARGET_DIR="$WORKTREE_BASE/$BEADS_ID/$REPO_NAME"
REPO_PATH="$HOME/$REPO_NAME"

# Verify repo exists
if [ ! -d "$REPO_PATH/.git" ]; then
    echo "Error: Repository $REPO_PATH not found or not a git repo" >&2
    exit 1
fi

# Create base dir if needed
mkdir -p "$WORKTREE_BASE/$BEADS_ID"

# Navigate to main repo
cd "$REPO_PATH"

# Fetch latest master
git fetch origin > /dev/null 2>&1

# Create worktree
# Strategy:
# 1. Try creating new branch 'feature-$BEADS_ID'
# 2. If branch exists, checkout existing branch
# 3. If worktree dir exists, ensure it's clean/locked? (For now assuming new dir)

if [ -d "$TARGET_DIR" ]; then
    echo "Worktree directory $TARGET_DIR already exists" >&2
    echo "$TARGET_DIR"
    exit 0
fi

# Try creating worktree with new branch
if git worktree add "$TARGET_DIR" -b "feature-$BEADS_ID" origin/master > /dev/null 2>&1; then
    echo "$TARGET_DIR"
    exit 0
fi

# Fallback: Branch might already exist, try checking it out
if git worktree add "$TARGET_DIR" "feature-$BEADS_ID" > /dev/null 2>&1; then
    echo "$TARGET_DIR"
    exit 0
fi

echo "Error: Failed to create worktree at $TARGET_DIR" >&2
exit 1
