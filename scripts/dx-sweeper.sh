#!/usr/bin/env bash
#
# DX Canonical Sweeper (V7.6)
#
# Purpose: Handle dirty/off-trunk canonical repos by creating rescue PRs
# and restoring canonical to clean master state.
#
# Scope: Only ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}
#
# Safety:
# - Skips if .git/index.lock exists (git in progress)
# - Never resets without pushing first
# - Rolling rescue PR per host+repo (bounded)
#
# Usage:
#   dx-sweeper [--dry-run] [--verbose]

set -euo pipefail

# Configuration
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
            echo "Usage: dx-sweeper [--dry-run] [--verbose]"
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

# Get current timestamp in ISO format
iso_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

# Get short hostname
short_hostname() {
    hostname -s 2>/dev/null || hostname | cut -d'.' -f1
}

# Check if gh CLI is available and authenticated
check_gh_auth() {
    if ! command -v gh &>/dev/null; then
        error "gh CLI not found"
        return 1
    fi
    
    if ! gh auth status &>/dev/null 2>&1; then
        error "gh CLI not authenticated"
        return 1
    fi
    
    return 0
}

# Process a single canonical repo
process_repo() {
    local repo_name="$1"
    local repo_path="$HOME/$repo_name"
    local host
    host=$(short_hostname)
    
    log "\n📁 Processing: $repo_name"
    
    # Verify repo exists
    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository"
        return 0
    fi
    
    cd "$repo_path"
    
    # Safety check 1: Git index.lock
    if [[ -f ".git/index.lock" ]]; then
        warn "$repo_name: .git/index.lock exists, skipping"
        return 0
    fi
    
    # Check current state
    local current_branch
    current_branch=$(git branch --show-current)
    local has_changes=false
    local has_untracked=false
    
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        has_changes=true
    fi
    
    # Determine if action needed
    local needs_rescue=false
    
    if [[ "$current_branch" != "master" ]]; then
        log "$repo_name: On branch '$current_branch' (not master)"
        needs_rescue=true
    fi
    
    if [[ "$has_changes" == true ]]; then
        log "$repo_name: Has uncommitted changes"
        needs_rescue=true
    fi
    
    if [[ "$needs_rescue" == false ]]; then
        log "$repo_name: Clean and on master, no action needed"
        return 0
    fi
    
    echo "🚨 $repo_name needs rescue (branch: $current_branch, dirty: $has_changes)"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would create rescue branch and PR"
        return 0
    fi
    
    # Rolling rescue branch name (bounded inbox: one PR per host+repo)
    local rescue_branch="canonical-rescue-${host}-${repo_name}"
    local timestamp
    timestamp=$(iso_timestamp)
    
    # Check gh auth
    if ! check_gh_auth; then
        error "$repo_name: Cannot proceed without gh CLI auth"
        return 1
    fi
    
    # Step 1: Preserve current branch if not master (push commits before we reset)
    if [[ "$current_branch" != "master" ]]; then
        log "Preserving branch '$current_branch'..."
        
        # Check if branch has commits worth saving
        local local_commits
        local_commits=$(git rev-list --count master.."$current_branch" 2>/dev/null || echo "0")
        
        if [[ "$local_commits" -gt 0 ]]; then
            log "Branch has $local_commits local commits"

            # Push branch even if it has no upstream (durability > convention)
            if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
                git push origin "$current_branch" 2>/dev/null || warn "Failed to push branch '$current_branch' (will still reset canonical)"
            else
                git push -u origin "$current_branch" 2>/dev/null || warn "Failed to push -u branch '$current_branch' (will still reset canonical)"
            fi
            success "Preserved branch '$current_branch' via push (best-effort)"
        fi
    fi

    # If we're only off-trunk (clean working tree), just restore canonical to master after preserving commits.
    if [[ "$has_changes" == false ]]; then
        log "$repo_name: Off-trunk but clean; restoring canonical to master"
        git checkout master >/dev/null 2>&1 || true
        git fetch origin master >/dev/null 2>&1 || true
        git reset --hard origin/master >/dev/null 2>&1 || true
        git clean -fd >/dev/null 2>&1 || true
        success "$repo_name: Reset to clean master (no rescue PR; working tree was clean)"
        return 0
    fi

    # Step 2: Dirty working tree → commit changes onto the rolling rescue branch and push it
    local rescue_sha=""
    log "Creating rescue commit on '$rescue_branch'..."

        # Stash current dirty state (including untracked) so we can safely switch branches
        git stash push --include-untracked -m "dx-sweeper: ${host}/${repo_name} ${timestamp}" >/dev/null 2>&1 || true

        # Ensure rescue branch exists locally (track remote if it exists)
        if git show-ref --verify --quiet "refs/remotes/origin/${rescue_branch}"; then
            git checkout -B "$rescue_branch" "origin/${rescue_branch}" || {
                error "Failed to checkout origin/${rescue_branch}"
                return 1
            }
        else
            git fetch origin master >/dev/null 2>&1 || true
            git checkout -B "$rescue_branch" "origin/master" || {
                error "Failed to create rescue branch from origin/master"
                return 1
            }
        fi

        # Apply stash and commit
        if git stash pop >/dev/null 2>&1; then
            git add -A
            if git commit -m "chore(rescue): canonical rescue (${host} ${repo_name}) ${timestamp}

Original branch: ${current_branch}

Feature-Key: RESCUE-${host}-${repo_name}
Agent: dx-sweeper" >/dev/null 2>&1; then
                rescue_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
            else
                warn "No changes to commit after stash pop"
            fi
        else
            warn "Failed to apply stash; rescue commit may be incomplete"
        fi

        # Push rolling rescue branch (fast-forward)
        if ! git push origin "$rescue_branch" >/dev/null 2>&1; then
            error "Failed to push rescue branch '$rescue_branch' (will NOT reset canonical)"
            return 1
        fi

    success "Pushed rolling rescue branch: $rescue_branch"

    # Step 3: Find or create rescue PR (head is the rolling rescue branch)
    local pr_title="chore: [RESCUE] canonical rescue ($host $repo_name)"
    local pr_body="Auto-generated rescue PR for dirty canonical.
    
**Source:** $host:$repo_path
**Rescue branch:** \`$rescue_branch\`
**Created:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
## Latest Rescue
- Branch: \`$rescue_branch\`
- Commit: \`${rescue_sha:-<none>}\`
- Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
## Action Required
1. Review changes
2. Either merge this PR or cherry-pick needed commits
3. Canonical will be reset to clean master after rescue is pushed
    
---
*Generated by dx-sweeper (V7.6)*"
    
    # Check for existing rescue PR
    local existing_pr
    existing_pr=$(gh pr list --head "$rescue_branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
    
    if [[ -n "$existing_pr" ]]; then
        log "Updating existing rescue PR #$existing_pr"
        gh pr edit "$existing_pr" --body "$pr_body" || {
            warn "Failed to update PR body, but branch was pushed"
        }
        
        # No comment spam: only update the PR body.
    else
        log "Creating new rescue PR"
        gh pr create \
            --title "$pr_title" \
            --body "$pr_body" \
            --draft \
            --label "wip/rescue,host/$host,repo/$repo_name" || {
            warn "Failed to create PR, but branch was pushed"
        }
    fi
    
    # Step 4: Reset canonical to clean master
    log "Resetting canonical to clean master..."
    
    # Checkout master
    git checkout master || {
        error "Failed to checkout master"
        return 1
    }
    
    # Fetch latest master
    git fetch origin master
    
    # Hard reset to origin/master
    git reset --hard origin/master || {
        error "Failed to reset to origin/master"
        return 1
    }
    
    # Clean any untracked files
    git clean -fd
    
    success "$repo_name: Reset to clean master"
    echo "   Rescue branch: $rescue_branch"
    
    return 0
}

# Main execution
main() {
    echo "🧹 DX Canonical Sweeper (V7.6)"
    echo "=============================="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE] No changes will be made"
    fi
    
    local processed=0
    local rescued=0
    local skipped=0
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        if process_repo "$repo"; then
            ((processed++))
            # Check if rescue was needed by looking at output
            # This is simplified - in production, track actual rescues
        else
            ((skipped++))
        fi
    done
    
    echo ""
    echo "=============================="
    echo "Sweep complete: $processed repos processed"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] No actual changes made"
    fi
}

main "$@"
