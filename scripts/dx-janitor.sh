#!/usr/bin/env bash
#
# DX Worktree Janitor (V7.8)
#
# Purpose: Ensure all worktree work is durable (pushed + has draft PR)
#
# Scope: /tmp/agents/**/<repo> only
#
# Safety:
# - No destructive actions (no close, no delete, no rebase, no squash)
# - Bounded PR creation to prevent spam
#
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

# Configuration
WORKTREE_BASE="/tmp/agents"
DX_JANITOR_MAX_NEW_PRS=${DX_JANITOR_MAX_NEW_PRS:-3}

# Internal state
PRS_CREATED=0
PRS_DEFERRED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

log() { if [[ "$VERBOSE" == true ]]; then echo -e "$1"; fi; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

# Determine repo slug from path
get_repo_slug() {
    local wt_path="$1"
    local repo_name
    repo_name=$(basename "$wt_path")
    # Mapping for stars-end
    echo "stars-end/$repo_name"
}

# Process a single worktree
process_worktree() {
    local worktree_path="$1"
    local worktree_name
    worktree_name=$(basename "$(dirname "$worktree_path")")
    local repo_name
    repo_name=$(basename "$worktree_path")
    local repo_slug
    repo_slug=$(get_repo_slug "$worktree_path")
    
    log "\n📁 Processing: $worktree_name/$repo_name ($repo_slug)"
    
    # Session Lock Check
    if [[ -f "$(dirname "$0")/dx-session-lock.sh" ]]; then
        if "$(dirname "$0")/dx-session-lock.sh" is-fresh "$worktree_path"; then
            log "KEEP: Active session lock found, skipping janitor"
            return 0
        fi
    fi
    
    if ! git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    
    cd "$worktree_path"
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -z "$current_branch" || "$current_branch" == "master" || "$current_branch" == "main" ]]; then
        return 0
    fi
    
    # Compute signals
    local base="origin/master"
    git rev-parse "$base" >/dev/null 2>&1 || base="origin/main"

    local worktree_dirty=false
    [[ -n "$(git status --porcelain=v1 2>/dev/null | grep -v "\.ralph" || true)" ]] && worktree_dirty=true

    local ahead_of_base
    ahead_of_base=$(git rev-list --count "$base..$current_branch" 2>/dev/null || echo "0")

    # If clean and not ahead, ignore
    if [[ "$ahead_of_base" -eq 0 && "$worktree_dirty" == false ]]; then
        return 0
    fi
    
    # Upstream check
    local has_upstream=false
    if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
        has_upstream=true
    fi

    if [[ "$has_upstream" == false && "$ahead_of_base" -gt 0 ]]; then
        info "No upstream found for $current_branch. Pushing..."
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would push $current_branch"
        else
            git push -u origin "$current_branch"
        fi
    fi

    # PR Check
    if command -v gh &>/dev/null; then
        local pr_number
        pr_number=$(gh pr list --repo "$repo_slug" --head "$current_branch" --state all --json number --jq '.[0].number' 2>/dev/null || echo "null")
        
        if [[ "$pr_number" != "null" && -n "$pr_number" ]]; then
            log "Existing PR found: #$pr_number"
        elif [[ "$ahead_of_base" -gt 0 ]]; then
            if [[ "$PRS_CREATED" -ge "$DX_JANITOR_MAX_NEW_PRS" ]]; then
                warn "PR budget exhausted. Deferring PR for $current_branch."
                PRS_DEFERRED=$((PRS_DEFERRED + 1))
            else
                info "Creating draft PR for $current_branch..."
                if [[ "$DRY_RUN" == true ]]; then
                    echo "  [DRY-RUN] Would create draft PR"
                    PRS_CREATED=$((PRS_CREATED + 1))
                else
                    if gh pr create --repo "$repo_slug" --draft --head "$current_branch" --base master \
                        --title "WIP: $current_branch (janitor surfaced)" \
                        --body "Surfaced by V7.8 janitor closure policy." 2>/dev/null; then
                        success "Created draft PR"
                        PRS_CREATED=$((PRS_CREATED + 1))
                    fi
                fi
            fi
        fi
    fi
}

main() {
    echo "🧹 DX Worktree Janitor (V7.8)"
    echo "Budget: $DX_JANITOR_MAX_NEW_PRS new PRs"
    
    local worktrees
    worktrees=$(find "$WORKTREE_BASE" -mindepth 3 -maxdepth 3 -name ".git" -exec dirname {} \; 2>/dev/null)
    
    for wt in $worktrees; do
        process_worktree "$wt"
    done
    
    echo -e "\nSummary: PRs Created: $PRS_CREATED, Deferred: $PRS_DEFERRED"
}

main "$@"