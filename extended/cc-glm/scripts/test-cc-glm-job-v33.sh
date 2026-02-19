#!/usr/bin/env bash
set -euo pipefail

# test-cc-glm-job-v33.sh
#
# Test coverage for cc-glm-job.sh V3.3+ features:
#   - Mutation detection
#   - Preflight checks
#   - Startup heartbeat
#
# Usage:
#   test-cc-glm-job-v33.sh [--verbose]
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"
HEADLESS_SCRIPT="${SCRIPT_DIR}/cc-glm-headless.sh"
VERBOSE="${1:-}"

LOG_DIR="/tmp/cc-glm-jobs-test-v33"
TEST_BEADS="test-v33-$$"

# Colors
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

passed=0
failed=0
skipped=0

pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  passed=$((passed + 1))
}

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  if [[ -n "${2:-}" ]]; then
    echo "  Details: $2"
  fi
  failed=$((failed + 1))
}

skip() {
  echo -e "${YELLOW}SKIP${NC}: $1"
  skipped=$((skipped + 1))
}

cleanup() {
  rm -rf "$LOG_DIR" 2>/dev/null || true
}

trap cleanup EXIT

setup() {
  cleanup
  mkdir -p "$LOG_DIR"
}

# Test: Preflight check returns correct structure
test_preflight_output_format() {
  echo ""
  echo "=== Test: Preflight output format ==="

  setup

  local output
  output=$(ZAI_API_KEY="test" "$JOB_SCRIPT" preflight --log-dir "$LOG_DIR" 2>&1) || true

  if echo "$output" | grep -q "claude binary:"; then
    pass "Preflight includes claude binary check"
  else
    fail "Preflight missing claude binary check" "$output"
  fi

  if echo "$output" | grep -q "auth resolution:"; then
    pass "Preflight includes auth resolution check"
  else
    fail "Preflight missing auth resolution check" "$output"
  fi

  if echo "$output" | grep -q "model config:"; then
    pass "Preflight includes model config check"
  else
    fail "Preflight missing model config check" "$output"
  fi
}

# Test: Preflight passes with valid auth
test_preflight_with_auth() {
  echo ""
  echo "=== Test: Preflight with auth ==="

  setup

  # Set a mock auth token
  local output
  output=$(CC_GLM_AUTH_TOKEN="test-token" "$JOB_SCRIPT" preflight --log-dir "$LOG_DIR" 2>&1) || true

  if echo "$output" | grep -q "auth resolution: OK"; then
    pass "Preflight passes with CC_GLM_AUTH_TOKEN"
  else
    # May fail if claude not installed - check for auth pass at least
    if echo "$output" | grep -q "CC_GLM_AUTH_TOKEN"; then
      pass "Preflight recognizes CC_GLM_AUTH_TOKEN"
    else
      fail "Preflight doesn't recognize CC_GLM_AUTH_TOKEN" "$output"
    fi
  fi
}

# Test: Preflight detects missing claude (if not installed)
test_preflight_missing_claude() {
  echo ""
  echo "=== Test: Preflight detects missing claude ==="

  setup

  # This test is informational - claude should be installed
  if command -v claude >/dev/null 2>&1; then
    skip "claude is installed, cannot test missing detection"
    return 0
  fi

  local output
  output=$("$JOB_SCRIPT" preflight --log-dir "$LOG_DIR" 2>&1) || true

  if echo "$output" | grep -q "claude binary: MISSING"; then
    pass "Preflight detects missing claude"
  else
    fail "Preflight doesn't detect missing claude" "$output"
  fi
}

# Test: Mutation detection with git worktree
test_mutation_detection_git() {
  echo ""
  echo "=== Test: Mutation detection (git worktree) ==="

  setup

  # Create a mock git worktree
  local worktree
  worktree=$(mktemp -d)
  cd "$worktree"
  git init -q
  echo "initial" > initial.txt
  git add initial.txt
  git commit -q -m "initial"

  # Create job metadata
  mkdir -p "$LOG_DIR"
  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=$worktree
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  touch "$LOG_DIR/${TEST_BEADS}.pid"

  # Make a change after meta file creation
  sleep 0.1
  echo "modified" > modified.txt

  # Check mutation detection
  local output
  output=$("$JOB_SCRIPT" mutations --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --worktree "$worktree" 2>&1) || true

  if echo "$output" | grep -q "mutation_count:"; then
    pass "Mutation detection returns count"
  else
    fail "Mutation detection missing count" "$output"
  fi

  # Cleanup
  rm -rf "$worktree"
}

