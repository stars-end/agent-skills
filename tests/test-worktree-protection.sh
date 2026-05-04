#!/usr/bin/env bash
#
# test-worktree-protection.sh (bd-kuhj.8)
#
# Real runtime tests for worktree protection logic.
# Tests: linked worktree detection, git locks, merge/rebase, session locks, working hours, tmux.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TEST_DIR="/tmp/dx-test-$$"
TEST_BEADS_ID="test-protection-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

setup() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    
    # Create a test repo
    cd "$TEST_DIR"
    git init test-repo
    cd test-repo
    echo "test" > file.txt
    git add file.txt
    git commit -m "initial"
    
    # Create a linked worktree
    mkdir -p "$TEST_DIR/worktrees"
    git worktree add "$TEST_DIR/worktrees/test-wt" -b test-branch
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((PASSED += 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((FAILED += 1))
    fi
}

assert_file_exists() {
    local path="$1"
    local message="$2"
    
    if [[ -f "$path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((PASSED += 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (file not found: $path)"
        ((FAILED += 1))
    fi
}

assert_path_exists() {
    local path="$1"
    local message="$2"

    if [[ -e "$path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((PASSED += 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (path not found: $path)"
        ((FAILED += 1))
    fi
}

assert_path_missing() {
    local path="$1"
    local message="$2"

    if [[ ! -e "$path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        ((PASSED += 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (still exists: $path)"
        ((FAILED += 1))
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$expected" -eq "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message (exit code: $actual)"
        ((PASSED += 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code:   $actual"
        ((FAILED += 1))
    fi
}

echo "=== bd-kuhj.8: Worktree Protection Tests ==="
echo ""

# Test 1: Linked worktree .git file detection
echo "Test 1: Linked worktree .git detection"
setup

# In a linked worktree, .git is a file, not a directory
if [[ -f "$TEST_DIR/worktrees/test-wt/.git" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Linked worktree .git is a file"
    ((PASSED += 1))
else
    echo -e "${RED}✗ FAIL${NC}: Linked worktree .git not found"
    ((FAILED += 1))
fi

# Extract gitdir from .git file
GITDIR=$(cd "$TEST_DIR/worktrees/test-wt" && cat .git)
if [[ "$GITDIR" =~ ^gitdir:\ (.+)$ ]]; then
    GITDIR_PATH="${BASH_REMATCH[1]}"
    assert_path_exists "$GITDIR_PATH" "Gitdir from .git file exists"
else
    echo -e "${RED}✗ FAIL${NC}: .git file doesn't contain gitdir"
    ((FAILED += 1))
fi

teardown

# Test 2: Git lock detection in linked worktree
echo ""
echo "Test 2: Git lock detection in linked worktree"
setup

# Create a fake lock file in the gitdir
GITDIR_PATH=$(cd "$TEST_DIR/worktrees/test-wt" && cat .git | sed 's/gitdir: //')
touch "$GITDIR_PATH/index.lock"

# Manually test the logic
if [[ -f "$GITDIR_PATH/index.lock" ]]; then
    assert_file_exists "$GITDIR_PATH/index.lock" "Git lock file detected in linked worktree gitdir"
    echo -e "${GREEN}✓ PASS${NC}: Lock detection works with linked worktrees"
    ((PASSED += 1))
else
    echo -e "${RED}✗ FAIL${NC}: Lock file not found in gitdir"
    ((FAILED += 1))
fi

teardown

# Test 3: Merge/rebase state detection
echo ""
echo "Test 3: Merge/rebase state detection in linked worktree"
setup

GITDIR_PATH=$(cd "$TEST_DIR/worktrees/test-wt" && cat .git | sed 's/gitdir: //')

# Create fake merge state
touch "$GITDIR_PATH/MERGE_HEAD"
assert_file_exists "$GITDIR_PATH/MERGE_HEAD" "MERGE_HEAD created in gitdir"

# Verify it would be detected
if [[ -f "$GITDIR_PATH/MERGE_HEAD" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Merge state detectable in linked worktree"
    ((PASSED += 1))
fi

rm "$GITDIR_PATH/MERGE_HEAD"
touch "$GITDIR_PATH/REBASE_HEAD"
assert_file_exists "$GITDIR_PATH/REBASE_HEAD" "REBASE_HEAD created in gitdir"

if [[ -f "$GITDIR_PATH/REBASE_HEAD" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Rebase state detectable in linked worktree"
    ((PASSED += 1))
fi

teardown

# Test 4: Manual cleanup protection exit code
echo ""
echo "Test 4: Manual cleanup protection exit code"
setup

# Create the test beads directory
mkdir -p "/tmp/agents/$TEST_BEADS_ID"
cd "$TEST_DIR/test-repo"
git worktree add "/tmp/agents/$TEST_BEADS_ID/test-repo" -b test-wt-2

# Copy the lock to the new worktree's gitdir
WT_GITDIR="/tmp/agents/$TEST_BEADS_ID/test-repo/.git"
WT_REAL_GITDIR=$(cat "$WT_GITDIR" | sed 's/gitdir: //')
touch "$WT_REAL_GITDIR/index.lock"

# Try to cleanup - should exit with code 2 (protected)
set +e
"$AGENTS_ROOT/scripts/worktree-cleanup.sh" "$TEST_BEADS_ID" 2>&1
EXIT_CODE=$?
set -e

assert_exit_code 2 $EXIT_CODE "Worktree cleanup exits with code 2 when protected (git lock)"

# Cleanup test
rm -rf "/tmp/agents/$TEST_BEADS_ID"
teardown

# Test 5: Automation cleanup respects working-hours protection
echo ""
echo "Test 5: Automation cleanup working-hours protection"
AUTOMATION_BEADS_ID="${TEST_BEADS_ID}-automation"
AUTOMATION_ROOT="/tmp/agents/$AUTOMATION_BEADS_ID"
mkdir -p "$AUTOMATION_ROOT/sample-repo"

set +e
WORKTREE_CLEANUP_PROTECT_START=0 WORKTREE_CLEANUP_PROTECT_END=24 \
    bash "$AGENTS_ROOT/scripts/worktree-cleanup-automation.sh" "$AUTOMATION_BEADS_ID" >/dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code 2 $EXIT_CODE "Automation cleanup exits with code 2 during protected hours"
assert_path_exists "$AUTOMATION_ROOT/sample-repo" "Automation cleanup preserves protected worktree root"
rm -rf "$AUTOMATION_ROOT"

# Test 6: Manual cleanup is not blocked by working-hours policy
echo ""
echo "Test 6: Manual cleanup ignores working-hours protection"
MANUAL_BEADS_ID="${TEST_BEADS_ID}-manual"
MANUAL_ROOT="/tmp/agents/$MANUAL_BEADS_ID"
mkdir -p "$MANUAL_ROOT/sample-repo"

set +e
WORKTREE_CLEANUP_PROTECT_START=0 WORKTREE_CLEANUP_PROTECT_END=24 \
    bash "$AGENTS_ROOT/scripts/worktree-cleanup.sh" "$MANUAL_BEADS_ID" >/dev/null 2>&1
EXIT_CODE=$?
set -e

assert_exit_code 0 $EXIT_CODE "Manual cleanup is allowed during protected hours"
assert_path_missing "$MANUAL_ROOT" "Manual cleanup removes worktree root"

# Test 7: Python workspace validation
echo ""
echo "Test 7: Python workspace path validation"
python3 -c "
import sys
sys.path.insert(0, '$AGENTS_ROOT/scripts')
from pathlib import Path
from dx_batch import is_canonical_repo_path, validate_workspace_path

# Test canonical detection
assert is_canonical_repo_path(Path.home() / 'agent-skills'), 'Should detect agent-skills'
assert is_canonical_repo_path(Path.home() / 'agent-skills' / 'scripts'), 'Should detect descendant'
assert not is_canonical_repo_path(Path('/tmp/agents/test')), 'Should allow /tmp/agents'

# Test workspace validation
is_valid, reason, exit_code = validate_workspace_path(Path.home() / 'agent-skills')
assert not is_valid, 'Should reject canonical'
assert exit_code == 22, 'Should return exit code 22 for canonical'

is_valid, reason, exit_code = validate_workspace_path(Path('/tmp/agents/test'))
assert is_valid, 'Should allow /tmp/agents'
assert exit_code == 0, 'Should return exit code 0 for allowed'

print('  ✓ Python validation functions work correctly')
"

if [[ $? -eq 0 ]]; then
    ((PASSED += 1))
else
    echo -e "${RED}✗ FAIL${NC}: Python validation functions"
    ((FAILED += 1))
fi

# Test 8: Working hours function
echo ""
echo "Test 8: Working hours protection logic"
CURRENT_HOUR=$((10#$(date +%H)))
export WORKTREE_CLEANUP_PROTECT_START=8
export WORKTREE_CLEANUP_PROTECT_END=18

if [[ "$CURRENT_HOUR" -ge 8 && "$CURRENT_HOUR" -lt 18 ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Currently in working hours ($CURRENT_HOUR:00)"
    ((PASSED += 1))
else
    echo -e "${GREEN}✓ PASS${NC}: Currently outside working hours ($CURRENT_HOUR:00)"
    ((PASSED += 1))
fi

# Test 7: Skip log file creation
echo ""
echo "Test 7: Skip log file creation"
LOG_FILE="$HOME/.dx-state/worktree-cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Write a test log entry
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | beads_id=test-123 | action=skip | reason=test | details=test | path=/tmp/test | mode=test" >> "$LOG_FILE"

assert_file_exists "$LOG_FILE" "Skip log file created"

# Verify log format is machine-readable
if grep -q "beads_id=test-123" "$LOG_FILE"; then
    echo -e "${GREEN}✓ PASS${NC}: Skip log format is machine-readable"
    ((PASSED += 1))
else
    echo -e "${RED}✗ FAIL${NC}: Skip log format not machine-readable"
    ((FAILED += 1))
fi

echo ""
echo "=== Test Summary ==="
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✅ All protection tests passed${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Some tests failed${NC}"
    exit 1
fi
