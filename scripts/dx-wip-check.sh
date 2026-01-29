#!/usr/bin/env bash
# dx-wip-check.sh
# Check for unmerged WIP auto-checkpoint branches
# Run as part of dx-check

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo "=== WIP Auto-Checkpoint Branches ==="

# Find all wip/auto/ branches
WIP_BRANCHES=$(git branch -a | grep -E "wip/auto/" | sed 's/[* ] //' | sed 's|remotes/origin/||' | sort -u)

if [[ -z "$WIP_BRANCHES" ]]; then
    info "No WIP auto-checkpoint branches found"
    exit 0
fi

FOUND_UNMERGED=0

for branch in $WIP_BRANCHES; do
    # Check if branch commits are in master
    BRANCH_COMMITS=$(git log origin/master..origin/"$branch" --oneline 2>/dev/null || git log master.."$branch" --oneline 2>/dev/null)

    if [[ -n "$BRANCH_COMMITS" ]]; then
        warn "Unmerged WIP branch: $branch"
        echo "$BRANCH_COMMITS" | head -3
        echo ""
        FOUND_UNMERGED=1
    fi
done

if [[ $FOUND_UNMERGED -eq 1 ]]; then
    echo ""
    warn "Action required:"
    echo "  1. Review WIP branches above"
    echo "  2. Merge or cherry-pick needed commits to master"
    echo "  3. Delete merged WIP branches: git branch -d <branch>"
    echo ""
else
    info "All WIP commits are merged to master"
fi
