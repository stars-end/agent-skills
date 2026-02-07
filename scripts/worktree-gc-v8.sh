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
    
    if [[ "$is_main" == true ]]; then
        log "  Skipping main worktree: $wt_path" >&2
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
            warn "  Worktree $wt_path has unmerged detached HEAD: $wt_head" >&2
        fi
    fi
    
    if [[ "$should_prune" == true ]]; then
        echo "♻️  Pruning worktree: $wt_path ($reason)" >&2
        if [[ "$DRY_RUN" == false ]]; then
            git worktree remove "$wt_path" --force >/dev/null 2>&1 || true
            rm -rf "$wt_path" 2>/dev/null || true
            success "Pruned $wt_path" >&2
            return 1 # Signify pruned
        else
            log "  [DRY-RUN] Would remove $wt_path" >&2
            return 0
        fi
    else
        log "  Keeping worktree: $wt_path (branch: $wt_branch)" >&2
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
                if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main"; then
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
        if ! process_worktree "$path" "$head" "$branch" "$is_detached" "$is_main"; then
            pruned_count=$((pruned_count + 1))
        fi
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        git worktree prune
    fi
    
    echo "$total_count $pruned_count"
}

main() {
    echo "🧹 DX Worktree GC V8"
    echo "===================="
    
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
