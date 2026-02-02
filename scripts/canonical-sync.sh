#!/bin/bash
# canonical-sync.sh - Daily reset of canonical repos to origin/master

set -euo pipefail

REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
LOG_PREFIX="[canonical-sync $(date +'%Y-%m-%d %H:%M:%S')]"

SYNCED=0
SKIPPED=0

for repo in "${REPOS[@]}"; do
    cd ~/$repo 2>/dev/null || continue
    
    # Skip if this is a worktree
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
    if [[ "$GIT_DIR" =~ worktrees ]]; then
        continue
    fi
    
    # Skip if git operation in progress
    if [[ -f .git/index.lock ]]; then
        echo "$LOG_PREFIX $repo: Skipped (git operation in progress)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # Check if repo needs healing (not on master or has uncommitted changes)
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    DIRTY=$(git status --porcelain 2>/dev/null || echo "")
    
    if [[ "$CURRENT_BRANCH" != "master" ]] || [[ -n "$DIRTY" ]]; then
        echo "$LOG_PREFIX Healing ~/$repo (was on $CURRENT_BRANCH, dirty: $([[ -n "$DIRTY" ]] && echo "yes" || echo "no"))"
    fi
    
    # Fetch from origin
    if ! git fetch origin --prune --quiet 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to fetch (network issue?)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # Nuclear reset to master
    if ! git checkout -f master 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to checkout master"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    if ! git reset --hard origin/master 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to reset to origin/master"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    git clean -fdx 2>/dev/null || true
    
    # Clean up old WIP branches
    git branch | grep -E 'wip/auto|auto-checkpoint/' | xargs -r git branch -D 2>/dev/null || true
    
    # Enforce V5 External Beads (Phase 4)
    if [[ -d ".beads" ]]; then
        echo "$LOG_PREFIX $repo: Removing legacy .beads/ directory"
        rm -rf .beads
    fi
    
    echo "$LOG_PREFIX $repo: ✅ Synced to origin/master"
    SYNCED=$((SYNCED + 1))
done

echo "$LOG_PREFIX Complete: $SYNCED synced, $SKIPPED skipped"

# Alert if all syncs failed
if [[ $SYNCED -eq 0 && $SKIPPED -gt 0 ]]; then
    echo "🚨 SYNC FAILED: 0 repos synced" | tee ~/logs/SYNC_ALERT
    exit 1
fi

exit 0
