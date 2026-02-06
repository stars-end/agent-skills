#!/usr/bin/env bash
#
# scripts/worktree-gc-v8.sh (V8.0)
#
# Purpose: Prune merged worktrees and clean up /tmp/agents directories.
# Cron schedule: daily at 3:30 AM
# Bead: bd-7jpo
#
# Invariants:
# 1. ALWAYS use --porcelain for worktree listing.
# 2. Detached HEAD: prune only if merge-base --is-ancestor confirms merged.
# 3. Never prune the main working tree.
# 4. Idempotent.

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
    local repo_path="$1"
    local wt_path="$2"
    local wt_head="$3"
    local wt_branch="$4"
    local wt_is_detached="$5"
    local is_main="$6"
    
    if [[ "$is_main" == true ]]; then
        log "  Skipping main worktree: $wt_path"
        return 0
    fi
    
    local should_prune=false
    local reason=""
    
    # Case 1: Path doesn't exist on disk
    if [[ ! -d "$wt_path" ]]; then
        should_prune=true
        reason="Path missing from disk"
    fi
    
    # Case 2: Branch merged into origin/master
    if [[ "$should_prune" == false && -n "$wt_branch" ]]; then
        if git merge-base --is-ancestor "$wt_head" origin/master 2>/dev/null; then
            should_prune=true
            reason="Branch '$wt_branch' merged into origin/master"
        fi
    fi
    
    # Case 3: Detached HEAD merged into origin/master
    if [[ "$should_prune" == false && "$wt_is_detached" == true ]]; then
        if git merge-base --is-ancestor "$wt_head" origin/master 2>/dev/null; then
            should_prune=true
            reason="Detached HEAD ($wt_head) merged into origin/master"
        else
            warn "  Worktree $wt_path has unmerged detached HEAD: $wt_head"
        fi
    fi
    
    if [[ "$should_prune" == true ]]; then
        echo "♻️  Pruning worktree: $wt_path ($reason)"
        if [[ "$DRY_RUN" == false ]]; then
            git worktree remove "$wt_path" --force >/dev/null 2>&1 || true
            rm -rf "$wt_path" 2>/dev/null || true
            success "Pruned $wt_path"
        else
            log "  [DRY-RUN] Would remove $wt_path"
        fi
    else
        log "  Keeping worktree: $wt_path (branch: $wt_branch)"
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
    
    # Fetch origin master to ensure merge-base is accurate
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin master --quiet || { warn "$repo: Failed to fetch origin master"; }
    fi
    
    local path=""
    local head=""
    local branch=""
    local is_detached=false
    local count=0
    
    while IFS= read -r line; do
        if [[ $line =~ ^worktree\ (.*) ]]; then
            # If we have a previous entry, process it
            if [[ -n "$path" ]]; then
                local is_main=false
                if [[ $count -eq 0 ]]; then is_main=true; fi
                process_worktree "$repo_path" "$path" "$head" "$branch" "$is_detached" "$is_main"
                ((count+=1))
            fi
            path="${BASH_REMATCH[1]}"
            head=""
            branch=""
            is_detached=false
        elif [[ $line =~ ^HEAD\ (.*) ]]; then
            head="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^branch\ refs/heads/(.*) ]]; then
            branch="${BASH_REMATCH[1]}"
        elif [[ $line == "detached" ]]; then
            is_detached=true
        fi
    done < <(git worktree list --porcelain)
    
    # Process last entry
    if [[ -n "$path" ]]; then
        local is_main=false
        if [[ $count -eq 0 ]]; then is_main=true; fi
        process_worktree "$repo_path" "$path" "$head" "$branch" "$is_detached" "$is_main"
    fi
    
    # Final cleanup of stale entries
    if [[ "$DRY_RUN" == false ]]; then
        git worktree prune
    fi
}

main() {
    echo "🧹 DX Worktree GC V8"
    echo "===================="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        process_repo "$repo" || warn "$repo: GC failed"
    done
}

main "$@"
