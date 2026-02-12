#!/usr/bin/env bash
# canonical-fetch.sh - Fetch-only for canonical repos (never blocks on dirty)
# Usage: canonical-fetch.sh [repo_name|all]
#
# Fetches from origin/master without merging. Never fails on dirty repos.

set -euo pipefail

REPO_ROOT="$HOME"
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
LOG_DIR="$HOME/logs/dx"
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" | tee -a "$LOG_DIR/fetch.log"
}

fetch_repo() {
    local repo="$1"
    local repo_path="$REPO_ROOT/$repo"

    if [[ ! -d "$repo_path/.git" ]]; then
        log "SKIP: $repo (not a git repo)"
        return 0
    fi

    cd "$repo_path"

    # Skip if locked
    if [[ -f ".git/index.lock" ]]; then
        log "SKIP: $repo (locked)"
        return 0
    fi

    # Fetch only - never conflicts with dirty working tree
    if git fetch origin master --quiet 2>/dev/null; then
        log "OK: $repo fetched"
        return 0
    else
        log "FAIL: $repo fetch failed"
        return 1
    fi
}

# Main
TARGET="${1:-all}"

if [[ "$TARGET" == "all" ]]; then
    FAILED=0
    for repo in "${CANONICAL_REPOS[@]}"; do
        fetch_repo "$repo" || ((FAILED++))
    done
    exit $FAILED
else
    fetch_repo "$TARGET"
fi
