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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"

# Colors for output (defined early for validation functions)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common" "bd-symphony")
WORKTREE_BASE="${DX_WORKTREE_BASE:-$HOME/.dx/worktrees}"
LEGACY_WORKTREE_BASE="/tmp/agents"

# Default max age for stale worktrees (48 hours in seconds)
DEFAULT_MAX_AGE=$((48 * 3600))
DEFAULT_PROTECT_TZ="America/Los_Angeles"
DEFAULT_PROTECT_START_HOUR=5
DEFAULT_PROTECT_END_HOUR=22

# Validate MAX_AGE value (used for both env var and CLI)
validate_max_age() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo -e "${RED}❌ Invalid MAX_AGE: '$value' (must be positive integer)${NC}" >&2
        exit 1
    fi
    echo "$value"
}

validate_hour() {
    local value="$1"
    local name="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 0 ]] || [[ "$value" -gt 23 ]]; then
        echo -e "${RED}❌ Invalid $name: '$value' (must be an integer from 0-23)${NC}" >&2
        exit 1
    fi
    echo "$value"
}

# Set MAX_AGE from env or default (validate if env was set)
MAX_AGE="${DX_GC_MAX_AGE:-$DEFAULT_MAX_AGE}"
if [[ -n "${DX_GC_MAX_AGE:-}" ]]; then
    MAX_AGE=$(validate_max_age "$DX_GC_MAX_AGE")
fi
GC_PROTECT_TZ="${DX_GC_PROTECT_TZ:-$DEFAULT_PROTECT_TZ}"
GC_PROTECT_START_HOUR="${DX_GC_PROTECT_START_HOUR:-$DEFAULT_PROTECT_START_HOUR}"
GC_PROTECT_END_HOUR="${DX_GC_PROTECT_END_HOUR:-$DEFAULT_PROTECT_END_HOUR}"
TMUX_ATTACHED_PATHS=$'\n'
TMUX_ATTACHED_PATHS_INITIALIZED=false

# Parse arguments
DRY_RUN=false
VERBOSE=false
IGNORE_HOURS_GATE=false

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
        --ignore-hours-gate)
            IGNORE_HOURS_GATE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --verbose         Show detailed output"
            echo "  --max-age AGE     Max age for stale worktrees (default: 48h)"
            echo "                    Formats: 48h, 2d, or seconds"
            echo "  --ignore-hours-gate  Run even during protected working hours"
            echo ""
            echo "Environment:"
            echo "  DX_GC_MAX_AGE     Default max age in seconds (override with --max-age)"
            echo "  DX_GC_PROTECT_TZ  Protected-hours timezone (default: America/Los_Angeles)"
            echo "  DX_GC_PROTECT_START_HOUR  Inclusive hour for protected window start (default: 5)"
            echo "  DX_GC_PROTECT_END_HOUR    Exclusive hour for protected window end (default: 22)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose] [--max-age AGE] [--ignore-hours-gate]"
            exit 1
            ;;
    esac
done

GC_PROTECT_START_HOUR=$(validate_hour "$GC_PROTECT_START_HOUR" "DX_GC_PROTECT_START_HOUR")
GC_PROTECT_END_HOUR=$(validate_hour "$GC_PROTECT_END_HOUR" "DX_GC_PROTECT_END_HOUR")

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

format_hour_range() {
    local start="$1"
    local end="$2"
    printf "%02d:00-%02d:00" "$start" "$end"
}

is_in_protected_hours() {
    local hour_raw
    hour_raw=$(TZ="$GC_PROTECT_TZ" date +%H 2>/dev/null || date +%H)
    local hour=$((10#$hour_raw))
    local start="$GC_PROTECT_START_HOUR"
    local end="$GC_PROTECT_END_HOUR"

    if (( start == end )); then
        return 1
    fi
    if (( start < end )); then
        (( hour >= start && hour < end ))
        return
    fi
    (( hour >= start || hour < end ))
}

canonicalize_dir_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" 2>/dev/null && pwd -P) || echo "$path"
    else
        echo "$path"
    fi
}

load_tmux_attached_paths() {
    if [[ "$TMUX_ATTACHED_PATHS_INITIALIZED" == true ]]; then
        return
    fi
    TMUX_ATTACHED_PATHS_INITIALIZED=true

    command -v tmux >/dev/null 2>&1 || return
    tmux list-sessions >/dev/null 2>&1 || return

    local attached_ids
    attached_ids="$(
        tmux list-sessions -F '#{session_id} #{session_attached}' 2>/dev/null \
            | awk '$2+0 > 0 {print $1}'
    )"
    [[ -n "$attached_ids" ]] || return

    local attached_set=$'\n'"$attached_ids"$'\n'
    local pane_sid pane_dead pane_path pane_real
    while IFS=$'\t' read -r pane_sid pane_dead pane_path; do
        [[ -n "$pane_sid" && -n "$pane_path" ]] || continue
        [[ "$pane_dead" == "1" ]] && continue
        [[ "$attached_set" == *$'\n'"$pane_sid"$'\n'* ]] || continue
        pane_real="$(canonicalize_dir_path "$pane_path")"
        if [[ "$TMUX_ATTACHED_PATHS" != *$'\n'"$pane_real"$'\n'* ]]; then
            TMUX_ATTACHED_PATHS+="$pane_real"$'\n'
        fi
    done < <(tmux list-panes -a -F '#{session_id}\t#{pane_dead}\t#{pane_current_path}' 2>/dev/null || true)
}

