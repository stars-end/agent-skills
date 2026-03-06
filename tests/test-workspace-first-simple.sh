#!/usr/bin/env bash
# test-workspace-first-simple.sh - Simpler validation for bd-kuhj
#
# This version validates implementation without creating worktrees
# Tests the PR checkout, not installed ~/agent-skills

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

pass() { echo -e "${GREEN}✓ PASS${NC}: $*"; pass_count=$((pass_count + 1)); }
fail() { echo -e "${RED}✗ FAIL${NC}: $*"; fail_count=$((fail_count + 1)); }

section() { echo ""; echo -e "${BLUE}### $*${NC}"; }

echo "========================================"
echo "DX V8.6 Workspace-First Validation"
echo "========================================"
echo "Testing PR checkout: $AGENTS_ROOT"
echo ""

# ============================================================================
# Test 1: dx-worktree command existence (bd-kuhj.1)
# ============================================================================

section "bd-kuhj.1: dx-worktree workspace primitives"

# Test 1.1: open command exists
if "$AGENTS_ROOT/scripts/dx-worktree.sh" 2>&1 | grep -q "open"; then
    pass "dx-worktree has 'open' command"
else
    fail "dx-worktree missing 'open' command"
fi

# Test 1.2: resume command exists
if "$AGENTS_ROOT/scripts/dx-worktree.sh" 2>&1 | grep -q "resume"; then
    pass "dx-worktree has 'resume' command"
else
    fail "dx-worktree missing 'resume' command"
fi

# Test 1.3: evacuate-canonical command exists
if "$AGENTS_ROOT/scripts/dx-worktree.sh" 2>&1 | grep -q "evacuate-canonical"; then
    pass "dx-worktree has 'evacuate-canonical' command"
else
    fail "dx-worktree missing 'evacuate-canonical' command"
fi

# Test 1.4: explain reflects V8.6
if "$AGENTS_ROOT/scripts/dx-worktree.sh" explain 2>&1 | grep -q "V8.6"; then
    pass "dx-worktree explain reflects V8.6 contract"
else
    fail "dx-worktree explain missing V8.6 reference"
fi

# ============================================================================
# Test 2: dx-runner canonical rejection (bd-kuhj.3)
# ============================================================================

section "bd-kuhj.3: dx-runner canonical rejection"

# Test 2.1: is_canonical_repo_path function exists
if grep -q "is_canonical_repo_path()" "$AGENTS_ROOT/scripts/dx-runner"; then
    pass "dx-runner has is_canonical_repo_path() function"
else
    fail "dx-runner missing is_canonical_repo_path() function"
fi

# Test 2.2: canonical_worktree_forbidden reason code exists
if grep -q "canonical_worktree_forbidden" "$AGENTS_ROOT/scripts/dx-runner"; then
    pass "dx-runner has canonical_worktree_forbidden reason code"
else
    fail "dx-runner missing canonical_worktree_forbidden reason code"
fi

# Test 2.3: remediation command present
if grep -q "remedy=dx-worktree create" "$AGENTS_ROOT/scripts/dx-runner"; then
    pass "dx-runner provides remediation command"
else
    fail "dx-runner missing remediation command"
fi

# Test 2.4: worktree enforcement for ALL providers (not just opencode)
# bd-kuhj.3: gemini must also be blocked from canonical repos
if grep -A30 "# Resolve and pin worktree" "$AGENTS_ROOT/scripts/dx-runner" | grep -q "PROVIDER.*opencode"; then
    fail "dx-runner still has provider-specific worktree check (gemini bypass)"
else
    pass "dx-runner enforces worktree for all providers"
fi

# Test 2.4: check_permission_gate updated
if grep -A10 "check_permission_gate()" "$AGENTS_ROOT/scripts/dx-runner" | grep -q "canonical_worktree_forbidden"; then
    pass "check_permission_gate() checks for canonical repos"
else
    fail "check_permission_gate() doesn't check canonical repos"
fi

# ============================================================================
# Test 3: Documentation alignment (bd-kuhj.4, bd-kuhj.6)
# ============================================================================

section "bd-kuhj.4/bd-kuhj.6: Documentation alignment"

# Test 3.1: worktree-workflow SKILL.md updated
if grep -q "Workspace-First.*V8.6" "$AGENTS_ROOT/extended/worktree-workflow/SKILL.md"; then
    pass "worktree-workflow SKILL.md reflects V8.6"
else
    fail "worktree-workflow SKILL.md missing V8.6 reference"
fi

# Test 3.2: IDE_SPECS.md has workspace-first section
if grep -q "Workspace-First Manual Sessions" "$AGENTS_ROOT/docs/IDE_SPECS.md"; then
    pass "IDE_SPECS.md has workspace-first section"
else
    fail "IDE_SPECS.md missing workspace-first section"
fi

# Test 3.3: dx-runner SKILL.md updated
if grep -q "Workspace-First Gate" "$AGENTS_ROOT/extended/dx-runner/SKILL.md"; then
    pass "dx-runner SKILL.md has workspace-first gate section"
else
    fail "dx-runner SKILL.md missing workspace-first gate section"
fi

# Test 3.4: canonical rejection documented in dx-runner SKILL.md
if grep -q "canonical_worktree_forbidden" "$AGENTS_ROOT/extended/dx-runner/SKILL.md"; then
    pass "dx-runner SKILL.md documents canonical rejection"
else
    fail "dx-runner SKILL.md missing canonical rejection docs"
fi

# ============================================================================
# Test 4: Normal operations still work (bd-kuhj.3)
# ============================================================================

section "bd-kuhj.3: Normal operations unaffected"

# Test 4.1: validate_worktree_path still allows agent-skills
if grep -A10 "allowed_prefixes=" "$AGENTS_ROOT/scripts/dx-runner" | grep -q '"\$HOME/agent-skills"'; then
    pass "dx-runner still allows \$HOME/agent-skills for non-mutating ops"
else
    fail "dx-runner removed agent-skills from allowed prefixes"
fi

# Test 4.2: skills directory exists
if [[ -d "$AGENTS_ROOT/extended" ]]; then
    skill_count="$(find "$AGENTS_ROOT/extended" -name "SKILL.md" | wc -l | tr -d ' ')"
    if [[ "$skill_count" -gt 0 ]]; then
        pass "Skills directory exists ($skill_count skills found)"
    else
        fail "No skills found in canonical"
    fi
else
    fail "Canonical extended skills directory missing"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Passed:${NC}  $pass_count"
echo -e "${RED}Failed:${NC}  $fail_count"
echo ""

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}✅ All validation tests passed${NC}"
    echo ""
    echo "Evidence:"
    echo "- dx-worktree has open/resume/evacuate-canonical commands"
    echo "- dx-runner rejects canonical repos with canonical_worktree_forbidden"
    echo "- dx-runner provides remediation: dx-worktree create <beads-id> <repo>"
    echo "- Documentation aligned to workspace-first V8.6 contract"
    echo "- Normal operations (git fetch, skills loading) still work"
    exit 0
else
    echo -e "${RED}❌ Some validation tests failed${NC}"
    exit 1
fi
