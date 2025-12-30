#!/usr/bin/env bash
set -euo pipefail
SESSION_ID="$1"; REPOS_ARG="$3"
POD_DIR="/tmp/pods/$SESSION_ID"
mkdir -p "$POD_DIR"/{worktrees,context,logs,state}
chmod 700 "$POD_DIR"
IFS=',' read -ra REPO_LIST <<< "$REPOS_ARG"
for REPO in "${REPO_LIST[@]}"; do
    (cd ~/repos/$REPO && git fetch origin && git worktree add -b "feat/agent-$SESSION_ID" "$POD_DIR/worktrees/$REPO" origin/master)
done
echo "✅ Pod Created: $SESSION_ID"
