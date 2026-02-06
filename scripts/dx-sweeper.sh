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

    # Safety check 2: DX session lock (V7.8)
    if [[ -f "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        if "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$repo_path"; then
            warn "$repo_name: Active session lock found, skipping"
            return 0
        fi
    fi
    
    # Check current state
    local current_branch
    current_branch=$(git branch --show-current)
    local has_changes=false
    local has_untracked=false
    
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        has_changes=true
    fi
    
    local has_stashes=false
    local stash_list
    stash_list=$(git stash list 2>/dev/null || echo "")
    if [[ -n "$stash_list" ]]; then
        has_stashes=true
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
    
    if [[ "$has_stashes" == true ]]; then
        log "$repo_name: Has stashes"
        needs_rescue=true
    fi
    
    if [[ "$needs_rescue" == false ]]; then
        log "$repo_name: Clean and on master, no action needed"
        return 0
    fi
    
    echo "🚨 $repo_name needs rescue (branch: $current_branch, dirty: $has_changes)"
    
    echo "🚨 $repo_name needs rescue (branch: $current_branch, dirty: $has_changes)"
    log "Audit: branch=$current_branch, changes=$has_changes, stashes=$has_stashes"
    
    # Step 0: Handle stashes (V7.8 - Safe Evacuation)
    if [[ "$has_stashes" == true ]]; then
        local stash_count
        stash_count=$(echo "$stash_list" | wc -l | tr -d ' ')
        warn "$repo_name: Found $stash_count stash(es). Evacuating via worktree..."
        
        local i=0
        while true; do
            # Refetch list to handle changing indices
            local current_stash_list
            current_stash_list=$(git stash list 2>/dev/null || echo "")
            if [[ -z "$current_stash_list" ]]; then break; fi
            
            # We always target the top-most stash that hasn't been rescued yet
            # After a successful drop, stash@{0} will be the NEXT stash.
            local stash_ref="stash@{0}"
            local timestamp
            timestamp=$(iso_timestamp)
            local rescue_branch="stash-rescue-${host}-${repo_name}-${timestamp}-${i}"
            local rescue_path="/tmp/agents/rescue-${host}-${repo_name}-${timestamp}-${i}"
            
            log "Evacuating $stash_ref to $rescue_branch via $rescue_path..."
            
            if [[ "$DRY_RUN" == true ]]; then
                echo "  [DRY-RUN] Would create worktree $rescue_path, apply $stash_ref, push, and drop."
                # In dry run, we must break to avoid infinite loop as indices don't change
                break
            fi

            # 1. Create temporary worktree
            if ! git worktree add -b "$rescue_branch" "$rescue_path" origin/master >/dev/null 2>&1; then
                error "Failed to create rescue worktree at $rescue_path"
                break # Avoid infinite loop on failure
            fi

            # 2. Apply stash in worktree
            if git -C "$rescue_path" stash apply "$stash_ref" >/dev/null 2>&1; then
                # 3. Commit changes
                git -C "$rescue_path" add -A
                git -C "$rescue_path" commit -m "chore(rescue): evacuate canonical stash (${host} ${repo_name})
                
Feature-Key: STASH-RESCUE-${host}-${repo_name}
Agent: dx-sweeper" >/dev/null 2>&1
                
                # 4. Push branch
                if git -C "$rescue_path" push -u origin "$rescue_branch" >/dev/null 2>&1; then
                    # 5. Create draft PR
                    local pr_url
                    pr_url=$(gh pr create --repo "stars-end/$repo_name" --head "$rescue_branch" --title "WIP: Stash Rescue ($host $repo_name)" --body "Rescued stash from canonical clone on $host." --draft 2>/dev/null || echo "")
                    
                    if [[ -n "$pr_url" ]]; then
                        success "Rescued stash to $pr_url"
                        # 6. ONLY NOW drop the stash in canonical
                        git stash drop "$stash_ref" >/dev/null 2>&1 || {
                            warn "Failed to drop $stash_ref in canonical after rescue. Breaking to avoid loop."
                            break
                        }
                    else
                        warn "Pushed $rescue_branch but failed to create PR. Stash NOT dropped. Breaking loop."
                        break
                    fi
                else
                    error "Failed to push $rescue_branch. Stash NOT dropped. Breaking loop."
                    break
                fi
            else
                error "Failed to apply $stash_ref in worktree. Stash NOT dropped. Breaking loop."
                break
            fi
            
            ((i+=1))
        done
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
        log "$repo_name: Off-trunk but clean; plan: restore master"
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would reset clean canonical to master"
            return 0
        fi
        git checkout master >/dev/null 2>&1 || true
        git fetch origin master >/dev/null 2>&1 || true
        git reset --hard origin/master >/dev/null 2>&1 || true
        git clean -fd >/dev/null 2>&1 || true
        success "$repo_name: Reset to clean master (no rescue PR; working tree was clean)"
        return 0
    fi

    # Step 2: Dirty working tree -> evacuate into a worktree, commit there, push rescue branch, then reset canonical.
    #
    # Canonical invariant: never rely on committing inside the canonical clone (hooks may block it).
    local timestamp
    timestamp=$(iso_timestamp)
    local rescue_branch="rescue-${host}-${repo_name}"
    local rescue_sha=""

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would create rescue PR for dirty worktree"
        return 0
    fi

    local tmp_dir rescue_path
    tmp_dir="$(mktemp -d "/tmp/dx-sweeper.${repo_name}.${timestamp}.XXXX" 2>/dev/null || mktemp -d)"
    rescue_path="$(mktemp -d "/tmp/agents/rescue-${host}-${repo_name}-${timestamp}.XXXX" 2>/dev/null || mktemp -d)"

    local unstaged_patch="$tmp_dir/unstaged.patch"
    local staged_patch="$tmp_dir/staged.patch"
    local untracked_list="$tmp_dir/untracked.list"

    # Snapshot canonical changes without modifying canonical state.
    git diff >"$unstaged_patch" 2>/dev/null || true
    git diff --cached >"$staged_patch" 2>/dev/null || true
    git ls-files -o --exclude-standard >"$untracked_list" 2>/dev/null || true

    # Create rescue worktree (reuse rolling rescue branch if it exists).
    git fetch origin master >/dev/null 2>&1 || true
    if git show-ref --verify --quiet "refs/remotes/origin/${rescue_branch}"; then
        if ! git worktree add -B "$rescue_branch" "$rescue_path" "origin/${rescue_branch}" >/dev/null 2>&1; then
            error "Failed to create rescue worktree for origin/${rescue_branch}"
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    else
        if ! git worktree add -B "$rescue_branch" "$rescue_path" "origin/master" >/dev/null 2>&1; then
            error "Failed to create rescue worktree from origin/master"
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    fi

    # Apply patches and untracked files into the rescue worktree.
    if [[ -s "$staged_patch" ]]; then
        if ! git -C "$rescue_path" apply --whitespace=nowarn "$staged_patch" >/dev/null 2>&1; then
            error "Failed to apply staged patch to rescue worktree"
            git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    fi
    if [[ -s "$unstaged_patch" ]]; then
        if ! git -C "$rescue_path" apply --whitespace=nowarn "$unstaged_patch" >/dev/null 2>&1; then
            error "Failed to apply unstaged patch to rescue worktree"
            git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    fi
    if [[ -s "$untracked_list" ]]; then
        # Best-effort: tar can fail if files disappear mid-run; treat that as fatal (avoid resetting canonical).
        if ! tar -C "$repo_path" -czf "$tmp_dir/untracked.tgz" -T "$untracked_list" >/dev/null 2>&1; then
            error "Failed to snapshot untracked files"
            git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
        if ! tar -C "$rescue_path" -xzf "$tmp_dir/untracked.tgz" >/dev/null 2>&1; then
            error "Failed to restore untracked files into rescue worktree"
            git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    fi

    # Commit + push from the rescue worktree (this is where hooks allow commits).
    git -C "$rescue_path" add -A >/dev/null 2>&1 || true
    if ! git -C "$rescue_path" diff --cached --quiet >/dev/null 2>&1; then
        if git -C "$rescue_path" commit -m "chore(rescue): canonical rescue (${host} ${repo_name}) ${timestamp}

Original branch: ${current_branch}

Feature-Key: RESCUE-${host}-${repo_name}
Agent: dx-sweeper" >/dev/null 2>&1; then
            rescue_sha="$(git -C "$rescue_path" rev-parse HEAD 2>/dev/null || echo "")"
        else
            error "Failed to commit rescue changes (will NOT reset canonical)"
            git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
            rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
            return 1
        fi
    else
        warn "No changes to commit in rescue worktree (unexpected for dirty canonical)"
    fi

    if ! git -C "$rescue_path" push -u origin "$rescue_branch" >/dev/null 2>&1; then
        error "Failed to push rescue branch '$rescue_branch' (will NOT reset canonical)"
        git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
        rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true
        return 1
    fi

    # Cleanup rescue worktree after successful push.
    git worktree remove --force "$rescue_path" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir" "$rescue_path" >/dev/null 2>&1 || true

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
            ((processed+=1))
            # Check if rescue was needed by looking at output
            # This is simplified - in production, track actual rescues
        else
            ((skipped+=1))
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
