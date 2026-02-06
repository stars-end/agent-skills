#!/usr/bin/env bash
# worktree-setup.sh <beads-id> <repo-name>
# Creates an isolated git worktree for a specific agent task.
#
# Usage:
#   ./worktree-setup.sh bd-123 prime-radiant-ai

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BEADS_ID="${1:-}"
REPO_NAME="${2:-}"

if [[ -z "$BEADS_ID" || -z "$REPO_NAME" ]]; then
    echo "Usage: $0 <beads-id> <repo-name>" >&2
    exit 1
fi

# Base directory for all agent worktrees
WORKTREE_BASE="/tmp/agents"
TARGET_DIR="$WORKTREE_BASE/$BEADS_ID/$REPO_NAME"
REPO_PATH="$HOME/$REPO_NAME"

# Verify repo exists
if [[ ! -d "$REPO_PATH/.git" ]]; then
    echo "Error: Repository $REPO_PATH not found or not a git repo" >&2
    exit 1
fi

# Create base dir if needed
mkdir -p "$WORKTREE_BASE/$BEADS_ID"

# Navigate to main repo
cd "$REPO_PATH"

# Determine origin default branch (origin/HEAD).
# Fleet standard is "master", but some repos may use "main".
DEFAULT_BRANCH="$(
    git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true
)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
UPSTREAM_REF="origin/${DEFAULT_BRANCH}"

# Fetch latest default branch
git fetch --quiet --prune origin "${DEFAULT_BRANCH}" || git fetch --quiet --prune origin || true

# Create worktree
# Strategy:
# 1. Try creating new branch 'feature-$BEADS_ID'
# 2. If branch exists, checkout existing branch
# 3. If worktree dir exists, ensure it's clean/locked? (For now assuming new dir)

if [[ -d "$TARGET_DIR" ]]; then
    echo "Worktree directory $TARGET_DIR already exists" >&2
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        "$SCRIPT_DIR/dx-session-lock.sh" touch "$TARGET_DIR" >/dev/null 2>&1 || true
    fi
    echo "$TARGET_DIR"
    exit 0
fi

BRANCH="feature-$BEADS_ID"

# Try creating worktree with new branch
if git worktree add "$TARGET_DIR" -b "$BRANCH" "$UPSTREAM_REF" > /dev/null 2>&1; then
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        "$SCRIPT_DIR/dx-session-lock.sh" touch "$TARGET_DIR" >/dev/null 2>&1 || true
    fi
    echo "$TARGET_DIR"
    exit 0
fi

# Fallback: Branch might already exist, try checking it out
if git worktree add "$TARGET_DIR" "$BRANCH" > /dev/null 2>&1; then
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        "$SCRIPT_DIR/dx-session-lock.sh" touch "$TARGET_DIR" >/dev/null 2>&1 || true
    fi
    echo "$TARGET_DIR"
    exit 0
fi

echo "Error: Failed to create worktree at $TARGET_DIR" >&2
exit 1
