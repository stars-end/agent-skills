#!/bin/bash
# canonical-repo-reminder.sh - Session start reminder for canonical repos
# Source this from your shell startup or session hooks

# Only show if we're in a canonical repo
CURRENT_DIR=$(pwd)
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common" "bd-symphony")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"

IS_CANONICAL=false
CURRENT_REPO=""
for repo in "${CANONICAL_REPOS[@]}"; do
    if [[ "$CURRENT_DIR" =~ /$repo(/|$) ]] && [[ ! "$CURRENT_DIR" =~ /tmp/agents/ ]]; then
        IS_CANONICAL=true
        CURRENT_REPO="$repo"
        break
    fi
done

if [[ "$IS_CANONICAL" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  CANONICAL REPOSITORY REMINDER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  You are in a READ-ONLY canonical repository."
    echo "  This directory auto-resets to origin/$(canonical_repo_branch "$CURRENT_REPO") daily at 3am."
    echo ""
    echo "  ✅ Use worktrees for development:"
    echo "     dx-worktree create bd-xxxx <repo-name>"
    echo "     cd /tmp/agents/bd-xxxx/<repo-name>"
    echo ""
    echo "  ❌ Do NOT commit directly here (pre-commit hook will block)"
    echo ""
    echo "  📖 See: ~/agent-skills/AGENTS.md for full workflow"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi
