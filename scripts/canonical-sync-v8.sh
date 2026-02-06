#!/usr/bin/env bash
#
# scripts/canonical-sync-v8.sh (V8.0)
#
# Purpose: Evacuate canonical repo changes to rescue branches and reset to master.
# Cron schedule: daily at 3:05 AM
# Bead: bd-obyk
#
# Invariants:
# 1. NEVER reset canonical unless push succeeded.
# 2. Use diff-based file copy, NOT rsync.
# 3. Use porcelain git output.
# 4. Idempotent.

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

iso_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

short_hostname() {
    hostname -s 2>/dev/null || hostname | cut -d'.' -f1
}

process_repo() {
    local repo="$1"
    local repo_path="$HOME/$repo"
    local host
    host=$(short_hostname)
    
    log "\n📁 Processing canonical: $repo"
    
    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository, skipping"
        return 0
    fi
    
    # Skip if locked
    if [[ -f "$repo_path/.git/index.lock" ]]; then
        warn "$repo: .git/index.lock exists, skipping"
        return 0
    fi
    
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        if "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$repo_path"; then
            warn "$repo: Active session lock found, skipping"
            return 0
        fi
    fi
    
    cd "$repo_path"
    
    # Fetch origin master
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin master --quiet || { warn "$repo: Failed to fetch origin master"; }
    else
        log "[DRY-RUN] Would fetch origin master"
    fi
    
    # Detect state
    local current_branch
    current_branch=$(git branch --show-current)
    local is_dirty=false
    if [[ -n $(git status --porcelain) ]]; then
        is_dirty=true
    fi
    
    local is_off_trunk=false
    if [[ "$current_branch" != "master" ]]; then
        is_off_trunk=true
    fi
    
    if [[ "$is_dirty" == false && "$is_off_trunk" == false ]]; then
        log "$repo: Already clean and on master"
        return 0
    fi
    
    echo "🚨 $repo needs rescue (branch: $current_branch, dirty: $is_dirty)"
    
    # Evacuation of off-trunk branch commits (best effort)
    if [[ "$is_off_trunk" == true ]]; then
        local ahead
        ahead=$(git rev-list --count origin/master..HEAD 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            log "$repo: Branch '$current_branch' is ahead of origin/master by $ahead commits. Pushing..."
            if [[ "$DRY_RUN" == false ]]; then
                git push origin "$current_branch" 2>/dev/null || true
            else
                log "[DRY-RUN] Would push branch '$current_branch'"
            fi
        fi
    fi
    
    # Evacuation of dirty state
    if [[ "$is_dirty" == true ]]; then
        local timestamp
        timestamp=$(iso_timestamp)
        local rescue_branch="rescue-${host}-${repo}-${timestamp}"
        local rescue_dir="/tmp/agents/rescue-${repo}-$$"
        
        log "Evacuating dirty changes to $rescue_branch..."
        
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would evacuate dirty changes to $rescue_branch and reset canonical"
            return 0
        fi
        
        # 1. Create rescue worktree
        if ! git worktree add -b "$rescue_branch" "$rescue_dir" origin/master >/dev/null 2>&1; then
            error "$repo: Failed to create rescue worktree at $rescue_dir"
            return 1
        fi
        
        # 2. Copy changed files via porcelain status (staged + unstaged + untracked)
        git status --porcelain | while IFS= read -r status_line; do
            # status_line format: "XY filename" or "XY filename -> renamed"
            local xy="${status_line:0:2}"
            local file="${status_line:3}"

            # Handle renames: "R  old -> new"
            if [[ "$file" == *" -> "* ]]; then
                file="${file##* -> }"
            fi

            # Skip deletions — nothing to copy
            local x="${xy:0:1}"
            local y="${xy:1:1}"
            if [[ "$x" == "D" || "$y" == "D" ]]; then
                continue
            fi

            # Skip if file doesn't exist (race condition safety)
            if [[ ! -e "$repo_path/$file" ]]; then
                continue
            fi

            # Copy preserving directory structure
            mkdir -p "$rescue_dir/$(dirname "$file")"
            cp -a "$repo_path/$file" "$rescue_dir/$file"
        done
        
        # 3. Commit in rescue worktree
        cd "$rescue_dir"
        git add -A
        if git commit -m "chore(rescue): evacuate canonical ($host $repo)

Original-Branch: $current_branch
Feature-Key: RESCUE-${host}-${repo}
Agent: canonical-sync-v8" --quiet; then
            log "Committed rescue changes"
        else
            log "Nothing to commit in rescue worktree"
        fi
        
        # 4. Push rescue branch
        if git push -u origin "$rescue_branch" --quiet; then
            success "Pushed rescue branch $rescue_branch"
            
            # NOW safe to reset canonical
            cd "$repo_path"
            git checkout master -q
            git reset --hard origin/master
            git clean -fdq
            git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
            rm -rf "$rescue_dir" 2>/dev/null || true
            success "$repo: Reset to clean master"
        else
            error "$repo: Push failed for $rescue_branch — canonical NOT reset"
            git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
            rm -rf "$rescue_dir" 2>/dev/null || true
            return 1
        fi
    else
        # Off-trunk but clean
        log "$repo: Off-trunk but clean, resetting to master..."
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would reset clean canonical to master"
            return 0
        fi
        
        git checkout master -q
        git reset --hard origin/master
        git clean -fdq
        success "$repo: Reset to clean master"
    fi
}

main() {
    echo "🧹 DX Canonical Sync V8"
    echo "======================="
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        process_repo "$repo" || warn "$repo: Process failed"
    done

    echo ""
    echo "======================="
    echo "Canonical sync complete"
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] No actual changes made"
    fi
}

main "$@"
