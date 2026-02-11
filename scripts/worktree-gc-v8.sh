#!/usr/bin/env bash
#
# scripts/worktree-gc-v8.sh (V8.1)
#
# Purpose: Prune merged worktrees and clean up /tmp/agents directories.
# Cron schedule: daily at 3:30 AM
# Bead: bd-7vnu
#
# Invariants:
# 1. ALWAYS use --porcelain for worktree listing.
# 2. Detached HEAD: prune only if merge-base --is-ancestor confirms merged.
# 3. Never prune the main working tree.
# 4. NEVER force-remove dirty worktrees - evacuate only.
# 5. Idempotent.
# 6. Age threshold configurable via --max-age (default 48h).

set -euo pipefail

# Colors for output (defined early for validation functions)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")

# Default max age for stale worktrees (48 hours in seconds)
DEFAULT_MAX_AGE=$((48 * 3600))

# Validate MAX_AGE value (used for both env var and CLI)
validate_max_age() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo -e "${RED}❌ Invalid MAX_AGE: '$value' (must be positive integer)${NC}" >&2
        exit 1
    fi
    echo "$value"
}

# Set MAX_AGE from env or default (validate if env was set)
MAX_AGE="${DX_GC_MAX_AGE:-$DEFAULT_MAX_AGE}"
if [[ -n "${DX_GC_MAX_AGE:-}" ]]; then
    MAX_AGE=$(validate_max_age "$DX_GC_MAX_AGE")
fi

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
        --max-age)
            shift
            if [[ -n "${1:-}" ]]; then
                PARSED_MAX_AGE=""
                # Parse age (supports: 48h, 2d, 172800)
                if [[ "$1" =~ ^([0-9]+)h$ ]]; then
                    PARSED_MAX_AGE=$((BASH_REMATCH[1] * 3600))
                elif [[ "$1" =~ ^([0-9]+)d$ ]]; then
                    PARSED_MAX_AGE=$((BASH_REMATCH[1] * 86400))
                elif [[ "$1" =~ ^[0-9]+$ ]]; then
                    PARSED_MAX_AGE="$1"
                else
                    echo -e "${RED}❌ Invalid --max-age value: '$1' (expected: 48h, 2d, or seconds)${NC}" >&2
                    exit 1
                fi
                # Validate it's a positive number
                if [[ ! "$PARSED_MAX_AGE" =~ ^[0-9]+$ ]] || [[ "$PARSED_MAX_AGE" -le 0 ]]; then
                    echo -e "${RED}❌ Invalid --max-age value: '$1' (must be positive integer)${NC}" >&2
                    exit 1
                fi
                MAX_AGE="$PARSED_MAX_AGE"
                shift
            else
                echo -e "${RED}❌ --max-age requires a value (e.g., 48h, 2d, or seconds)${NC}" >&2
                exit 1
            fi
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --verbose         Show detailed output"
            echo "  --max-age AGE     Max age for stale worktrees (default: 48h)"
            echo "                    Formats: 48h, 2d, or seconds"
            echo ""
            echo "Environment:"
            echo "  DX_GC_MAX_AGE     Default max age in seconds (override with --max-age)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose] [--max-age AGE]"
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

# Check if a worktree has uncommitted changes
is_worktree_dirty() {
    local wt_path="$1"
    # Check for both staged and unstaged changes, and untracked files
    local status
    status=$(git -C "$wt_path" status --porcelain=v1 2>/dev/null | grep -v "^$" || true)
    [[ -n "$status" ]]
}

# Get file mtime in seconds (cross-platform: macOS and Linux)
# macOS: stat -f %m (seconds since epoch)
# Linux: stat -c %Y (seconds since epoch)
get_file_mtime() {
    local file="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f %m "$file" 2>/dev/null || echo "0"
    else
        stat -c %Y "$file" 2>/dev/null || echo "0"
    fi
}

# Get worktree age in seconds (based on most recent file mtime, NOT commit time)
# This is more accurate for detecting active WIP on old branches
get_worktree_age_seconds() {
    local wt_path="$1"
    local now_ts
    now_ts=$(date +%s)

    # For dirty worktrees, check git index modification time
    # This is a fast proxy for "recently edited" that works cross-platform
    local newest_file_ts=0

    # Check .git/index (staged changes) - fast and accurate for dirty state
    local git_index="$wt_path/.git/index"
    if [[ -f "$git_index" ]]; then
        newest_file_ts=$(get_file_mtime "$git_index")
    fi

    # Also check worktree directory mtime (updated when files inside change)
    local wt_dir_mtime
    wt_dir_mtime=$(get_file_mtime "$wt_path")
    if [[ "$wt_dir_mtime" -gt "$newest_file_ts" ]]; then
        newest_file_ts="$wt_dir_mtime"
    fi

    # Fallback to commit time if no valid mtime found
    if [[ -z "$newest_file_ts" || "$newest_file_ts" == "0" ]]; then
        newest_file_ts=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null || echo "0")
    fi

    echo $((now_ts - newest_file_ts))
}

