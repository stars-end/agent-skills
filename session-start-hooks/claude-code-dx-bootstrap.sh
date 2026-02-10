#!/usr/bin/env bash
#
# Claude Code SessionStart Hook: DX Bootstrap (V7.6)
#
# Installation:
#   mkdir -p .claude/hooks/SessionStart
#   cp ~/agent-skills/session-start-hooks/claude-code-dx-bootstrap.sh \
#      .claude/hooks/SessionStart/dx-bootstrap.sh
#   chmod +x .claude/hooks/SessionStart/dx-bootstrap.sh
#
# Purpose: Run dx-doctor check at session start to detect environment drift

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/.agent/skills}"
if [[ ! -d "$AGENTS_ROOT" ]]; then
    AGENTS_ROOT="$HOME/agent-skills"
fi

# Prefer the canonical cross-agent entrypoint if present.
if [[ -x "$AGENTS_ROOT/session-start-hooks/dx-bootstrap.sh" ]]; then
    exec "$AGENTS_ROOT/session-start-hooks/dx-bootstrap.sh"
fi

echo "🚀 DX Bootstrap starting... (fallback)"

# 1. Git sync (optional - may fail if no remote)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "📦 Syncing with remote..."
    git pull origin master 2>&1 | grep -v "^Already up to date" || echo "  ↳ Already up to date"
fi

# 2. Baseline DX check (canonical)
echo "🩺 Running dx-check..."
if command -v dx-check >/dev/null 2>&1; then
    dx-check 2>&1 || true
elif [[ -f "$AGENTS_ROOT/scripts/dx-check.sh" ]]; then
    "$AGENTS_ROOT/scripts/dx-check.sh" 2>&1 || true
else
    echo "⚠️  dx-check not found (install agent-skills)"
fi

# 2.5 Stranded work reminder (auto-checkpoint/WIP visibility)
if [[ -f "$AGENTS_ROOT/scripts/auto-checkpoint-notify.sh" ]]; then
    "$AGENTS_ROOT/scripts/auto-checkpoint-notify.sh" 2>&1 || true
fi

# 2.6 Canonical warning (V7.6)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
case "$REPO_ROOT" in
  "$HOME/agent-skills"|"$HOME/prime-radiant-ai"|"$HOME/affordabot"|"$HOME/llm-common")
    echo ""
    echo "🚨 WARNING: You are in a canonical clone: $REPO_ROOT"
    echo "🚨 Canonicals are automation-owned and MUST stay clean."
    echo "🚨 Create a worktree before making changes:"
    echo "   dx-worktree create <beads-id> $(basename "$REPO_ROOT")"
    echo ""
    ;;
esac

# 3. Coordinator stack checks (OPTIONAL)
if [[ "${DX_BOOTSTRAP_COORDINATOR:-0}" == "1" ]]; then
    echo "🩺 Running dx-doctor (optional coordinator checks)..."
    if command -v dx-doctor >/dev/null 2>&1; then
        dx-doctor 2>&1 || true
    elif [[ -f "$AGENTS_ROOT/scripts/dx-doctor.sh" ]]; then
        "$AGENTS_ROOT/scripts/dx-doctor.sh" 2>&1 || true
    fi
fi

echo "✅ DX bootstrap complete"
echo ""
