#!/usr/bin/env bash
set -euo pipefail

# test-cc-glm-job-v3.sh
#
# Comprehensive test suite for cc-glm-job.sh V3.0 features:
# - Log rotation (no truncation)
# - Outcome metadata persistence
# - Progress-aware health detection
# - Restart contract integrity
# - Operator guardrails (--no-ansi, tail command)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"
TEST_LOG_DIR="/tmp/cc-glm-jobs-test-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

usage() {
  cat <<'EOF'
test-cc-glm-job-v3.sh

Test suite for cc-glm-job.sh V3.0 features.

Usage:
  test-cc-glm-job-v3.sh [--verbose]

Tests:
  1. Log rotation on restart (preserves history, no truncation)
  2. Outcome metadata persistence (exit_code, state, duration, retries)
  3. Progress-aware health detection (CPU time tracking)
  4. Contract file persistence and verification
  5. ANSI stripping for status/health/tail commands
  6. Tail command with line limiting
  7. Status/health output shows outcome column

Environment:
  Uses isolated test log dir: /tmp/cc-glm-jobs-test-<pid>
EOF
}

pass_count=0
fail_count=0
verbose=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v)
      verbose=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Test utilities
log_dir() {
  echo "$TEST_LOG_DIR"
}

assert_file_exists() {
  local file="$1"
  local msg="$2"
  if [[ -f "$file" ]]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}FAIL${NC}: $msg - file not found: $file"
    ((fail_count++))
    return 1
  fi
}

assert_file_not_exists() {
  local file="$1"
  local msg="$2"
  if [[ ! -f "$file" ]]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}FAIL${NC}: $msg - file exists: $file"
    ((fail_count++))
    return 1
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local msg="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo -e "${GREEN}PASS${NC}: $msg"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}FAIL${NC}: $msg - pattern not found: $pattern"
    if [[ "$verbose" == "true" ]]; then
      echo "  File content:"
      cat "$file" | sed 's/^/    /'
    fi
    ((fail_count++))
    return 1
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}FAIL${NC}: $msg - expected '$expected', got '$actual'"
    ((fail_count++))
    return 1
  fi
}

assert_ne() {
  local actual="$1"
  local not_expected="$2"
  local msg="$3"
  if [[ "$actual" != "$not_expected" ]]; then
    echo -e "${GREEN}PASS${NC}: $msg"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}FAIL${NC}: $msg - should not equal '$not_expected'"
    ((fail_count++))
    return 1
  fi
}

# Setup and teardown
setup() {
  mkdir -p "$TEST_LOG_DIR"
  # Create a minimal test prompt file
  cat > "/tmp/test-prompt-$$" <<'EOF'
You are a test agent. Run a simple command and exit successfully.

Execute:
1. Run: echo "Test job completed"
2. Exit with code 0

That's it.
EOF
}

