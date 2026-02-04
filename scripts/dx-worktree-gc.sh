#!/usr/bin/env bash
#
# DX Worktree GC (V7.8)
#
# Purpose: Bounded /tmp/agents surface area via deterministic lifecycle rules.
#
# GC States:
# - SAFE DELETE: Clean + Merged + >24h old + No active session.
# - ARCHIVE: Stale (>7d) + unmerged.
# - KEEP: Active or recently updated.
# - ESCALATE: Dirty or ambiguous state.
#
# Usage:
#   dx-worktree-gc [--dry-run] [--force] [--verbose]
#

set -euo pipefail

WORKTREE_BASE="/tmp/agents"
COOLDOWN_HOURS=24
ARCHIVE_THRESHOLD_DAYS=7
ARCHIVE_BASE="$HOME/.dx-archives"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
FORCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

log() { [[ "$VERBOSE" == true ]] && echo -e "$1"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

mkdir -p "$ARCHIVE_BASE"

check_merged() {
    local repo_path="$1"
    local branch="$2"
    cd "$repo_path"
    
    # Check if branch is merged into origin/master or origin/main
    local base="origin/master"
    if ! git rev-parse "$base" >/dev/null 2>&1; then
        base="origin/main"
    fi
    
    if git merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
        return 0 # Merged
    fi
    
    # Check PR status via gh CLI
    if command -v gh &>/dev/null; then
        local pr_status
        pr_status=$(gh pr list --head "$branch" --json state --jq '.[0].state' 2>/dev/null || echo "null")
        if [[ "$pr_status" == "MERGED" || "$pr_status" == "CLOSED" ]]; then
            return 0 # PR merged or closed
        fi
    fi
    
    return 1 # Not merged
}

get_last_commit_hours() {
    local repo_path="$1"
    local last_ts
    last_ts=$(git -C "$repo_path" log -1 --format=%ct 2>/dev/null || echo "0")
    local current_ts
    current_ts=$(date +%s)
    echo $(((current_ts - last_ts) / 3600))
}

process_worktree() {
    local path="$1"
    local name
    name=$(basename "$(dirname "$path")")
    local repo
    repo=$(basename "$path")
    
    log "\n🔎 Auditing: $name/$repo"
    
    if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then return 0; fi
    
    cd "$path"
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "")
    if [[ -z "$branch" || "$branch" == "master" || "$branch" == "main" ]]; then return 0; fi
    
    local dirty
    dirty=$(git status --porcelain=v1)
    local age_hours
    age_hours=$(get_last_commit_hours "$path")
    
    # Check for active session lock
    if [[ -f "$path/.dx-session-lock" ]]; then
        local lock_ts
        lock_ts=$(cut -d: -f1 "$path/.dx-session-lock" 2>/dev/null || echo "0")
        local current_ts
        current_ts=$(date +%s)
        if (( current_ts - lock_ts < 14400 )); then
            log "KEEP: Active session lock found"
            return 0
        fi
    fi
    
    if check_merged "$path" "$branch"; then
        if [[ -z "$dirty" ]]; then
            if [[ "$age_hours" -ge "$COOLDOWN_HOURS" ]]; then
                success "SAFE DELETE: $name/$repo ($branch)"
                if [[ "$DRY_RUN" == false ]]; then
                    # Remove worktree safely
                    git -C "$WORKTREE_BASE" worktree remove -f "$path" 2>/dev/null || rm -rf "$path"
                fi
            else
                log "KEEP: Merged but in cooldown (${age_hours}h < ${COOLDOWN_HOURS}h)"
            fi
        else
            warn "ESCALATE: Merged but DIRTY: $name/$repo"
        fi
    elif [[ "$age_hours" -ge $((ARCHIVE_THRESHOLD_DAYS * 24)) ]]; then
        if [[ -z "$dirty" ]]; then
            warn "ARCHIVE: Stale clean worktree: $name/$repo"
            if [[ "$DRY_RUN" == false ]]; then
                local archive_name="${name}_${repo}_$(date +%Y%m%d).tar.gz"
                tar -czf "$ARCHIVE_BASE/$archive_name" -C "$(dirname "$path")" "$repo"
                git -C "$WORKTREE_BASE" worktree remove -f "$path" 2>/dev/null || rm -rf "$path"
                info "Archived to $ARCHIVE_BASE/$archive_name"
            fi
        else
            error "ESCALATE: Stale but DIRTY: $name/$repo"
        fi
    else
        log "KEEP: Active/Unmerged: $name/$repo"
    fi
}

main() {
    info "🧹 DX Worktree GC (V7.8)"
    [[ "$DRY_RUN" == true ]] && info "[DRY-RUN MODE] No deletions will occur"
    
    local worktrees
    worktrees=$(find "$WORKTREE_BASE" -maxdepth 3 -name ".git" -exec dirname {} \; 2>/dev/null)
    
    for wt in $worktrees; do
        process_worktree "$wt"
    done
}

main
