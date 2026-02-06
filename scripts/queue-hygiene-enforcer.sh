#!/usr/bin/env bash
#
# scripts/queue-hygiene-enforcer.sh (V8.0)
#
# Purpose: Deterministic closed-loop PR queue management.
# Cron schedule: every 4 hours (*/4)
# Bead: bd-gdlr
#
# Invariants:
# 1. ONLY runs if DX_CONTROLLER=1.
# 2. Idempotent.
# 3. Best-effort PR cleanup and branch updates.

set -euo pipefail

# Configuration
REPOS=(
    "stars-end/agent-skills"
    "stars-end/prime-radiant-ai"
    "stars-end/affordabot"
    "stars-end/llm-common"
)

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

# DX_CONTROLLER guard
if [[ "${DX_CONTROLLER:-0}" != "1" ]]; then
    echo "ENFORCER SKIP: DX_CONTROLLER not set (this VM is not the controller)"
    exit 0
fi

update_heartbeat() {
    local heartbeat="$HOME/.dx-state/HEARTBEAT.md"
    [[ -f "$heartbeat" ]] || return 0

    local section_start="### PR Queue"
    local status="$1"  # OK, WARNING, ERROR
    local details="$2"  # e.g., "Blocked: 1\nQueued: 5"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$section_start" -v status="$status" -v details="$details" -v now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
        BEGIN { in_section=0; printed=0 }
        $0 == start {
            in_section=1; printed=1
            print start
            print "<!-- Updated by script -->"
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

get_hours_behind() {
    local updated_at="$1"
    local now_epoch
    now_epoch=$(date -u +%s)
    local pr_epoch
    pr_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null || date -d "$updated_at" +%s 2>/dev/null)
    echo $(( (now_epoch - pr_epoch) / 3600 ))
}

process_repo() {
    local repo="$1"
    local actions_taken=0
    local blocked=0
    local queued=0
    
    log "\n🔍 Checking PR queue for: $repo"
    
    # Query open PRs with autoMerge enabled
    local prs
    prs=$(gh pr list --repo "$repo" --json number,title,mergeStateStatus,autoMergeRequest,updatedAt,headRefName --jq '.[] | select(.autoMergeRequest != null)' 2>/dev/null || echo "")
    
    if [[ -z "$prs" ]]; then
        log "No PRs with autoMerge enabled found."
        return 0
    fi

    while read -r pr; do
        if [[ -z "$pr" ]]; then continue; fi
        
        local number
        number=$(echo "$pr" | jq -r '.number')
        local status
        status=$(echo "$pr" | jq -r '.mergeStateStatus')
        local updated_at
        updated_at=$(echo "$pr" | jq -r '.updatedAt')
        local head_ref
        head_ref=$(echo "$pr" | jq -r '.headRefName')
        
        queued=$((queued + 1))
        
        local hours_behind
        hours_behind=$(get_hours_behind "$updated_at")
        
        # Rule 1: DIRTY → disable auto-merge immediately
        if [[ "$status" == "DIRTY" ]]; then
            echo "🚨 Rule 1: #$number is DIRTY. Disabling auto-merge."
            blocked=$((blocked + 1))
            if [[ "$DRY_RUN" == false ]]; then
                gh pr merge --disable-auto --repo "$repo" "$number"
                actions_taken=$((actions_taken + 1))
            fi
            continue # Move to next PR
        fi
        
        # Rule 2: BEHIND > 6 hours → update branch
        if [[ "$status" == "BEHIND" ]]; then
            if [[ "$hours_behind" -gt 6 ]]; then
                echo "🔄 Rule 2: #$number is BEHIND (${hours_behind}h). Updating branch."
                if [[ "$DRY_RUN" == false ]]; then
                    gh api "repos/$repo/pulls/$number/update-branch" -X PUT 2>/dev/null || true
                    actions_taken=$((actions_taken + 1))
                fi
            fi
        fi
        
        # Rule 3: Rescue branches with 0 commits ahead → delete
        if [[ "$head_ref" == rescue-* || "$head_ref" == stash-rescue-* ]]; then
            local ahead
            ahead=$(gh api "repos/$repo/compare/master...$head_ref" --jq '.ahead_by' 2>/dev/null || echo "0")
            if [[ "$ahead" -eq 0 ]]; then
                echo "🗑️  Rule 3: #$number is an empty rescue PR. Closing and deleting branch."
                if [[ "$DRY_RUN" == false ]]; then
                    gh pr close --repo "$repo" "$number" --delete-branch
                    actions_taken=$((actions_taken + 1))
                fi
                continue
            fi
        fi
        
        # Rule 4: DIRTY or BEHIND > 72 hours → disable auto-merge
        if [[ "$status" == "DIRTY" || "$status" == "BEHIND" ]]; then
            if [[ "$hours_behind" -gt 72 ]]; then
                echo "🛑 Rule 4: #$number is stuck (${hours_behind}h). Disabling auto-merge."
                blocked=$((blocked + 1))
                if [[ "$DRY_RUN" == false ]]; then
                    gh pr merge --disable-auto --repo "$repo" "$number"
                    actions_taken=$((actions_taken + 1))
                fi
                continue
            fi
        fi
        
    done <<< "$prs"
    
    echo "$actions_taken $blocked $queued"
}

main() {
    echo "🏗️  DX Queue Hygiene Enforcer V8"
    echo "================================"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi
    
    local total_actions=0
    local total_blocked=0
    local total_queued=0
    
    for repo in "${REPOS[@]}"; do
        read -r actions blocked queued < <(process_repo "$repo")
        total_actions=$((total_actions + actions))
        total_blocked=$((total_blocked + blocked))
        total_queued=$((total_queued + queued))
    done
    
    if [[ "$total_actions" -gt 0 ]]; then
        echo "ENFORCER: $total_actions actions taken ($total_blocked blocked, $total_queued queued)"
        update_heartbeat "OK" "Blocked: $total_blocked\nQueued: $total_queued\nActions taken: $total_actions"
    else
        echo "ENFORCER OK: 0 actions needed"
        update_heartbeat "OK" "Blocked: $total_blocked\nQueued: $total_queued\nActions taken: 0"
    fi
}

main "$@"
