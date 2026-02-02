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
    ((ISSUES++))
fi

for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo 2>/dev/null || continue
    
    BRANCH=$(git branch --show-current)
    
    # Check if on master
    if [[ "$BRANCH" != "master" ]]; then
        echo -e "${YELLOW}⚠️  $repo on $BRANCH (expected master)${RESET}"
        ((ISSUES++))
    fi
    
    # Check if behind
    BEHIND=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo 0)
    if [[ $BEHIND -gt 5 ]]; then
        echo -e "${YELLOW}⚠️  $repo $BEHIND commits behind${RESET}"
        ((ISSUES++))
    fi
    
    # Check for dirty files
    DIRTY=$(git status --porcelain | wc -l)
    if [[ $DIRTY -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  $repo has $DIRTY dirty files${RESET}"
        ((ISSUES++))
    fi
done

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✅ All canonical repos healthy${RESET}"
fi

exit 0
