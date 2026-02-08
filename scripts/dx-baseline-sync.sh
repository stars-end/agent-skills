#!/usr/bin/env bash
# dx-baseline-sync.sh - Local alternative to GHA Baseline Sync
# Orchestrates baseline regeneration and distribution across the fleet.
# MUST BE RUN from macmini local clone (canonical or worktree).

set -euo pipefail

# Config
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING_REPOS=("prime-radiant-ai" "affordabot" "llm-common")
HOME_DIR="/Users/fengning"

log() { echo -e "\033[0;34m[baseline-sync]\033[0m $*"; }
error() { echo -e "\033[0;31m[error]\033[0m $*" >&2; }
success() { echo -e "\033[0;32m[success]\033[0m $*"; }

# 1. Regenerate Baseline in agent-skills
log "Regenerating baseline in agent-skills..."
cd "$REPO_ROOT"
make publish-baseline > /dev/null

if [[ ! -f "dist/universal-baseline.md" ]]; then
    error "Baseline generation failed: dist/universal-baseline.md not found"
    exit 1
fi

# 2. Distribute to Siblings
for repo in "${SIBLING_REPOS[@]}"; do
    log "Syncing $repo..."
    
    # 2.1 Ensure Worktree exists for automation
    WT_ID="bot-baseline-sync"
    WT_PATH="/tmp/agents/$WT_ID/$repo"
    
    if [[ ! -d "$WT_PATH" ]]; then
        log "Creating worktree for $repo at $WT_PATH..."
        dx-worktree create "$WT_ID" "$repo" > /dev/null || {
            error "Failed to create worktree for $repo"
            continue
        }
    fi

    # 2.2 Perform Sync in Worktree
    (
        cd "$WT_PATH"
        git fetch origin master > /dev/null
        git checkout master > /dev/null 2>&1 || true # Ensure we are on master
        git pull origin master > /dev/null

        # Ensure fragments directory exists
        mkdir -p "fragments"
        
        # Copy baseline
        cp "$REPO_ROOT/dist/universal-baseline.md" "fragments/universal-baseline.md"
        
        # Run regeneration
        if [[ -x "scripts/agents-md-compile.zsh" ]]; then
            log "Regenerating AGENTS.md in $repo..."
            ./scripts/agents-md-compile.zsh > /dev/null
        fi
        
        # Check for changes
        if [[ -n "$(git status --porcelain=v1 AGENTS.md fragments/universal-baseline.md)" ]]; then
            log "Drift detected in $repo. Committing and pushing to bot branch..."
            
            BOT_BRANCH="bot/agent-baseline-sync"
            git checkout -B "$BOT_BRANCH" > /dev/null
            git add AGENTS.md fragments/universal-baseline.md
            git commit -m "chore: sync baseline from agent-skills [local-sync]"
            
            # Push with force-with-lease to match GHA behavior
            git push --force-with-lease origin "$BOT_BRANCH"
            success "Pushed baseline update to $repo branch $BOT_BRANCH"
        else
            log "No changes in $repo."
        fi
    )
done

success "Baseline sync complete."