# Check if worktree is stale (older than MAX_AGE)
is_worktree_stale() {
    local wt_path="$1"
    local age
    age=$(get_worktree_age_seconds "$wt_path")
    [[ $age -gt $MAX_AGE ]]
}

# Evacuate dirty worktree to a rescue branch
evacuate_dirty_worktree() {
    local wt_path="$1"
    local wt_branch="$2"
    local repo_path="$3"

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local rescue_branch="rescue/${wt_branch:-unknown}-$timestamp"

    echo "🚨 Evacuating dirty worktree: $wt_path" >&2

    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Would create rescue branch: $rescue_branch" >&2
        return 0
    fi

    # Create rescue branch from current state
    # Use --no-track to avoid setting upstream
    if ! git -C "$wt_path" checkout -b "$rescue_branch" --no-track 2>/dev/null; then
        # If checkout fails, we cannot safely evacuate - abort
        error "  Failed to create rescue branch in worktree - aborting evacuation" >&2
        return 1
    fi

    # Stage all changes including untracked
    git -C "$wt_path" add -A 2>/dev/null || true

    # Commit if there are changes
    # Use --no-verify to bypass commit hooks (rescue operation, not user commit)
    if git -C "$wt_path" diff --cached --quiet 2>/dev/null; then
        log "  No changes to commit in evacuation" >&2
    else
        if ! git -C "$wt_path" commit --no-verify -m "evacuate: dirty worktree rescue $timestamp" 2>/dev/null; then
            error "  Failed to commit evacuation changes - aborting" >&2
            # Switch back to original branch to avoid leaving user on rescue branch
            git -C "$wt_path" checkout "$wt_branch" 2>/dev/null || true
            return 1
        fi
    fi

    # Push rescue branch from worktree's current state
    if ! git -C "$wt_path" push origin "$rescue_branch" 2>/dev/null; then
        warn "  Failed to push rescue branch: $rescue_branch" >&2
        # Switch back to original branch
        git -C "$wt_path" checkout "$wt_branch" 2>/dev/null || true
        return 1
    fi

    success "  Evacuated to: $rescue_branch" >&2
    # Switch back to original branch before return
    git -C "$wt_path" checkout "$wt_branch" 2>/dev/null || true
    return 0
}

update_heartbeat() {
    local heartbeat="$HOME/.dx-state/HEARTBEAT.md"
    [[ -f "$heartbeat" ]] || return 0

    local section_start="### Worktree Health"
    local status="$1"  # OK, WARNING, ERROR
    local details="$2"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$section_start" -v status="$status" -v details="$details" -v now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
        BEGIN { in_section=0; printed=0; gsub(/\\n/, "\n", details) }
        $0 == start {
            in_section=1; printed=1
            print start
            print "<!-- Updated by worktree-gc-v8.sh -->"
            print "Status: " status
            print "Last run: " now
            if (details != "") print details
            print ""
            next
        }
        /^### / && in_section { in_section=0 }
        !in_section { print }
    ' "$heartbeat" > "$tmpfile" && mv "$tmpfile" "$heartbeat"
}