worktree_has_attached_tmux_path() {
    local wt_path="$1"
    [[ -d "$wt_path" ]] || return 1

    load_tmux_attached_paths
    [[ "$TMUX_ATTACHED_PATHS" != $'\n' ]] || return 1

    local wt_real
    wt_real="$(canonicalize_dir_path "$wt_path")"

    local pane_path
    while IFS= read -r pane_path; do
        [[ -n "$pane_path" ]] || continue
        if [[ "$pane_path" == "$wt_real" || "$pane_path" == "$wt_real/"* ]]; then
            return 0
        fi
    done <<< "$TMUX_ATTACHED_PATHS"
    return 1
}

is_managed_worktree_path() {
    local wt_path="$1"
    if [[ "$wt_path" == "$WORKTREE_BASE/"* || "$wt_path" == "$WORKTREE_BASE" ]]; then
        return 0
    fi
    if [[ "$wt_path" == "$LEGACY_WORKTREE_BASE/"* || "$wt_path" == "$LEGACY_WORKTREE_BASE" ]]; then
        return 0
    fi
    return 1
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

# Get worktree age in seconds (based on most recent activity, NOT commit time)
# This is more accurate for detecting active WIP on old branches
get_worktree_age_seconds() {
    local wt_path="$1"
    local now_ts
    now_ts=$(date +%s)

    local newest_file_ts=0

    # Method 1: Check git index mtime (works for both regular repos and worktrees)
    # For worktrees, .git is a file pointer, so we use git rev-parse --git-dir
    local git_dir
    git_dir=$(git -C "$wt_path" rev-parse --git-dir 2>/dev/null)
    if [[ -n "$git_dir" && -f "$git_dir/index" ]]; then
        local index_mtime
        index_mtime=$(get_file_mtime "$git_dir/index")
        if [[ "$index_mtime" -gt "$newest_file_ts" ]]; then
            newest_file_ts="$index_mtime"
        fi
    fi

    # Method 2: Sample a few recently modified tracked files
    # This catches active editing even if index hasn't been updated.
    local sample_count=0
    while IFS= read -r file; do
        if [[ -e "$wt_path/$file" ]]; then
            local file_mtime
            file_mtime=$(get_file_mtime "$wt_path/$file")
            if [[ "$file_mtime" -gt "$newest_file_ts" ]]; then
                newest_file_ts="$file_mtime"
            fi
            ((sample_count++))
            # Only check first 10 modified files for performance
            [[ $sample_count -ge 10 ]] && break
        fi
    done < <(git -C "$wt_path" diff --name-only HEAD 2>/dev/null | head -10)

    # Method 3: Sample untracked files.
    # This avoids misclassifying active untracked-only WIP as stale.
    sample_count=0
    while IFS= read -r file; do
        if [[ -e "$wt_path/$file" ]]; then
            local file_mtime
            file_mtime=$(get_file_mtime "$wt_path/$file")
            if [[ "$file_mtime" -gt "$newest_file_ts" ]]; then
                newest_file_ts="$file_mtime"
            fi
            ((sample_count++))
            [[ $sample_count -ge 10 ]] && break
        fi
    done < <(git -C "$wt_path" ls-files --others --exclude-standard 2>/dev/null | head -10)

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
    # NOTE: Redirect BOTH stdout and stderr to avoid polluting process_repo output
    if ! git -C "$wt_path" checkout -b "$rescue_branch" --no-track >/dev/null 2>&1; then
        # If checkout fails, we cannot safely evacuate - abort
        error "  Failed to create rescue branch in worktree - aborting evacuation" >&2
        return 1
    fi

    # Stage all changes including untracked
    git -C "$wt_path" add -A >/dev/null 2>&1 || true

    # Commit if there are changes
    # Use --no-verify to bypass commit hooks (rescue operation, not user commit)
    if git -C "$wt_path" diff --cached --quiet >/dev/null 2>&1; then
        log "  No changes to commit in evacuation" >&2
    else
        if ! git -C "$wt_path" commit --no-verify -m "evacuate: dirty worktree rescue $timestamp" >/dev/null 2>&1; then
            error "  Failed to commit evacuation changes - aborting" >&2
            # Switch back to original branch to avoid leaving user on rescue branch
            git -C "$wt_path" checkout "$wt_branch" >/dev/null 2>&1 || true
            return 1
        fi
    fi

    # Push rescue branch from worktree's current state
    if ! git -C "$wt_path" push origin "$rescue_branch" >/dev/null 2>&1; then
        warn "  Failed to push rescue branch: $rescue_branch" >&2
        # Switch back to original branch
        git -C "$wt_path" checkout "$wt_branch" >/dev/null 2>&1 || true
        return 1
    fi

    success "  Evacuated to: $rescue_branch" >&2
    # Switch back to original branch before return
    git -C "$wt_path" checkout "$wt_branch" >/dev/null 2>&1 || true
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
    local upstream_ref="${7:-origin/master}"

    if [[ "$is_main" == true ]]; then
        log "  Skipping main worktree: $wt_path" >&2
        return 0
    fi

    if ! is_managed_worktree_path "$wt_path"; then
        log "  Skipping non-managed worktree path: $wt_path" >&2
        return 0
    fi

    # Respect explicit session locks where present.
    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        if "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$wt_path" >/dev/null 2>&1; then
            log "  Keeping worktree: $wt_path (fresh session lock)" >&2
            return 0
        fi
    fi

    # Protect worktrees that are currently used by attached tmux sessions.
    if worktree_has_attached_tmux_path "$wt_path"; then
        log "  Keeping worktree: $wt_path (attached tmux pane cwd)" >&2
        if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
            "$SCRIPT_DIR/dx-session-lock.sh" touch "$wt_path" >/dev/null 2>&1 || true
        fi
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

    # Case 2: Branch merged into the repo's upstream branch AND clean AND stale
    if [[ "$should_prune" == false && -n "$wt_branch" ]]; then
        if git merge-base --is-ancestor "$wt_head" "$upstream_ref" 2>/dev/null; then
            if [[ "$is_dirty" == true ]]; then
                # P0 SAFETY: Never auto-prune dirty worktrees
                warn "  Worktree $wt_path is MERGED but DIRTY - skipping auto-prune" >&2
                if [[ "$is_stale" == true ]]; then
                    warn "  Stale dirty worktree (>$(($MAX_AGE / 3600))h) - manual review or evacuate" >&2
                fi
            else
                if [[ "$is_stale" == true ]]; then
                    should_prune=true
                    reason="Branch '$wt_branch' merged into $upstream_ref (clean + stale)"
                else
                    log "  Keeping merged clean worktree (not stale yet): $wt_path" >&2
                fi
            fi
        fi
    fi

    # Case 3: Detached HEAD merged into the repo's upstream branch AND clean AND stale
    if [[ "$should_prune" == false && "$wt_is_detached" == true ]]; then
        if git merge-base --is-ancestor "$wt_head" "$upstream_ref" 2>/dev/null; then
            if [[ "$is_dirty" == true ]]; then
                # P0 SAFETY: Never auto-prune dirty worktrees
                warn "  Worktree $wt_path has DETACHED merged HEAD but is DIRTY - skipping auto-prune" >&2
            else
                if [[ "$is_stale" == true ]]; then
                    should_prune=true
                    reason="Detached HEAD ($wt_head) merged into $upstream_ref (clean + stale)"
                else
                    log "  Keeping detached merged worktree (not stale yet): $wt_path" >&2
                fi
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
            if git worktree remove "$wt_path" --force >/dev/null 2>&1; then
                success "Pruned $wt_path" >&2
            else
                error "Failed to prune $wt_path via git worktree remove; leaving path intact" >&2
                return 0
            fi
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
    local canonical_branch upstream_ref
    canonical_branch="$(canonical_repo_branch "$repo")"
    upstream_ref="origin/$canonical_branch"
    
    log "\n📁 Processing repo: $repo" >&2

    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository, skipping" >&2
        echo "0 0"
        return 0
    fi
    
    cd "$repo_path"
    
    # Fetch the repo's canonical branch to ensure merge-base is accurate.
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin "$canonical_branch" --quiet || { warn "$repo: Failed to fetch $upstream_ref" >&2; }
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
                if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main" "$repo_path" "$upstream_ref"; then
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
        if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main" "$repo_path" "$upstream_ref"; then
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
    echo "Protected hours: $(format_hour_range "$GC_PROTECT_START_HOUR" "$GC_PROTECT_END_HOUR") $GC_PROTECT_TZ"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    if [[ "$IGNORE_HOURS_GATE" != true ]] && is_in_protected_hours; then
        local now_pt
        now_pt=$(TZ="$GC_PROTECT_TZ" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
        info "Skipping prune during protected hours ($(format_hour_range "$GC_PROTECT_START_HOUR" "$GC_PROTECT_END_HOUR") $GC_PROTECT_TZ); now=$now_pt"
        exit 0
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
