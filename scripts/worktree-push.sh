#!/usr/bin/env bash
#
# scripts/worktree-push.sh (V8.0)
#
# Purpose: Push all unpushed worktree branches to origin.
# Cron schedule: daily at 3:15 AM
# Bead: bd-s7a3
#
# Invariants:
# 1. ALWAYS use --porcelain for worktree listing.
# 2. NO PR creation — push only.
# 3. Best-effort: warn on failure, don't abort.
# 4. Skip detached HEAD worktrees.
# 5. Idempotent.

set -euo pipefail

# Configuration
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose]"
            exit 1
            ;;
    esac
done

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "$1"
    fi
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

process_worktree() {
    local wt_path="$1"
    local wt_branch="$2"
    local wt_is_detached="$3"
    local is_main="$4"
    
    if [[ "$is_main" == true ]]; then
        return 0
    fi
    
    if [[ "$wt_is_detached" == true ]]; then
        log "  Skipping detached HEAD worktree: $wt_path"
        return 0
    fi
    
    if [[ -z "$wt_branch" ]]; then
        return 0
    fi
    
    local remote_ref="origin/$wt_branch"
    local needs_push=false
    
    if ! git rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        log "  Branch '$wt_branch' does not exist on origin"
        needs_push=true
    else
        local ahead
        ahead=$(git rev-list --count "$remote_ref".."$wt_branch" 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            log "  Branch '$wt_branch' is ahead of origin by $ahead commits"
            needs_push=true
        fi
    fi
    
    if [[ "$needs_push" == true ]]; then
        echo "📤 Pushing branch: $wt_branch"
        if [[ "$DRY_RUN" == false ]]; then
            if git push origin "$wt_branch" --quiet; then
                success "Pushed $wt_branch"
            else
                warn "Failed to push $wt_branch"
            fi
        else
            log "  [DRY-RUN] Would push branch $wt_branch"
        fi
    else
        log "  Branch '$wt_branch' is up to date with origin"
    fi
}

process_repo() {
    local repo="$1"
    local repo_path="$HOME/$repo"
    
    log "\n📁 Processing repo: $repo"
    
    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository, skipping"
        return 0
    fi
    
    cd "$repo_path"
    
    # Fetch origin to have latest remote refs
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin --quiet || { warn "$repo: Failed to fetch origin"; }
    fi
    
    local path=""
    local branch=""
    local is_detached=false
    local count=0
    
    while IFS= read -r line; do
        if [[ $line =~ ^worktree\ (.*) ]]; then
            if [[ -n "$path" ]]; then
                local is_main=false
                if [[ $count -eq 0 ]]; then is_main=true; fi
                process_worktree "$path" "$branch" "$is_detached" "$is_main"
                ((count+=1))
            fi
            path="${BASH_REMATCH[1]}"
            branch=""
            is_detached=false
        elif [[ $line =~ ^branch\ refs/heads/(.*) ]]; then
            branch="${BASH_REMATCH[1]}"
        elif [[ $line == "detached" ]]; then
            is_detached=true
        fi
    done < <(git worktree list --porcelain)
    
    if [[ -n "$path" ]]; then
        local is_main=false
        if [[ $count -eq 0 ]]; then is_main=true; fi
        process_worktree "$path" "$branch" "$is_detached" "$is_main"
    fi
}

main() {
    echo "🚀 DX Worktree Push V8"
    echo "======================"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        process_repo "$repo" || warn "$repo: Push failed"
    done
}

main "$@"