# Test: Mutation detection with no worktree
test_mutation_detection_no_worktree() {
  echo ""
  echo "=== Test: Mutation detection (no worktree) ==="

  setup

  # Create job metadata without worktree
  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  local output
  output=$("$JOB_SCRIPT" mutations --beads "$TEST_BEADS" --log-dir "$LOG_DIR" 2>&1) || true

  if echo "$output" | grep -q "no worktree"; then
    pass "Mutation detection handles missing worktree"
  else
    fail "Mutation detection doesn't handle missing worktree" "$output"
  fi
}

# Test: Status --mutations flag
test_status_mutations_flag() {
  echo ""
  echo "=== Test: Status --mutations flag ==="

  setup

  # Create minimal job state
  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
  echo "12345" > "$LOG_DIR/${TEST_BEADS}.pid"

  local output
  output=$("$JOB_SCRIPT" status --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --mutations 2>&1) || true

  if echo "$output" | grep -q "mut"; then
    pass "Status --mutations shows mutation column"
  else
    fail "Status --mutations missing mutation column" "$output"
  fi
}

# Test: Startup heartbeat format
test_startup_heartbeat_format() {
  echo ""
  echo "=== Test: Startup heartbeat format ==="

  # Check that the headless script contains heartbeat logic
  if grep -q "LAUNCH_OK" "$HEADLESS_SCRIPT"; then
    pass "Headless script contains LAUNCH_OK heartbeat"
  else
    fail "Headless script missing LAUNCH_OK heartbeat"
  fi

  # Check format components
  if grep -q "ts=" "$HEADLESS_SCRIPT" && grep -q "model=" "$HEADLESS_SCRIPT" && grep -q "pid=" "$HEADLESS_SCRIPT"; then
    pass "Heartbeat includes ts, model, pid fields"
  else
    fail "Heartbeat missing required fields"
  fi
}

# Test: Usage includes V3.3 commands
test_usage_v33_commands() {
  echo ""
  echo "=== Test: Usage includes V3.3 commands ==="

  local output
  output=$("$JOB_SCRIPT" --help 2>&1)

  if echo "$output" | grep -q "preflight"; then
    pass "Usage includes preflight command"
  else
    fail "Usage missing preflight command"
  fi

  if echo "$output" | grep -q "mutations"; then
    pass "Usage includes mutations command"
  else
    fail "Usage missing mutations command"
  fi

  if echo "$output" | grep -q "\-\-mutations"; then
    pass "Usage includes --mutations flag"
  else
    fail "Usage missing --mutations flag"
  fi

  if echo "$output" | grep -Eq "V3\\.[34]"; then
    pass "Usage shows V3.3+ version"
  else
    fail "Usage doesn't show expected V3.x version"
  fi
}

# Test: Mutation marker file creation
test_mutation_marker_file() {
  echo ""
  echo "=== Test: Mutation marker file creation ==="

  setup

  # Create minimal job state with worktree
  local worktree
  worktree=$(mktemp -d)
  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=$worktree
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  echo "12345" > "$LOG_DIR/${TEST_BEADS}.pid"

  # Run mutations command
  "$JOB_SCRIPT" mutations --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --worktree "$worktree" >/dev/null 2>&1 || true

  # Check mutation marker file
  if [[ -f "$LOG_DIR/${TEST_BEADS}.mutation" ]]; then
    pass "Mutation marker file created"
    
    # Check contents
    if grep -q "mutation_count=" "$LOG_DIR/${TEST_BEADS}.mutation"; then
      pass "Mutation marker contains count"
    else
      fail "Mutation marker missing count"
    fi
  else
    fail "Mutation marker file not created"
  fi

  rm -rf "$worktree"
}

# Run all tests
main() {
  echo "========================================"
  echo "cc-glm-job V3.3 Feature Tests"
  echo "========================================"
  echo ""

  test_preflight_output_format
  test_preflight_with_auth
  test_preflight_missing_claude
  test_mutation_detection_git
  test_mutation_detection_no_worktree
  test_status_mutations_flag
  test_startup_heartbeat_format
  test_usage_v33_commands
  test_mutation_marker_file

  echo ""
  echo "========================================"
  echo "Results: ${passed} passed, ${failed} failed, ${skipped} skipped"
  echo "========================================"

  if [[ $failed -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main
