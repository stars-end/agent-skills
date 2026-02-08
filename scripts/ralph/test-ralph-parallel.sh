#!/bin/bash
# End-to-end test for Ralph parallel execution (agent-jhjf)
# Tests: dependency resolution, parallel execution, layer ordering, worktree cleanup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $1"
}

# Configuration
WORKSPACE="/Users/fengning/agent-skills"
BEADS_DIR="${BEADS_DIR:-$HOME/bd/.beads}"  # Use external BEADS_DIR (dx-alpha)
TEST_EPIC_ID="agent-test-e2e-$$"
MAX_PARALLEL=3

log "=== Ralph Parallel E2E Test ==="
log "Test epic ID: $TEST_EPIC_ID"
log "Max parallel workers: $MAX_PARALLEL"
log ""

# Create test epic with 8 subtasks and proper dependencies
log "Creating test epic with subtasks..."

# Create epic
EPIC_ID="$TEST_EPIC_ID"
bd create \
  --id="$EPIC_ID" \
  --title="Ralph Parallel E2E Test Epic" \
  --description="End-to-end test for Ralph parallel execution" \
  --type=epic \
  --priority=1 \
  --assignee="test" >/dev/null 2>&1 || true

# Create 8 subtasks with dependency structure:
# Layer 0: T1, T2, T3 (no dependencies)
# Layer 1: T4 (depends on T1), T5 (depends on T2), T6 (depends on T3)
# Layer 2: T7 (depends on T4), T8 (depends on T5)

log "  Layer 0 tasks (independent): T1, T2, T3"
bd create --id="${TEST_EPIC_ID}-t1" --title="Test Task 1" --description="Create test-t1.txt" --type=task --priority=1 >/dev/null 2>&1 || true
bd create --id="${TEST_EPIC_ID}-t2" --title="Test Task 2" --description="Create test-t2.txt" --type=task --priority=1 >/dev/null 2>&1 || true
bd create --id="${TEST_EPIC_ID}-t3" --title="Test Task 3" --description="Create test-t3.txt" --type=task --priority=1 >/dev/null 2>&1 || true

log "  Layer 1 tasks (depend on Layer 0): T4, T5, T6"
bd create --id="${TEST_EPIC_ID}-t4" --title="Test Task 4" --description="Create test-t4.txt (depends on T1)" --type=task --priority=1 >/dev/null 2>&1 || true
bd create --id="${TEST_EPIC_ID}-t5" --title="Test Task 5" --description="Create test-t5.txt (depends on T2)" --type=task --priority=1 >/dev/null 2>&1 || true
bd create --id="${TEST_EPIC_ID}-t6" --title="Test Task 6" --description="Create test-t6.txt (depends on T3)" --type=task --priority=1 >/dev/null 2>&1 || true

log "  Layer 2 tasks (depend on Layer 1): T7, T8"
bd create --id="${TEST_EPIC_ID}-t7" --title="Test Task 7" --description="Create test-t7.txt (depends on T4)" --type=task --priority=1 >/dev/null 2>&1 || true
bd create --id="${TEST_EPIC_ID}-t8" --title="Test Task 8" --description="Create test-t8.txt (depends on T5)" --type=task --priority=1 >/dev/null 2>&1 || true

# Set up dependencies (child->parent)
log "Setting up dependencies..."
bd dep add "${TEST_EPIC_ID}-t4" "${TEST_EPIC_ID}-t1"
bd dep add "${TEST_EPIC_ID}-t5" "${TEST_EPIC_ID}-t2"
bd dep add "${TEST_EPIC_ID}-t6" "${TEST_EPIC_ID}-t3"
bd dep add "${TEST_EPIC_ID}-t7" "${TEST_EPIC_ID}-t4"
bd dep add "${TEST_EPIC_ID}-t8" "${TEST_EPIC_ID}-t5"

# Link subtasks to epic (parent-child relationship)
log "Linking subtasks to epic..."
for task_id in ${TEST_EPIC_ID}-{t1..t8}; do
  bd dep add "$task_id" "$EPIC_ID" 2>/dev/null || true
done

log_success "Test epic created with 8 subtasks"
log ""

