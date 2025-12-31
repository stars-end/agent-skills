#!/usr/bin/env bash
# hive/pods/create.sh
# Isolation Engine: Creates a secure, ephemeral workspace for an agent.

set -euo pipefail

SESSION_ID=$1
REPOS=${2:-"agent-skills"} # Comma-separated list

POD_DIR="/tmp/pods/$SESSION_ID"
WORKTREES_DIR="$POD_DIR/worktrees"
CONTEXT_DIR="$POD_DIR/context"
LOGS_DIR="$POD_DIR/logs"

echo "📦 Creating Pod: $SESSION_ID"

# 1. Create Structure
mkdir -p "$WORKTREES_DIR" "$CONTEXT_DIR" "$LOGS_DIR" "$POD_DIR/state"

# 2. Provision Worktrees
IFS=',' read -ra REPO_LIST <<< "$REPOS"
for REPO_NAME in "${REPO_LIST[@]}"; do
    REPO_PATH="$HOME/repos/$REPO_NAME"
    TARGET_WT="$WORKTREES_DIR/$REPO_NAME"
    
    if [ ! -d "$REPO_PATH" ]; then
        echo "   ⚠️ Repository $REPO_NAME not found. Attempting auto-clone..."
        # Try to clone from stars-end org
        if git clone "git@github.com:stars-end/$REPO_NAME.git" "$REPO_PATH"; then
             echo "   ✅ Cloned $REPO_NAME successfully."
        else
             echo "   ❌ Failed to clone $REPO_NAME. Skipping."
             continue
        fi
    fi

    echo "   -> Provisioning worktree: $REPO_NAME"
    (
        cd "$REPO_PATH"
        git fetch origin master --quiet
        git worktree add -b "hive/$SESSION_ID/$REPO_NAME" "$TARGET_WT" origin/master --quiet
    )
    
    # Install local hooks for safety
    if [ -f "$HOME/agent-skills/git-safety-guard/install.sh" ]; then
        (cd "$TARGET_WT" && "$HOME/agent-skills/git-safety-guard/install.sh" --quiet)
    fi
done

# 3. Inject Context (The Briefcase)
# This will be populated by prompts.py / hive-queen.py
touch "$CONTEXT_DIR/00_MISSION.md"
touch "$CONTEXT_DIR/01_CONTEXT.json"

# 4. Permissions
chmod -R 700 "$POD_DIR"

echo "✨ Pod creation complete: $POD_DIR"