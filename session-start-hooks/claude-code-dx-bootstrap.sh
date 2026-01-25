#!/usr/bin/env bash
#
# Claude Code SessionStart Hook: DX Bootstrap
#
# Installation:
#   mkdir -p .claude/hooks/SessionStart
#   cp ~/agent-skills/session-start-hooks/claude-code-dx-bootstrap.sh \
#      .claude/hooks/SessionStart/dx-bootstrap.sh
#   chmod +x .claude/hooks/SessionStart/dx-bootstrap.sh
#
# Purpose: Run dx-doctor check at session start to detect environment drift

set -euo pipefail

echo "🚀 DX Bootstrap starting..."

# 1. Git sync (optional - may fail if no remote)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "📦 Syncing with remote..."
    git pull origin master 2>&1 | grep -v "^Already up to date" || echo "  ↳ Already up to date"
fi

# 2. Baseline DX check (canonical)
echo "🩺 Running dx-check..."
if command -v dx-check >/dev/null 2>&1; then
    dx-check 2>&1 || true
elif [[ -f "$HOME/agent-skills/scripts/dx-check.sh" ]]; then
    "$HOME/agent-skills/scripts/dx-check.sh" 2>&1 || true
else
    echo "⚠️  dx-check not found (install agent-skills)"
fi

# 3. Coordinator stack checks (OPTIONAL)
if [[ "${DX_BOOTSTRAP_COORDINATOR:-0}" == "1" ]]; then
    echo "🩺 Running dx-doctor (optional coordinator checks)..."
    if command -v dx-doctor >/dev/null 2>&1; then
        dx-doctor 2>&1 || true
    elif [[ -f "$HOME/agent-skills/scripts/dx-doctor.sh" ]]; then
        "$HOME/agent-skills/scripts/dx-doctor.sh" 2>&1 || true
    fi
fi

echo "✅ DX bootstrap complete"
echo ""