# Verify dependency structure
log "Verifying dependency structure..."
for task_id in ${TEST_EPIC_ID}-{t1..t8}; do
  TASK_JSON=$(bd show "$task_id" --json 2>/dev/null)
  TITLE=$(echo "$TASK_JSON" | jq -r '.[0].title')
  DEPS=$(echo "$TASK_JSON" | jq -r '.[0].dependencies // []' | jq -r '[.[].id] | join(", ")')
  log "  $task_id ($title): depends on [$DEPS]"
done
log ""

# Run Ralph parallel execution
log "Running Ralph parallel execution..."
log "Command: ./scripts/ralph/beads-parallel.sh --max-parallel $MAX_PARALLEL ${TEST_EPIC_ID}-{t1..t8}"
log ""

# Capture output
TEST_OUTPUT="/tmp/ralph-e2e-test-$$.log"
cd "$WORKSPACE"

# Run the test (with KEEP_WORKTREES=0 to ensure cleanup)
KEEP_WORKTREES=0 ./scripts/ralph/beads-parallel.sh --max-parallel "$MAX_PARALLEL" \
  ${TEST_EPIC_ID}-t1 \
  ${TEST_EPIC_ID}-t2 \
  ${TEST_EPIC_ID}-t3 \
  ${TEST_EPIC_ID}-t4 \
  ${TEST_EPIC_ID}-t5 \
  ${TEST_EPIC_ID}-t6 \
  ${TEST_EPIC_ID}-t7 \
  ${TEST_EPIC_ID}-t8 2>&1 | tee "$TEST_OUTPUT"

EXIT_CODE=${PIPESTATUS[0]}

log ""
log "=================================================="
log "VERIFICATION"
log "=================================================="

# Verify all tasks completed
log "Checking task completion..."
COMPLETED_COUNT=0
for task_id in ${TEST_EPIC_ID}-{t1..t8}; do
  TASK_JSON=$(bd show "$task_id" --json 2>/dev/null)
  STATUS=$(echo "$TASK_JSON" | jq -r '.[0].status')
  if [ "$STATUS" = "closed" ]; then
    ((COMPLETED_COUNT++))
  else
    log_error "  $task_id: $status (expected: closed)"
  fi
done

log "Completed: $COMPLETED_COUNT/8 tasks"

# Verify layer execution order
log ""
log "Verifying layer execution order..."
if grep -q "Layer 0:" "$TEST_OUTPUT" && \
   grep -q "Layer 1:" "$TEST_OUTPUT" && \
   grep -q "Layer 2:" "$TEST_OUTPUT"; then
  log_success "✓ All 3 layers executed in order"
else
  log_error "✗ Layer execution order incorrect"
fi

# Verify parallel worker limit
log ""
log "Verifying parallel worker limit..."
# Check that Layer 0 had exactly 3 workers running in parallel
if grep -A 10 "LAYER 1/1:" "$TEST_OUTPUT" | grep -q "Worker 0" && \
   grep -A 10 "LAYER 1/1:" "$TEST_OUTPUT" | grep -q "Worker 1" && \
   grep -A 10 "LAYER 1/1:" "$TEST_OUTPUT" | grep -q "Worker 2"; then
  log_success "✓ Parallel workers executed correctly"
else
  log_error "✗ Parallel worker limit not enforced"
fi

# Verify worktree cleanup
log ""
log "Verifying worktree cleanup..."
WORKTREE_COUNT=$(find /tmp/agents -name "agent-skills" -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$WORKTREE_COUNT" -eq 0 ]; then
  log_success "✓ Worktrees cleaned up (0 remaining)"
else
  log_warning "⚠ $WORKTREE_COUNT worktree(s) remaining (may be from failures)"
fi

# Final result
log ""
log "=================================================="
log "RESULT"
log "=================================================="

if [ $EXIT_CODE -eq 0 ] && [ $COMPLETED_COUNT -eq 8 ]; then
  log_success "✓ E2E TEST PASSED"

  # Cleanup test epic
  log ""
  log "Cleaning up test epic..."
  for task_id in ${TEST_EPIC_ID}-{t1..t8} "$EPIC_ID"; do
    bd delete "$task_id" --force 2>/dev/null || true
  done

  log "Test epic deleted"
  exit 0
else
  log_error "✗ E2E TEST FAILED"

  # Keep test epic for debugging
  log ""
  log "Test epic preserved for debugging: $EPIC_ID"
  log "To cleanup manually: bd delete $EPIC_ID --force"

  exit 1
fi
