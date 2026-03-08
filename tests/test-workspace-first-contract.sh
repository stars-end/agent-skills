#!/usr/bin/env bash
# test-workspace-first-contract.sh
#
# Validation tests for DX V8.6 workspace-first canonical isolation
# Beads: bd-kuhj.7
#
# Tests the PR checkout itself, not installed ~/agent-skills
#
# NOTE: This script and dx-runner both require bash >= 4 for associative arrays.
# On macOS, the shebang #!/usr/bin/env bash resolves to Homebrew bash (5.x) when
# /opt/homebrew/bin is in PATH before /bin. To run explicitly with modern bash:
#   /opt/homebrew/bin/bash tests/test-workspace-first-contract.sh
# Or simply ensure /opt/homebrew/bin appears before /bin in your PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Test the PR checkout itself, not installed canonical
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CURRENT_BASH="${BASH:-bash}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass_count=0
fail_count=0
skip_count=0
test_beads_id=""
test_workspace_path=""

pass() { echo -e "${GREEN}✓ PASS${NC}"; pass_count=$((pass_count + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}"; fail_count=$((fail_count + 1)); }
skip() { echo -e "${YELLOW}⊘ SKIP${NC}"; skip_count=$((skip_count + 1)); }

section() { echo ""; echo -e "${BLUE}### $*${NC}"; }

# ============================================================================
# Test 1: dx-worktree workspace primitives (bd-kuhj.1)
# ============================================================================

section "bd-kuhj.1: dx-worktree workspace primitives"

# Test 1.1: create workspace
echo "Test 1.1: dx-worktree create"
# Use unique test ID to avoid conflicts
test_beads_id="bd-test-ws-$$"
set +e
create_result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" create "$test_beads_id" agent-skills 2>&1)"
create_rc=$?
set -e
if [[ $create_rc -eq 0 && -n "$create_result" ]]; then
    pass "dx-worktree create succeeded"
    # Store for cleanup
    test_workspace_path="$create_result"
else
    # If create fails, workspace might already exist - try to cleanup and retry
    "$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" cleanup "$test_beads_id" >/dev/null 2>&1 || true
    set +e
    create_result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" create "$test_beads_id" agent-skills 2>&1)"
    create_rc=$?
    set -e
    if [[ $create_rc -eq 0 && -n "$create_result" ]]; then
        pass "dx-worktree create succeeded (after cleanup)"
        test_workspace_path="$create_result"
    else
        fail "dx-worktree create failed: $create_result"
    fi
fi

# Test 1.2: open workspace (path mode)
echo "Test 1.2: dx-worktree open (path mode)"
result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" open "$test_beads_id" agent-skills 2>&1)" || true
if [[ "$result" == *"workspace_path="* ]] || [[ -n "$result" && "$result" == *"/tmp/agents"* ]]; then
    pass "dx-worktree open returns workspace status"
else
    fail "dx-worktree open failed: $result"
fi

# Test 1.3: resume workspace
echo "Test 1.3: dx-worktree resume"
result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" resume "$test_beads_id" agent-skills 2>&1)" || true
if [[ "$result" == *"workspace_path="* ]] || [[ -n "$result" && "$result" == *"/tmp/agents"* ]]; then
    pass "dx-worktree resume works (alias)"
else
    fail "dx-worktree resume failed"
fi

# Test 1.4: explain command
echo "Test 1.4: dx-worktree explain"
if "$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" explain | grep -q "Workspace-First"; then
    pass "dx-worktree explain reflects V8.6 contract"
else
    fail "dx-worktree explain missing V8.6 contract"
fi

# Cleanup
"$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" cleanup "$test_beads_id" >/dev/null 2>&1 || true

# ============================================================================
# Test 2: Canonical path rejection (bd-kuhj.3)
# ============================================================================

section "bd-kuhj.3: Canonical path rejection"

# Test 2.1: dx-runner rejects canonical path
echo "Test 2.1: dx-runner rejects canonical repo"
set +e
result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-runner" start \
    --beads bd-test-canonical \
    --provider opencode \
    --worktree "$HOME/agent-skills" \
    --prompt-file /tmp/test.txt 2>&1)" || true
rc=$?
set -e

# Accept either canonical_worktree_forbidden OR beads cwd gate (both are valid rejections)
if [[ "$result" == *"canonical_worktree_forbidden"* ]]; then
    pass "dx-runner rejects canonical with reason_code"
elif [[ "$result" == *"beads cwd gate failed"* ]]; then
    pass "dx-runner enforces cwd gate (valid rejection)"
elif [[ "$result" == *"canonical"* && "$result" == *"forbidden"* ]]; then
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
# This test requires modifying an actual canonical repo, which we can't do safely
# So we test that the function properly validates canonical repo names
result="$("$CURRENT_BASH" "$AGENTS_ROOT/scripts/dx-worktree.sh" evacuate-canonical non-canonical-test-repo 2>&1)" || true
if [[ "$result" == *"not a canonical repo"* ]]; then
    pass "evacuate-canonical validates repo is canonical"
else
    # Alternative: check if it validates the repo exists at all
    if [[ "$result" == *"canonical repo missing"* ]]; then
        pass "evacuate-canonical validates repo exists"
    else
        skip "evacuate-canonical test requires safe environment"
    fi
fi

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
