#!/usr/bin/env bash
# dx-bootstrap.sh - Session start warning shim for canonical repo detection
# Deprecated as a bootstrap surface: session-start hooks must stay warning-only.

CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")

# Detect if we're in a canonical repo
IS_CANONICAL=false
CURRENT_DIR="${PWD}"

for repo in "${CANONICAL_REPOS[@]}"; do
    if [[ "$CURRENT_DIR" =~ /$repo(/|$) ]] && [[ ! "$CURRENT_DIR" =~ /tmp/agents/ ]] && [[ ! "$CURRENT_DIR" =~ /private/tmp/agents/ ]]; then
        IS_CANONICAL=true
        CANONICAL_REPO="$repo"
        break
    fi
done

if [[ "$IS_CANONICAL" == "true" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  CANONICAL REPOSITORY DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  You are in: $CANONICAL_REPO (canonical clone)"
    echo "  This repo auto-resets when dirty > 48h."
    echo ""
    echo "  ✅ Use worktrees for development:"
    echo "     dx-worktree create <beads-id> $CANONICAL_REPO"
    echo "     cd /tmp/agents/<beads-id>/$CANONICAL_REPO"
    echo ""
    echo "  ❌ Do NOT commit directly here (pre-commit hook will block)"
    echo ""
    echo "  📖 See: ~/agent-skills/AGENTS.md for full workflow"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi
