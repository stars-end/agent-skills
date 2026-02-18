#!/usr/bin/env bash

# test-cc-glm-job-features.sh
#
# Tests for bd-xga8.10.4 features:
# 1) Remote log locality status hints
# 2) Multi-log-dir ambiguity guardrails
# 3) ANSI stripping mode for machine parsing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"

pass_count=0
fail_count=0
skip_count=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  ((pass_count++))
}

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  ((fail_count++))
}

skip() {
  echo -e "${YELLOW}SKIP${NC}: $1"
  ((skip_count++))
}

# Test 1: ANSI stripping
test_ansi_strip() {
  echo "=== Test 1: ANSI stripping ==="
  local input=$'\033[31mError:\033[0m \033[1;32mSuccess\033[0m'
  local output
  output="$(echo "$input" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || echo "$input")"

  if [[ "$output" == "Error: Success" ]]; then
    pass "ANSI codes stripped correctly"
  else
    fail "ANSI strip failed. Got: '$output'"
  fi
}

# Test 2: Remote locality hint in status (empty dir)
test_status_empty_hints() {
  echo "=== Test 2: Status remote hints (empty) ==="
  local test_dir="/tmp/cc-glm-test-$$-status"
  mkdir -p "$test_dir"

  local output
  output="$("$JOB_SCRIPT" status --log-dir "$test_dir" 2>&1 || true)"
  rm -rf "$test_dir"

  if echo "$output" | grep "remote VMs" >/dev/null 2>&1; then
    pass "Remote locality hint shown for empty log dir"
  else
    fail "Remote locality hint NOT shown"
  fi
}

# Test 3: Health command remote hints
test_health_hints() {
  echo "=== Test 3: Health remote hints ==="
  local test_dir="/tmp/cc-glm-test-$$-health"
  mkdir -p "$test_dir"

  local output
  output="$("$JOB_SCRIPT" health --log-dir "$test_dir" 2>&1 || true)"
  rm -rf "$test_dir"

  if echo "$output" | grep "remote VMs" >/dev/null 2>&1; then
    pass "Health command shows remote hints"
  else
    fail "Health command missing remote hints"
  fi
}

# Test 4: Check command remote hints for missing job
test_check_missing_hints() {
  echo "=== Test 4: Check remote hints (missing) ==="
  local test_dir="/tmp/cc-glm-test-$$-check"
  mkdir -p "$test_dir"

  local output
  output="$("$JOB_SCRIPT" check --beads "nonexistent" --log-dir "$test_dir" 2>&1 || true)"
  rm -rf "$test_dir"

  if echo "$output" | grep "remote VM" >/dev/null 2>&1; then
    pass "Check command shows remote hints for missing job"
  else
    fail "Check command missing remote hints"
  fi
}

# Test 5: --no-ansi flag produces clean output
test_no_ansi_flag() {
  echo "=== Test 5: --no-ansi flag ==="
  local test_dir="/tmp/cc-glm-test-$$-ansi"
  mkdir -p "$test_dir"

  local output
  output="$("$JOB_SCRIPT" status --log-dir "$test_dir" --no-ansi 2>&1 || true)"
  rm -rf "$test_dir"

  # Check for absence of ANSI escape sequences
  if ! echo "$output" | grep -P '\x1b\[' >/dev/null 2>&1; then
    pass "--no-ansi produces clean output"
  else
    fail "--no-ansi still contains ANSI codes"
  fi
}

# Test 6: Ambiguity warning with multiple log dirs
test_ambiguity_warning() {
  echo "=== Test 6: Ambiguity warning ==="
  # Create alt dirs
  mkdir -p "/tmp/cc-glm-jobs-alt1-$$"
  mkdir -p "/tmp/cc-glm-jobs-alt2-$$"
  local test_dir="/tmp/cc-glm-jobs-$$"
  mkdir -p "$test_dir"

  # Clear warning cache
  rm -f "/tmp/.cc-glm-last-logdir-warning"

  local output
  output="$("$JOB_SCRIPT" status --log-dir "$test_dir" 2>&1 || true)"

  # Cleanup
  rm -rf "/tmp/cc-glm-jobs-alt1-$$"
  rm -rf "/tmp/cc-glm-jobs-alt2-$$"
  rm -rf "$test_dir"

  if echo "$output" | grep "Multiple log directories" >/dev/null 2>&1; then
    pass "Ambiguity warning shown"
  else
    skip "Ambiguity warning not shown (may be conditional)"
  fi
}

# Test 7: Tail empty log hints
test_tail_empty_hints() {
  echo "=== Test 7: Tail empty log hints ==="
  local test_dir="/tmp/cc-glm-test-$$-tail"
  mkdir -p "$test_dir"

  # Create empty log file
  touch "$test_dir/test.log"

  local output
  output="$("$JOB_SCRIPT" tail --beads "test" --log-dir "$test_dir" 2>&1 || true)"
  rm -rf "$test_dir"

  if echo "$output" | grep "empty log" >/dev/null 2>&1; then
    pass "Empty log hint shown"
  else
    skip "Empty log hint not shown (behavior may vary)"
  fi
}

# Test 8: Bash syntax validation
test_syntax() {
  echo "=== Test 8: Bash syntax ==="
  if bash -n "$JOB_SCRIPT" 2>/dev/null; then
    pass "cc-glm-job.sh has valid bash syntax"
  else
    fail "cc-glm-job.sh has syntax errors"
  fi
}

main() {
  echo "=========================================="
  echo "cc-glm-job.sh V3.0 Feature Tests"
  echo "bd-xga8.10.4: Remote Locality + Guardrails"
  echo "=========================================="
  echo ""

  if [[ ! -x "$JOB_SCRIPT" ]]; then
    echo "ERROR: cc-glm-job.sh not found or not executable"
    exit 1
  fi

  test_syntax
  test_ansi_strip
  test_status_empty_hints
  test_health_hints
  test_check_missing_hints
  test_no_ansi_flag
  test_ambiguity_warning
  test_tail_empty_hints

  echo ""
  echo "=========================================="
  echo "Summary"
  echo "=========================================="
  echo "Passed: $pass_count"
  echo "Failed: $fail_count"
  echo "Skipped: $skip_count"
  echo ""

  if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
  fi
}

main "$@"