process_worktree() {
    local wt_path="$1"
    local wt_head="$2"
    local wt_branch="$3"
    local wt_is_detached="$4"
    local is_main="$5"
    local repo_path="$6"

    if [[ "$is_main" == true ]]; then
        log "  Skipping main worktree: $wt_path" >&2
        return 0
    fi

    # Check if worktree is dirty BEFORE any prune decision
    local is_dirty=false
    if [[ -d "$wt_path" ]]; then
        if is_worktree_dirty "$wt_path"; then
            is_dirty=true
        fi
    fi

    # Check if worktree is stale
    local is_stale=false
    if [[ -d "$wt_path" ]]; then
        if is_worktree_stale "$wt_path"; then
            is_stale=true
        fi
    fi

    local should_prune=false
    local reason=""

    # Case 1: Path doesn't exist on disk
    if [[ ! -d "$wt_path" ]]; then
        should_prune=true
        reason="Path missing from disk"
    fi

    # Case 2: Branch merged into origin/master AND not dirty
    if [[ "$should_prune" == false && -n "$wt_branch" ]]; then
        if git merge-base --is-ancestor "$wt_head" origin/master 2>/dev/null; then
            if [[ "$is_dirty" == true ]]; then
                # P0 SAFETY: Never auto-prune dirty worktrees
                warn "  Worktree $wt_path is MERGED but DIRTY - skipping auto-prune" >&2
                if [[ "$is_stale" == true ]]; then
                    warn "  Stale dirty worktree (>$(($MAX_AGE / 3600))h) - manual review or evacuate" >&2
                fi
            else
                should_prune=true
                reason="Branch '$wt_branch' merged into origin/master (clean)"
            fi
        fi
    fi

    # Case 3: Detached HEAD merged into origin/master AND not dirty
    if [[ "$should_prune" == false && "$wt_is_detached" == true ]]; then
        if git merge-base --is-ancestor "$wt_head" origin/master 2>/dev/null; then
            if [[ "$is_dirty" == true ]]; then
                # P0 SAFETY: Never auto-prune dirty worktrees
                warn "  Worktree $wt_path has DETACHED merged HEAD but is DIRTY - skipping auto-prune" >&2
            else
                should_prune=true
                reason="Detached HEAD ($wt_head) merged into origin/master (clean)"
            fi
        else
            log "  Worktree $wt_path has unmerged detached HEAD: $wt_head" >&2
        fi
    fi

    # Case 4: Stale dirty worktree - evacuate then remove
    if [[ "$is_dirty" == true && "$is_stale" == true ]]; then
        local age_h
        age_h=$(($(get_worktree_age_seconds "$wt_path") / 3600))
        info "  Stale dirty worktree: $wt_path (${age_h}h old)" >&2

        if evacuate_dirty_worktree "$wt_path" "$wt_branch" "$repo_path"; then
            # After successful evacuation, safe to remove
            should_prune=true
            reason="Evacuated stale dirty worktree (${age_h}h old)"
        else
            error "  Failed to evacuate $wt_path - keeping worktree" >&2
            return 0
        fi
    fi

    if [[ "$should_prune" == true ]]; then
        echo "♻️  Pruning worktree: $wt_path ($reason)" >&2
        if [[ "$DRY_RUN" == false ]]; then
            # Final safety check: refuse to force-remove dirty worktrees
            if [[ -d "$wt_path" ]] && is_worktree_dirty "$wt_path"; then
                error "  SAFETY: Refusing to force-remove dirty worktree: $wt_path" >&2
                error "  This should not happen - evacuation should have run first" >&2
                return 0
            fi
            git worktree remove "$wt_path" --force >/dev/null 2>&1 || true
            rm -rf "$wt_path" 2>/dev/null || true
            success "Pruned $wt_path" >&2
            return 1 # Signify pruned
        else
            log "  [DRY-RUN] Would remove $wt_path" >&2
            return 0
        fi
    else
        local status_parts=()
        [[ "$is_dirty" == true ]] && status_parts+=("dirty")
        [[ "$is_stale" == true ]] && status_parts+=("stale")
        local status="${status_parts[*]:-clean}"
        log "  Keeping worktree: $wt_path (branch: $wt_branch, $status)" >&2
        return 0
    fi
}

process_repo() {
    local repo="$1"
    local repo_path="$HOME/$repo"
    local pruned_count=0
    local total_count=0
    
    log "\n📁 Processing repo: $repo" >&2

    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository, skipping" >&2
        echo "0 0"
        return 0
    fi
    
    cd "$repo_path"
    
    # Fetch origin master to ensure merge-base is accurate
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin master --quiet || { warn "$repo: Failed to fetch origin master" >&2; }
    fi
    
    local path=""
    local head=""
    local branch=""
    local is_detached=false
    local count=0
    
    while IFS= read -r line; do
        if [[ $line =~ ^worktree\ (.*) ]]; then
            if [[ -n "$path" ]]; then
                local is_main=false
                if [[ $count -eq 0 ]]; then is_main=true; fi
                total_count=$((total_count + 1))
                if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main" "$repo_path"; then
                    pruned_count=$((pruned_count + 1))
                fi
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

    if [[ -n "$path" ]]; then
        local is_main=false
        if [[ $count -eq 0 ]]; then is_main=true; fi
        total_count=$((total_count + 1))
        if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main" "$repo_path"; then
            pruned_count=$((pruned_count + 1))
        fi
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        git worktree prune
    fi
    
    echo "$total_count $pruned_count"
}

main() {
    echo "🧹 DX Worktree GC V8.1"
    echo "====================="

    local max_age_h=$((MAX_AGE / 3600))
    echo "Max age threshold: ${max_age_h}h"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    
    local grand_total=0
    local grand_pruned=0
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        read -r t p < <(process_repo "$repo")
        grand_total=$((grand_total + t))
        grand_pruned=$((grand_pruned + p))
    done
    
    update_heartbeat "OK" "Count: $grand_total\nPruned: $grand_pruned"
}

main "$@"
