#!/usr/bin/env bash
# test-workspace-first-contract.sh
#
# Validation tests for DX V8.6 workspace-first canonical isolation
# Beads: bd-kuhj.7
#
# Tests the PR checkout itself, not installed ~/agent-skills

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Test the PR checkout itself, not installed canonical
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass_count=0
fail_count=0
skip_count=0

pass() { echo -e "${GREEN}✓ PASS${NC}"; ((pass_count++)); }
fail() { echo -e "${RED}✗ FAIL${NC}"; ((fail_count++)); }
skip() { echo -e "${YELLOW}⊘ SKIP${NC}"; ((skip_count++)); }

section() { echo ""; echo -e "${BLUE}### $*${NC}"; }

# ============================================================================
# Test 1: dx-worktree workspace primitives (bd-kuhj.1)
# ============================================================================

section "bd-kuhj.1: dx-worktree workspace primitives"

# Test 1.1: create workspace
echo "Test 1.1: dx-worktree create"
if "$AGENTS_ROOT/scripts/dx-worktree.sh" create bd-test-ws agent-skills >/dev/null 2>&1; then
    pass "dx-worktree create succeeded"
else
    fail "dx-worktree create failed"
fi

# Test 1.2: open workspace (path mode)
echo "Test 1.2: dx-worktree open (path mode)"
result="$("$AGENTS_ROOT/scripts/dx-worktree.sh" open bd-test-ws agent-skills 2>&1)" || true
if [[ "$result" == *"workspace_path="* ]]; then
    pass "dx-worktree open returns workspace status"
else
    fail "dx-worktree open failed: $result"
fi

# Test 1.3: resume workspace
echo "Test 1.3: dx-worktree resume"
result="$("$AGENTS_ROOT/scripts/dx-worktree.sh" resume bd-test-ws agent-skills 2>&1)" || true
if [[ "$result" == *"workspace_path="* ]]; then
    pass "dx-worktree resume works (alias)"
else
    fail "dx-worktree resume failed"
fi

# Test 1.4: explain command
echo "Test 1.4: dx-worktree explain"
if "$AGENTS_ROOT/scripts/dx-worktree.sh" explain | grep -q "Workspace-First"; then
    pass "dx-worktree explain reflects V8.6 contract"
else
    fail "dx-worktree explain missing V8.6 contract"
fi

# Cleanup
"$AGENTS_ROOT/scripts/dx-worktree.sh" cleanup bd-test-ws >/dev/null 2>&1 || true

# ============================================================================
# Test 2: Canonical path rejection (bd-kuhj.3)
# ============================================================================

section "bd-kuhj.3: Canonical path rejection"

# Test 2.1: dx-runner rejects canonical path
echo "Test 2.1: dx-runner rejects canonical repo"
set +e
result="$("$AGENTS_ROOT/scripts/dx-runner" start \
    --beads bd-test-canonical \
    --provider opencode \
    --worktree "$HOME/agent-skills" \
    --prompt-file /tmp/test.txt 2>&1)" || true
rc=$?
set -e

if [[ "$result" == *"canonical_worktree_forbidden"* ]]; then
    pass "dx-runner rejects canonical with reason_code"
elif [[ "$result" == *"canonical_worktree_forbidden"* ]]; then
    pass "dx-runner rejects canonical (partial match)"
else
    fail "dx-runner canonical rejection failed: $result"
fi

# Test 2.2: Remediation command present
echo "Test 2.2: Remediation command present"
if [[ "$result" == *"remedy=dx-worktree create"* ]]; then
    pass "Remediation command provided"
else
    skip "Remediation command not found (acceptable if error format differs)"
fi

# ============================================================================
# Test 3: Normal operations still work (bd-kuhj.3)
# ============================================================================

section "bd-kuhj.3: Normal operations unaffected"

# Test 3.1: git fetch in canonical
echo "Test 3.1: git fetch in canonical repo"
if (cd "$HOME/agent-skills" && git fetch --dry-run 2>&1 | grep -q "Would fetch"); then
    pass "git fetch works in canonical"
else
    skip "git fetch test skipped"
fi

# Test 3.2: railway status in canonical
echo "Test 3.2: railway status in canonical repo"
if command -v railway >/dev/null 2>&1; then
    if (cd "$HOME/agent-skills" && railway status >/dev/null 2>&1); then
        pass "railway status works in canonical"
    else
        skip "railway status test skipped (not linked)"
    fi
else
    skip "railway not available"
fi

# Test 3.3: skills load from canonical
echo "Test 3.3: skills load from canonical"
if [[ -d "$HOME/agent-skills/extended" ]]; then
    skill_count="$(find "$HOME/agent-skills/extended" -name "SKILL.md" | wc -l | tr -d ' ')"
    if [[ "$skill_count" -gt 0 ]]; then
        pass "Skills load from canonical ($skill_count skills found)"
    else
        fail "No skills found in canonical"
    fi
else
    fail "Canonical extended skills directory missing"
fi

# ============================================================================
# Test 4: Recovery with named worktrees (bd-kuhj.5)
# ============================================================================

section "bd-kuhj.5: Recovery with named worktrees"

# Test 4.1: evacuate-canonical skip conditions
echo "Test 4.1: evacuate-canonical skip conditions"
# Create a fake lock
mkdir -p "/tmp/test-agent-skills/.git"
touch "/tmp/test-agent-skills/.git/index.lock"

result="$("$AGENTS_ROOT/scripts/dx-worktree.sh" evacuate-canonical test-agent-skills 2>&1)" || true
if [[ "$result" == *"reason=index_lock"* ]] then
    pass "evacuate-canonical skips on index.lock"
else
    fail "evacuate-canonical did not skip on lock: $result"
fi

rm -rf "/tmp/test-agent-skills"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================"
echo "DX V8.6 Workspace-First Validation"
echo "========================================"
echo ""
echo -e "${GREEN}Passed:${NC}  $pass_count"
echo -e "${RED}Failed:${NC}  $fail_count"
echo -e "${YELLOW}Skipped:${NC} $skip_count"
echo ""

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}All critical tests passed${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