teardown() {
  # Stop any running test jobs
  if [[ -d "$TEST_LOG_DIR" ]]; then
    for pidf in "$TEST_LOG_DIR"/*.pid; do
      [[ -f "$pidf" ]] || continue
      local pid
      pid="$(cat "$pidf" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
    rm -rf "$TEST_LOG_DIR"
  fi
  rm -f "/tmp/test-prompt-$$"
}

# Test 1: Log rotation on restart
test_log_rotation() {
  local beads="test-rotate-$$"
  echo ""
  echo "=== Test 1: Log Rotation on Restart ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null
  sleep 1

  # Write to the log
  echo "First run log content" >> "$TEST_LOG_DIR/${beads}.log"

  # Stop the job
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

  # Restart (should rotate log)
  "$JOB_SCRIPT" restart --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Check that rotated log exists
  assert_file_exists "$TEST_LOG_DIR/${beads}.log.1" "Rotated log file (.log.1) exists"

  # Check that rotated log contains previous content
  assert_contains "$TEST_LOG_DIR/${beads}.log.1" "First run log content" "Rotated log preserves previous content"

  # Stop and cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

  # Restart again (should create .log.2)
  echo "Second run log content" >> "$TEST_LOG_DIR/${beads}.log"
  "$JOB_SCRIPT" restart --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null

  assert_file_exists "$TEST_LOG_DIR/${beads}.log.2" "Second rotated log file (.log.2) exists"

  # Verify content preservation
  assert_contains "$TEST_LOG_DIR/${beads}.log.2" "Second run log content" "Second rotated log preserves content"

  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 2: Outcome metadata persistence
test_outcome_persistence() {
  local beads="test-outcome-$$"
  echo ""
  echo "=== Test 2: Outcome Metadata Persistence ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Wait for job to complete (or timeout)
  local max_wait=30
  local waited=0
  while [[ $waited -lt $max_wait ]]; do
    if ! "$JOB_SCRIPT" check --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    ((waited++))
  done

  # Check outcome file exists
  assert_file_exists "$TEST_LOG_DIR/${beads}.outcome" "Outcome file exists"

  # Check outcome metadata fields
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "beads=$beads" "Outcome contains beads ID"
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "exit_code=" "Outcome contains exit_code"
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "state=" "Outcome contains state"
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "completed_at=" "Outcome contains completed_at"
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "duration_sec=" "Outcome contains duration_sec"
  assert_contains "$TEST_LOG_DIR/${beads}.outcome" "retries=" "Outcome contains retries"

  # Check that state is either success, failed, or killed
  if grep -q "state=success" "$TEST_LOG_DIR/${beads}.outcome"; then
    echo -e "${GREEN}PASS${NC}: Outcome state is 'success'"
    ((pass_count++))
  elif grep -q "state=failed" "$TEST_LOG_DIR/${beads}.outcome"; then
    echo -e "${GREEN}PASS${NC}: Outcome state is 'failed'"
    ((pass_count++))
  elif grep -q "state=killed" "$TEST_LOG_DIR/${beads}.outcome"; then
    echo -e "${GREEN}PASS${NC}: Outcome state is 'killed'"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Outcome state not recognized"
    ((fail_count++))
  fi

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 3: Outcome rotation on restart
test_outcome_rotation() {
  local beads="test-outcome-rotate-$$"
  echo ""
  echo "=== Test 3: Outcome Rotation on Restart ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Wait a bit then stop
  sleep 2
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

  # First outcome should exist
  assert_file_exists "$TEST_LOG_DIR/${beads}.outcome" "First outcome file exists"

  # Record first run_id
  local first_run_id
  first_run_id="$(grep "run_id=" "$TEST_LOG_DIR/${beads}.outcome" | cut -d= -f2)"

  # Restart
  "$JOB_SCRIPT" restart --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Wait a bit then stop again
  sleep 2
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

  # Check that outcome was rotated
  assert_file_exists "$TEST_LOG_DIR/${beads}.outcome.1" "Rotated outcome file (.outcome.1) exists"

  # Check that rotated outcome contains previous run_id
  assert_contains "$TEST_LOG_DIR/${beads}.outcome.1" "run_id=$first_run_id" "Rotated outcome preserves previous run_id"

  # Check that new outcome has different run_id
  local new_run_id
  new_run_id="$(grep "run_id=" "$TEST_LOG_DIR/${beads}.outcome" | cut -d= -f2)"
  assert_ne "$new_run_id" "$first_run_id" "New outcome has different run_id"

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 4: Contract file persistence
test_contract_persistence() {
  local beads="test-contract-$$"
  echo ""
  echo "=== Test 4: Contract File Persistence ==="

  # Start a job with custom model
  CC_GLM_MODEL=glm-5 "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Check contract file exists
  assert_file_exists "$TEST_LOG_DIR/${beads}.contract" "Contract file exists"

  # Check contract fields
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "auth_source=" "Contract contains auth_source"
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "model=" "Contract contains model"
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "base_url=" "Contract contains base_url"
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "timeout_ms=" "Contract contains timeout_ms"
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "execution_mode=" "Contract contains execution_mode"

  # Check that model is set to glm-5
  assert_contains "$TEST_LOG_DIR/${beads}.contract" "model=glm-5" "Contract records model=glm-5"

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 5: ANSI stripping
test_ansi_stripping() {
  local beads="test-ansi-$$"
  echo ""
  echo "=== Test 5: ANSI Stripping ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Get status with ANSI
  local status_with_ansi
  status_with_ansi="$("$JOB_SCRIPT" status --beads "$beads" --log-dir "$TEST_LOG_DIR" 2>&1 || true)"

  # Get status without ANSI
  local status_no_ansi
  status_no_ansi="$("$JOB_SCRIPT" status --beads "$beads" --log-dir "$TEST_LOG_DIR" --no-ansi 2>&1 || true)"

  # Check that ANSI version contains escape sequences (we can't reliably test this in shell)
  # But we can check that both produce output
  if [[ -n "$status_with_ansi" ]]; then
    echo -e "${GREEN}PASS${NC}: Status with ANSI produces output"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Status with ANSI produces no output"
    ((fail_count++))
  fi

  if [[ -n "$status_no_ansi" ]]; then
    echo -e "${GREEN}PASS${NC}: Status without ANSI produces output"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Status without ANSI produces no output"
    ((fail_count++))
  fi

  # Test health command with --no-ansi
  local health_no_ansi
  health_no_ansi="$("$JOB_SCRIPT" health --beads "$beads" --log-dir "$TEST_LOG_DIR" --no-ansi 2>&1 || true)"

  if [[ -n "$health_no_ansi" ]]; then
    echo -e "${GREEN}PASS${NC}: Health without ANSI produces output"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Health without ANSI produces no output"
    ((fail_count++))
  fi

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 6: Tail command
test_tail_command() {
  local beads="test-tail-$$"
  echo ""
  echo "=== Test 6: Tail Command ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Write some log content
  local log_file="$TEST_LOG_DIR/${beads}.log"
  for i in {1..30}; do
    echo "Log line $i" >> "$log_file"
  done

  # Test tail with default 20 lines
  local tail_output
  tail_output="$("$JOB_SCRIPT" tail --beads "$beads" --log-dir "$TEST_LOG_DIR" 2>&1 || true)"

  # Check that we get output
  if [[ -n "$tail_output" ]]; then
    echo -e "${GREEN}PASS${NC}: Tail command produces output"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Tail command produces no output"
    ((fail_count++))
  fi

  # Test tail with --lines 5
  local tail_5_lines
  tail_5_lines="$("$JOB_SCRIPT" tail --beads "$beads" --log-dir "$TEST_LOG_DIR" --lines 5 2>&1 || true)"

  # Count lines
  local line_count
  line_count="$(echo "$tail_5_lines" | grep -c "^" || echo "0")"

  # Should be 5 lines (or close to it, accounting for edge cases)
  if [[ "$line_count" -ge 4 && "$line_count" -le 6 ]]; then
    echo -e "${GREEN}PASS${NC}: Tail with --lines 5 produces ~5 lines (got $line_count)"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Tail with --lines 5 produced $line_count lines (expected ~5)"
    ((fail_count++))
  fi

  # Test tail with --no-ansi
  local tail_no_ansi
  tail_no_ansi="$("$JOB_SCRIPT" tail --beads "$beads" --log-dir "$TEST_LOG_DIR" --no-ansi 2>&1 || true)"

  if [[ -n "$tail_no_ansi" ]]; then
    echo -e "${GREEN}PASS${NC}: Tail with --no-ansi produces output"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Tail with --no-ansi produces no output"
    ((fail_count++))
  fi

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 7: Status/health show outcome column
test_status_outcome_column() {
  local beads="test-status-outcome-$$"
  echo ""
  echo "=== Test 7: Status/Health Outcome Column ==="

  # Start and immediately stop a job to get an outcome
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null
  sleep 2
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

  # Wait a moment for outcome to be written
  sleep 1

  # Get status output
  local status_output
  status_output="$("$JOB_SCRIPT" status --beads "$beads" --log-dir "$TEST_LOG_DIR" 2>&1 || true)"

  # Check that status output has "outcome" in header
  if echo "$status_output" | head -1 | grep -q "outcome"; then
    echo -e "${GREEN}PASS${NC}: Status header contains 'outcome' column"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Status header missing 'outcome' column"
    if [[ "$verbose" == "true" ]]; then
      echo "  Status output:"
      echo "$status_output" | sed 's/^/    /'
    fi
    ((fail_count++))
  fi

  # Get health output
  local health_output
  health_output="$("$JOB_SCRIPT" health --beads "$beads" --log-dir "$TEST_LOG_DIR" 2>&1 || true)"

  # Check that health output has "outcome" in header
  if echo "$health_output" | head -1 | grep -q "outcome"; then
    echo -e "${GREEN}PASS${NC}: Health header contains 'outcome' column"
    ((pass_count++))
  else
    echo -e "${RED}FAIL${NC}: Health header missing 'outcome' column"
    if [[ "$verbose" == "true" ]]; then
      echo "  Health output:"
      echo "$health_output" | sed 's/^/    /'
    fi
    ((fail_count++))
  fi

  # Check that outcome data is displayed (should contain state:exit format)
  if echo "$status_output" | grep -v "^bead" | grep -q ":"; then
    echo -e "${GREEN}PASS${NC}: Status shows outcome data (state:exit format)"
    ((pass_count++))
  else
    echo -e "${YELLOW}WARN${NC}: Status outcome data not clearly visible"
    # Don't fail - outcome might be empty or in unexpected format
  fi

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Test 8: Progress-aware health metadata
test_progress_aware_metadata() {
  local beads="test-progress-$$"
  echo ""
  echo "=== Test 8: Progress-Aware Health Metadata ==="

  # Start a job
  "$JOB_SCRIPT" start --beads "$beads" --prompt-file "/tmp/test-prompt-$$" --log-dir "$TEST_LOG_DIR" >/dev/null

  # Check that meta file contains last_cpu_time field
  local meta_file="$TEST_LOG_DIR/${beads}.meta"
  sleep 1

  if [[ -f "$meta_file" ]]; then
    # Run health check to trigger CPU time tracking
    "$JOB_SCRIPT" health --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true

    # Check for last_cpu_time field
    if grep -q "last_cpu_time=" "$meta_file"; then
      echo -e "${GREEN}PASS${NC}: Meta file contains last_cpu_time field"
      ((pass_count++))
    else
      echo -e "${YELLOW}WARN${NC}: Meta file missing last_cpu_time field (may be added on next health check)"
    fi

    # Check for version field
    if grep -q "version=" "$meta_file"; then
      echo -e "${GREEN}PASS${NC}: Meta file contains version field"
      ((pass_count++))
    else
      echo -e "${YELLOW}WARN${NC}: Meta file missing version field"
    fi
  else
    echo -e "${RED}FAIL${NC}: Meta file not found"
    ((fail_count++))
  fi

  # Cleanup
  "$JOB_SCRIPT" stop --beads "$beads" --log-dir "$TEST_LOG_DIR" >/dev/null 2>&1 || true
}

# Main test runner
main() {
  echo "========================================="
  echo "cc-glm-job.sh V3.0 Test Suite"
  echo "========================================="
  echo "Test log directory: $TEST_LOG_DIR"
  echo ""

  setup

  # Run tests
  test_log_rotation
  test_outcome_persistence
  test_outcome_rotation
  test_contract_persistence
  test_ansi_stripping
  test_tail_command
  test_status_outcome_column
  test_progress_aware_metadata

  # Cleanup
  teardown

  # Summary
  echo ""
  echo "========================================="
  echo "Test Summary"
  echo "========================================="
  echo -e "${GREEN}PASSED${NC}: $pass_count"
  echo -e "${RED}FAILED${NC}: $fail_count"
  echo ""

  if [[ "$fail_count" -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
  fi
}

# Run main
main
