#!/usr/bin/env bash
#
# DX Worktree Janitor (V7.6)
#
# Purpose: Ensure all worktree work is durable (pushed + has draft PR)
#
# Scope: /tmp/agents/**/<repo> only
#
# Safety:
# - No destructive actions (no close, no delete, no rebase, no squash)
# - Quiet mode by default (minimal notifications)
#
# Usage:
#   dx-janitor [--dry-run] [--verbose] [--check-abandon]

set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

# Configuration
WORKTREE_BASE="/tmp/agents"
ABANDON_THRESHOLD_HOURS=72

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
VERBOSE=false
CHECK_ABANDON=false

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
        --check-abandon)
            CHECK_ABANDON=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: dx-janitor [--dry-run] [--verbose] [--check-abandon]"
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

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
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

# Get PR details for a branch
get_pr_for_branch() {
    local branch="$1"
    local repo_path="$2"
    
    cd "$repo_path"
    gh pr list --head "$branch" --json number,state,labels,updatedAt --jq '.[0]' 2>/dev/null || echo "null"
}

# Calculate hours since a timestamp
hours_since() {
    local iso_date="$1"
    local pr_ts
    pr_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null || date -d "$iso_date" +%s 2>/dev/null || echo "0")
    local current_ts
    current_ts=$(date +%s)
    local diff=$((current_ts - pr_ts))
    echo $((diff / 3600))
}

