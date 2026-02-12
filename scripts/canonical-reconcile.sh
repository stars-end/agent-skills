#!/usr/bin/env bash
# canonical-reconcile.sh - Pull clean repos, skip dirty ones
# Usage: canonical-reconcile.sh

set -euo pipefail

REPO_ROOT="$HOME"
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
LOG_DIR="$HOME/logs/dx"
TRACKER_SCRIPT="$(dirname "$0")/canonical-dirty-tracker.sh"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $1" | tee -a "$LOG_DIR/reconcile.log"
}

reconcile_repo() {
    local repo="$1"
    local repo_path="$REPO_ROOT/$repo"

    if [[ ! -d "$repo_path/.git" ]]; then
        return 0
    fi

    cd "$repo_path"

    # Skip if locked
    if [[ -f ".git/index.lock" ]]; then
        log "SKIP: $repo (locked)"
        return 0
    fi

    # Check if dirty
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        log "SKIP: $repo (dirty) - updating tracker"
        "$TRACKER_SCRIPT" check 2>/dev/null || true
        return 0
    fi

    # Clean - pull if behind
    git fetch origin master --quiet 2>/dev/null
    local behind=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")

    if [[ "$behind" -gt 0 ]]; then
        if git pull --ff-only origin master --quiet 2>/dev/null; then
            log "OK: $repo pulled $behind commits"
        else
            log "FAIL: $repo pull failed"
            return 1
        fi
    else
        log "OK: $repo already up to date"
    fi
}

# Main
FAILED=0
for repo in "${CANONICAL_REPOS[@]}"; do
    reconcile_repo "$repo" || ((FAILED++))
done

exit $FAILED
