#!/usr/bin/env bash
#
# scripts/queue-hygiene-enforcer.sh (V8.6)
#
# Purpose: Deterministic policy enforcement for PR queue hygiene.
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
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

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
        echo -e "$1" >&2
    fi
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
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
        BEGIN { in_section=0; printed=0; gsub(/\\n/, "\n", details) }
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

process_repo() {
    local repo="$1"
    local actions_taken=0
    local blocked=0
    local queued=0
    
    log "\n🔍 Checking PR queue for: $repo"
    
    # Query open PRs with autoMerge enabled
    local prs
    prs=$(gh pr list --repo "$repo" --json number,title,mergeStateStatus,autoMergeRequest,updatedAt,headRefName | jq -c ".[] | select(.autoMergeRequest != null)" 2>/dev/null || echo "")
    
    if [[ -z "$prs" ]]; then
        log "No PRs with autoMerge enabled found."
        echo "0 0 0"
        return 0
    fi

    while read -r pr; do
        if [[ -z "$pr" ]]; then continue; fi
        
        local number
        number=$(echo "$pr" | jq -r ".number")
        local head_ref
        head_ref=$(echo "$pr" | jq -r ".headRefName")
        
        queued=$((queued + 1))

        # Rule 1: Auto-merge is prohibited by policy. Disable always.
        echo "🚫 Rule 1: #$number has auto-merge enabled. Disabling (policy)." >&2
        blocked=$((blocked + 1))
        if [[ "$DRY_RUN" == false ]]; then
            gh pr merge --disable-auto --repo "$repo" "$number" >&2
            actions_taken=$((actions_taken + 1))
        fi
        
        # Rule 2: Empty rescue PRs can be closed and branch deleted.
        if [[ "$head_ref" == rescue-* || "$head_ref" == stash-rescue-* ]]; then
            local ahead
            ahead=$(gh api "repos/$repo/compare/master...$head_ref" --jq ".ahead_by" 2>/dev/null || echo "0")
            if [[ "$ahead" -eq 0 ]]; then
                echo "🗑️  Rule 2: #$number is an empty rescue PR. Closing and deleting branch." >&2
                if [[ "$DRY_RUN" == false ]]; then
                    gh pr close --repo "$repo" "$number" --delete-branch >&2
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
