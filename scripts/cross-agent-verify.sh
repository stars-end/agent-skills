#!/usr/bin/env bash
# cross-agent-verify.sh - Verify cross-agent guardrails are installed
# Usage: cross-agent-verify.sh

set -euo pipefail

PASS=0
FAIL=0

check_pass() {
    echo "✅ PASS: $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo "❌ FAIL: $1"
    echo "   Fix: $2"
    FAIL=$((FAIL + 1))
}

echo "=== Cross-Agent Guardrail Verification ==="
echo ""

# 1. Claude Code SessionStart hook
if [[ -f "$HOME/.claude/hooks/SessionStart/dx-bootstrap.sh" ]]; then
    check_pass "Claude Code SessionStart hook installed"
else
    check_fail "Claude Code SessionStart hook missing" \
        "ln -s ~/agent-skills/session-start-hooks/dx-bootstrap.sh ~/.claude/hooks/SessionStart/dx-bootstrap.sh"
fi

# 2. Codex config.toml
if [[ -f "$HOME/.codex/config.toml" ]]; then
    if grep -q "dx-bootstrap" "$HOME/.codex/config.toml" 2>/dev/null; then
        check_pass "Codex config.toml has on_start hook"
    else
        check_fail "Codex config.toml missing on_start hook" \
            "Add [session].on_start to ~/.codex/config.toml"
    fi
else
    check_fail "Codex config.toml missing" \
        "cp ~/agent-skills/config-templates/codex-config.toml ~/.codex/config.toml"
fi

# 3. Pre-commit hook in canonical repos
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
for repo in "${CANONICAL_REPOS[@]}"; do
    if [[ -f "$HOME/$repo/.git/hooks/pre-commit" ]]; then
        if grep -q "worktree\|canonical" "$HOME/$repo/.git/hooks/pre-commit" 2>/dev/null; then
            check_pass "$repo pre-commit hook installed"
        else
            check_fail "$repo pre-commit hook missing canonical check" \
                "Run: ~/agent-skills/scripts/install-canonical-precommit.sh"
        fi
    else
        check_fail "$repo pre-commit hook missing" \
            "Run: ~/agent-skills/scripts/install-canonical-precommit.sh"
    fi
done

# 4. Antigravity/OpenCode (documented as TODO)
echo ""
echo "⚠️  MANUAL CHECK: Antigravity/OpenCode"
echo "   Status: TODO - manual step required"
echo "   These tools don't have hook infrastructure yet."
echo ""

# Summary
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ All cross-agent guardrails verified"
    exit 0
else
    echo "❌ Some guardrails missing - see fixes above"
    exit 1
fi
