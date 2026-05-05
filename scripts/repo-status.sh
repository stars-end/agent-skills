#!/bin/bash
# repo-status.sh - Quick health check of canonical repos

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

ISSUES=0

# Check for sync alert
if [[ -f ~/logs/SYNC_ALERT ]]; then
    echo -e "${RED}🚨 SYNC FAILED - check ~/logs/canonical-sync.log${RESET}"
    ISSUES=$((ISSUES + 1))
fi

# Check for healing events (agents bypassed hooks)
if [[ -f ~/logs/canonical-sync.log ]]; then
    HEALING_EVENTS=$(grep -c "Healing" ~/logs/canonical-sync.log 2>/dev/null || echo 0)
    if [[ $HEALING_EVENTS -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  $HEALING_EVENTS healing events detected (agents bypassed pre-commit hooks)${RESET}"
        echo "   Last 3 events:"
        grep "Healing" ~/logs/canonical-sync.log | tail -3 | sed 's/^/   /'
        echo "   Full log: tail ~/logs/canonical-sync.log"
        ISSUES=$((ISSUES + 1))
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"

for repo in agent-skills prime-radiant-ai affordabot llm-common bd-symphony; do
    cd ~/$repo 2>/dev/null || continue
    EXPECTED_BRANCH="$(canonical_repo_branch "$repo")"
    
    BRANCH=$(git branch --show-current)
    
    # Check if on canonical branch
    if [[ "$BRANCH" != "$EXPECTED_BRANCH" ]]; then
        echo -e "${YELLOW}⚠️  $repo on $BRANCH (expected $EXPECTED_BRANCH)${RESET}"
        ISSUES=$((ISSUES + 1))
    fi
    
    # Check if behind
    BEHIND=$(git rev-list --count HEAD..origin/$EXPECTED_BRANCH 2>/dev/null || echo 0)
    if [[ $BEHIND -gt 5 ]]; then
        echo -e "${YELLOW}⚠️  $repo $BEHIND commits behind${RESET}"
        ISSUES=$((ISSUES + 1))
    fi
    
    # Check for dirty files
    DIRTY=$(git status --porcelain | wc -l)
    if [[ $DIRTY -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  $repo has $DIRTY dirty files${RESET}"
        ISSUES=$((ISSUES + 1))
    fi
done

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✅ All canonical repos healthy${RESET}"
fi

exit 0
