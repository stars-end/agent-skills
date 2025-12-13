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

# 2. DX doctor check
echo "🩺 Running dx-doctor..."
if [[ -f Makefile ]] && grep -q "dx-doctor" Makefile 2>/dev/null; then
    make dx-doctor 2>&1 || {
        echo "⚠️  dx-doctor check found issues (see above)"
        echo "   Continue with caution or fix issues before proceeding"
    }
elif [[ -f ~/.agent/skills/dx-doctor/check.sh ]]; then
    ~/.agent/skills/dx-doctor/check.sh 2>&1 || {
        echo "⚠️  dx-doctor check found issues (see above)"
        echo "   Continue with caution or fix issues before proceeding"
    }
else
    echo "⚠️  dx-doctor not found (install agent-skills)"
    echo "   git clone https://github.com/stars-end/agent-skills ~/.agent/skills"
fi

# 3. Agent Mail check (if configured)
if [[ -n "${AGENT_MAIL_URL:-}" ]] && [[ -n "${AGENT_MAIL_BEARER_TOKEN:-}" ]]; then
    echo "✅ Agent Mail configured ($AGENT_MAIL_URL)"
    echo "   Register identity and check inbox for assignments"
else
    echo "ℹ️  Agent Mail not configured (Beads + git only)"
fi

echo "✅ DX bootstrap complete"
echo ""