# Process a single worktree
process_worktree() {
    local worktree_path="$1"
    local worktree_name
    worktree_name=$(basename "$(dirname "$worktree_path")")
    local repo_name
    repo_name=$(basename "$worktree_path")
    
    log "\n📁 Processing: $worktree_name/$repo_name"
    
    # Verify it's a git repo
    if [[ ! -d "$worktree_path/.git" ]]; then
        log "Not a git repository, skipping"
        return 0
    fi
    
    cd "$worktree_path"
    
    # Get current branch
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    
    if [[ -z "$current_branch" ]]; then
        warn "Could not determine branch, skipping"
        return 0
    fi
    
    log "Branch: $current_branch"
    
    # Skip master/main branches
    if [[ "$current_branch" == "master" || "$current_branch" == "main" ]]; then
        log "On default branch, skipping"
        return 0
    fi
    
    # Check for unpushed commits
    local unpushed_commits=0
    local has_upstream=false
    if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
        has_upstream=true
        unpushed_commits=$(git rev-list --count "$current_branch"@{upstream}.."$current_branch" 2>/dev/null || echo "0")
    else
        # No upstream: branch exists locally but not in origin.
        # Check if it has any commits ahead of master (or main)
        local base="origin/master"
        if ! git rev-parse "$base" >/dev/null 2>&1; then
            base="origin/main"
        fi
        
        unpushed_commits=$(git rev-list --count "$base..$current_branch" 2>/dev/null || echo "0")
        log "No upstream found. Commits ahead of $base: $unpushed_commits"
    fi
    
    if [[ "$unpushed_commits" -gt 0 ]]; then
        info "Found $unpushed_commits unpushed commits"
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would push $unpushed_commits commits"
        else
            if [[ "$has_upstream" == true ]]; then
                push_cmd=(git push origin "$current_branch")
            else
                push_cmd=(git push -u origin "$current_branch")
            fi

            if "${push_cmd[@]}"; then
                success "Pushed $unpushed_commits commits"
            else
                error "Failed to push commits"
                return 1
            fi
        fi
    else
        log "No unpushed commits"
    fi
    
    # Check for existing PR
    if ! check_gh_auth; then
        warn "gh CLI not available, skipping PR check"
        return 0
    fi
    
    local pr_info
    pr_info=$(get_pr_for_branch "$current_branch" "$worktree_path")
    
    if [[ "$pr_info" != "null" && -n "$pr_info" ]]; then
        local pr_number
        pr_number=$(printf '%s' "$pr_info" | python3 -c 'import json,sys; o=json.load(sys.stdin); print(o.get("number",""))' 2>/dev/null || true)
        local pr_state
        pr_state=$(printf '%s' "$pr_info" | python3 -c 'import json,sys; o=json.load(sys.stdin); print(o.get("state",""))' 2>/dev/null || true)
        local pr_labels
        pr_labels=$(printf '%s' "$pr_info" | python3 -c 'import json,sys; o=json.load(sys.stdin); print(\"\\n\".join([l.get(\"name\",\"\") for l in (o.get(\"labels\",[]) or [])]))' 2>/dev/null || true)
        
        log "Existing PR found: #$pr_number (state: $pr_state)"
        
        # Ensure labels are present
        if [[ "$DRY_RUN" == false && "$pr_state" == "OPEN" ]]; then
            # Add wip/worktree label if not present
            if [[ ! "$pr_labels" =~ "wip/worktree" ]]; then
                gh pr edit "$pr_number" --add-label "wip/worktree" 2>/dev/null || true
            fi
        fi
        
        # Check for abandonment (optional)
        if [[ "$CHECK_ABANDON" == true ]]; then
            local pr_updated
            pr_updated=$(printf '%s' "$pr_info" | python3 -c 'import json,sys; o=json.load(sys.stdin); print(o.get(\"updatedAt\",\"\"))' 2>/dev/null || true)
            
            if [[ -n "$pr_updated" && "$pr_state" == "OPEN" ]]; then
                local hours_old
                hours_old=$(hours_since "$pr_updated")
                
                if [[ "$hours_old" -gt $ABANDON_THRESHOLD_HOURS ]]; then
                    # Check if it has wip:abandon label
                    if [[ "$pr_labels" =~ "wip:abandon" ]]; then
                        warn "PR #$pr_number is ${hours_old}h old with wip:abandon label"
                        info "Consider closing or updating this PR"
                    fi
                fi
            fi
        fi
    else
        # No PR exists, create draft PR
        info "No PR exists for branch '$current_branch'"
        
        # Get the remote repo name
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        local repo_full_name=""
        
        if [[ "$remote_url" =~ github.com[/:]([^/]+)/([^/\.]+) ]]; then
            repo_full_name="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        fi
        
        if [[ -z "$repo_full_name" ]]; then
            warn "Could not determine repo name from remote"
            return 0
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would create draft PR for $repo_full_name"
        else
            # Create draft PR
            local pr_body="Worktree: \`$worktree_name\`
Branch: \`$current_branch\`
Path: \`$worktree_path\`

---
*Created by dx-janitor (V7.8)*"
            
            # Extract Feature-Key from commits if possible
            local feature_key=""
            feature_key=$(git log -1 --pretty=format:%B | grep -i "Feature-Key:" | head -1 | awk '{print $2}' || true)
            
            local pr_title="WIP: $current_branch"
            if [[ -n "$feature_key" ]]; then
                pr_title="WIP: $feature_key ($current_branch)"
            fi

            if gh pr create \
                --repo "$repo_full_name" \
                --title "$pr_title" \
                --body "$pr_body" \
                --draft \
                --label "wip/worktree" 2>/dev/null; then
                success "Created draft PR for $current_branch"
            else
                # Maybe PR already exists but search failed
                error "Failed to create PR (it might already exist or need manual push)"
                return 0 # Non-fatal
            fi
        fi
    fi
    
    return 0
}

# Find all worktrees
find_worktrees() {
    if [[ ! -d "$WORKTREE_BASE" ]]; then
        log "Worktree base directory not found: $WORKTREE_BASE"
        return 0
    fi
    
    find "$WORKTREE_BASE" -name ".git" -exec dirname {} \; 2>/dev/null
}

# Main execution
main() {
    echo "🧹 DX Worktree Janitor (V7.6)"
    echo "=============================="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE] No changes will be made"
    fi
    
    local worktrees
    worktrees=$(find_worktrees)
    
    if [[ -z "$worktrees" ]]; then
        echo "No worktrees found"
        exit 0
    fi
    
    local processed=0
    local pushed=0
    local created=0
    
    while IFS= read -r worktree; do
        if [[ -n "$worktree" ]]; then
            if process_worktree "$worktree"; then
                ((processed++))
            fi
        fi
    done <<< "$worktrees"
    
    echo ""
    echo "=============================="
    echo "Janitor complete: $processed worktrees processed"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] No actual changes made"
    fi
}

main "$@"
