#!/usr/bin/env bash
# canonical-fetch.sh - Fetch-only for canonical repos (never blocks on dirty)
# Usage: canonical-fetch.sh [repo_name|all]
#
# Fetches from each repo's canonical branch without merging. Never fails on dirty repos.

set -euo pipefail

REPO_ROOT="$HOME"
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common" "bd-symphony")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"
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

    local remote_result remote_status remote_current remote_expected
    remote_result="$(canonical_ensure_origin_ssh "$repo" "$repo_path" "fix")"
    remote_status="${remote_result%%|*}"
    remote_current="$(echo "$remote_result" | cut -d'|' -f2)"
    remote_expected="$(echo "$remote_result" | cut -d'|' -f3)"
    case "$remote_status" in
        converted)
            log "OK: $repo origin normalized to SSH ($remote_current -> $remote_expected)"
            ;;
        set_failed|unsupported_origin|missing_origin|read_failed)
            log "WARN: $repo origin not normalized ($remote_status; current=${remote_current:-unknown}; expected=${remote_expected:-unknown})"
            ;;
    esac

    # Fetch only - never conflicts with dirty working tree
    local fetch_output
    local branch
    branch="$(canonical_repo_branch "$repo")"
    if fetch_output=$(git fetch origin "$branch" 2>&1); then
        log "OK: $repo fetched $branch"
        return 0
    else
        log "FAIL: $repo fetch failed - $fetch_output"
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
