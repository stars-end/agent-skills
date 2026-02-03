#!/bin/bash
# Ralph Test Framework
# Creates and runs test epics to validate Ralph autonomous loop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
if [ -z "${BEADS_DIR:-}" ]; then
    echo "❌ BEADS_DIR not set. V5 requires external beads DB."
    echo "   Fix: export BEADS_DIR=\"$HOME/bd/.beads\""
    exit 1
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}✅ PASS: $*${NC}"
}

log_fail() {
    echo -e "${RED}❌ FAIL: $*${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  WARN: $*${NC}"
}

# Create trivial test epic in Beads
create_test_epic() {
    local epic_id="test-ralph-$$"
    local epic_title="Test Epic: Ralph Loop Validation ($(date +%H%M%S))"

    log "Creating test epic: $epic_id"

    # Create epic
    bd --no-daemon --allow-stale create \
        --id "$epic_id" \
        --title "$epic_title" \
        --type epic \
        --priority 3 \
        --description "Automated test epic for Ralph loop validation" >/dev/null

    # Create 5 trivial file creation tasks
    for i in {1..5}; do
        local task_id="test-ralph-$$-task$i"
        local filename="test-file-$i.txt"
        local content="This is test file $i created by Ralph"

        bd --no-daemon --allow-stale create \
            --id "$task_id" \
            --title "Create test file $i" \
            --type task \
            --priority 3 \
            --description "Create file named $filename with content: $content" \
            --acceptance "File exists with correct content" >/dev/null

        # Link task to epic
        bd --no-daemon --allow-stale dep add "$task_id" "$epic_id" >/dev/null 2>&1 || true
    done

    log_pass "Test epic created with 5 tasks"
    echo "$epic_id"
}

# Verify test results
verify_results() {
    local work_dir="$1"
    local passed=0
    local failed=0

    log "Verifying test results..."

    # Check each test file
    for i in {1..5}; do
        local filename="$work_dir/test-file-$i.txt"
        local expected_content="This is test file $i created by Ralph"

        if [ -f "$filename" ]; then
            local actual_content=$(cat "$filename")
            if [ "$actual_content" = "$expected_content" ]; then
                log_pass "File $i: correct content"
                ((passed++))
            else
                log_fail "File $i: wrong content (expected: '$expected_content', got: '$actual_content')"
                ((failed++))
            fi
        else
            log_fail "File $i: not found"
            ((failed++))
        fi
    done

    # Check git commits
    log "Checking git commits..."
    local commits=$(cd "$work_dir" && git log --oneline | grep -c "test-ralph-" || echo "0")
    log "Git commits: $commits"

    echo ""
    log "=== Verification Summary ==="
    log "Passed: $passed/5"
    log "Failed: $failed/5"

    if [ $failed -eq 0 ]; then
        log_pass "All tests passed!"
        return 0
    else
        log_fail "Some tests failed"
        return 1
    fi
}

# Run test cycle
run_test_cycle() {
    local epic_id="$1"
    local cycle_num="$2"
    local work_dir=".ralph-test-cycle-$cycle_num-$$"

    log "=== Cycle $cycle_num: $epic_id ==="
    log "Work directory: $work_dir"

    # Run Ralph integration
    if (cd "$WORKSPACE" && "$SCRIPT_DIR/beads-integration.sh" "$epic_id"); then
        log_pass "Cycle $cycle_num completed successfully"
        return 0
    else
        log_fail "Cycle $cycle_num failed"
        return 1
    fi
}

# Main test execution
main() {
    log "=== Ralph Test Framework ==="
    log "Starting test sequence..."
    echo ""

    # Create test epic
    local epic_id=$(create_test_epic)
    echo ""

    # Run 3 test cycles
    local cycles_passed=0
    local cycles_failed=0

    for cycle in {1..3}; do
        log "=== Test Cycle $cycle/3 ==="

        # Re-create epic for each cycle (clean state)
        if [ $cycle -gt 1 ]; then
            log "Re-creating test epic for cycle $cycle..."
            # Close previous epic
            bd --no-daemon --allow-stale close "$epic_id" >/dev/null 2>&1 || true
            # Create new epic
            epic_id=$(create_test_epic)
        fi

        # Run test cycle
        if run_test_cycle "$epic_id" "$cycle"; then
            ((cycles_passed++))
        else
            ((cycles_failed++))
        fi

        echo ""
    done

    # Final summary
    log "=== Final Summary ==="
    log "Cycles passed: $cycles_passed/3"
    log "Cycles failed: $cycles_failed/3"

    if [ $cycles_failed -eq 0 ]; then
        log_pass "All test cycles passed! Ralph is stable."
        exit 0
    else
        log_fail "Some test cycles failed. See logs above."
        exit 1
    fi
}

# Run main
main "$@"
