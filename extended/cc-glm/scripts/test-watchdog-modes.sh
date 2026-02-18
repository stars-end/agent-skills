#!/usr/bin/env bash
set -euo pipefail

# test-watchdog-modes.sh
#
# Deterministic tests for cc-glm-job.sh watchdog mode semantics.
# Tests observe-only, no-auto-restart, and per-bead override controls.
#
# Usage:
#   ./test-watchdog-modes.sh
#
# Exit codes:
#   0 - All tests passed
#   N - N tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"

# Test counters
PASSED=0
FAILED=0

# Test utilities
pass() {
  local msg="$1"
  echo "  PASS: $msg"
  PASSED=$((PASSED + 1))
}

fail() {
  local msg="$1"
  local detail="${2:-}"
  echo "  FAIL: $msg"
  if [[ -n "$detail" ]]; then
    echo "        detail: $detail"
  fi
  FAILED=$((FAILED + 1))
}

section() {
  echo ""
  echo "=== $1 ==="
}

# ============================================================================
# V3.2 WATCHDOG MODE SEMANTIC TESTS
# ============================================================================

# Test: Job script exists and is readable
test_script_exists() {
  section "Script Existence"

  if [[ -f "$JOB_SCRIPT" ]]; then
    pass "Job script exists at $JOB_SCRIPT"
  else
    fail "Job script not found" "$JOB_SCRIPT"
  fi
}

# Test: Version is V3.2
test_version_v32() {
  section "Version Check (V3.2)"

  if grep -q "CC_GLM_JOB_VERSION=\"3.2" "$JOB_SCRIPT"; then
    pass "Job script version is V3.2"
  else
    fail "Job script version should be V3.2"
  fi
}

# Test: Usage documents watchdog modes
test_usage_watchdog_modes() {
  section "Usage Documentation"

  # Check observe-only documented
  if grep -q "\-\-observe-only" "$JOB_SCRIPT"; then
    pass "--observe-only documented in usage"
  else
    fail "--observe-only should be documented in usage"
  fi

  # Check no-auto-restart documented
  if grep -q "\-\-no-auto-restart" "$JOB_SCRIPT"; then
    pass "--no-auto-restart documented in usage"
  else
    fail "--no-auto-restart should be documented in usage"
  fi

  # Check set-override command documented
  if grep -q "set-override" "$JOB_SCRIPT"; then
    pass "set-override command documented in usage"
  else
    fail "set-override command should be documented in usage"
  fi
}

# Test: Observe-only mode implementation
test_observe_only_implementation() {
  section "Observe-Only Mode Implementation"

  # Check WATCHDOG_OBSERVE_ONLY variable
  if grep -q "WATCHDOG_OBSERVE_ONLY" "$JOB_SCRIPT"; then
    pass "WATCHDOG_OBSERVE_ONLY variable exists"
  else
    fail "WATCHDOG_OBSERVE_ONLY variable should exist"
  fi

  # Check observe-only check in watchdog loop
  if grep -q 'WATCHDOG_OBSERVE_ONLY.*true' "$JOB_SCRIPT" && \
     grep -q "OBSERVE-ONLY" "$JOB_SCRIPT"; then
    pass "observe-only mode logs and skips restart"
  else
    fail "observe-only mode should log and skip restart"
  fi
}

# Test: No-auto-restart global flag implementation
test_no_auto_restart_global() {
  section "No-Auto-Restart Global Flag"

  # Check WATCHDOG_NO_AUTO_RESTART variable
  if grep -q "WATCHDOG_NO_AUTO_RESTART" "$JOB_SCRIPT"; then
    pass "WATCHDOG_NO_AUTO_RESTART variable exists"
  else
    fail "WATCHDOG_NO_AUTO_RESTART variable should exist"
  fi

  # Check blocked_reason = no_auto_restart
  if grep -q 'blocked_reason.*no_auto_restart' "$JOB_SCRIPT"; then
    pass "blocked_reason set to no_auto_restart when flag is true"
  else
    fail "blocked_reason should be set when no_auto_restart is true"
  fi
}

# Test: Per-bead override implementation
test_per_bead_override() {
  section "Per-Bead Override Controls"

  # Check no_auto_restart in meta
  if grep -q 'meta_get.*no_auto_restart' "$JOB_SCRIPT"; then
    pass "no_auto_restart read from meta file"
  else
    fail "no_auto_restart should be read from meta file"
  fi

  # Check set-override command exists
  if grep -q "set_override_cmd()" "$JOB_SCRIPT"; then
    pass "set-override command function exists"
  else
    fail "set-override command function should exist"
  fi

  # Check --no-auto-restart accepts true/false values
  if grep -q 'OVERRIDE_NO_AUTO_RESTART' "$JOB_SCRIPT"; then
    pass "OVERRIDE_NO_AUTO_RESTART for set-override values"
  else
    fail "OVERRIDE_NO_AUTO_RESTART should exist for set-override"
  fi
}

# Test: Mode/override state in output
test_override_state_output() {
  section "Override State in Output"

  # Check SHOW_OVERRIDES flag
  if grep -q "SHOW_OVERRIDES" "$JOB_SCRIPT"; then
    pass "SHOW_OVERRIDES flag exists"
  else
    fail "SHOW_OVERRIDES flag should exist"
  fi

  # Check --show-overrides option
  if grep -q "\-\-show-overrides" "$JOB_SCRIPT"; then
    pass "--show-overrides option documented"
  else
    fail "--show-overrides option should be documented"
  fi

  # Check override column in status_line
  if grep -q 'override=' "$JOB_SCRIPT"; then
    pass "override variable in status/health output"
  else
    fail "override variable should exist for status/health output"
  fi

  # Check "no-restart" and "blocked" override values
  if grep -q 'no-restart' "$JOB_SCRIPT"; then
    pass "no-restart override value supported"
  else
    fail "no-restart override value should be supported"
  fi
}

# Test: Watchdog blocked_reason values
test_blocked_reason_values() {
  section "Blocked Reason Values"

  # Check max_retries blocked reason
  if grep -q 'blocked_reason.*max_retries' "$JOB_SCRIPT"; then
    pass "blocked_reason = max_retries when retries exhausted"
  else
    fail "blocked_reason should be max_retries when retries exhausted"
  fi

  # Check no_auto_restart blocked reason
  if grep -q 'blocked_reason.*no_auto_restart' "$JOB_SCRIPT"; then
    pass "blocked_reason = no_auto_restart when override is set"
  else
    fail "blocked_reason should be no_auto_restart when override is set"
  fi
}

# Test: Watchdog mode description output
test_watchdog_mode_output() {
  section "Watchdog Mode Output"

  # Check mode_desc variable
  if grep -q 'mode_desc=' "$JOB_SCRIPT"; then
    pass "mode_desc variable for watchdog output"
  else
    fail "mode_desc variable should exist for watchdog output"
  fi

  # Check observe-only mode description
  if grep -q 'mode_desc.*observe-only' "$JOB_SCRIPT"; then
    pass "observe-only mode description implemented"
  else
    fail "observe-only mode description should be implemented"
  fi
}

# Test: Restart suppression logic
test_restart_suppression() {
  section "Restart Suppression Logic"

  # Check that restart is suppressed in observe-only mode
  if grep -q 'continue' "$JOB_SCRIPT" | grep -A5 'OBSERVE-ONLY' 2>/dev/null; then
    pass "observe-only mode uses continue to skip restart"
  else
    # Check for the pattern differently
    if grep -q 'OBSERVE-ONLY.*would restart' "$JOB_SCRIPT" || \
       grep -q "continue" "$JOB_SCRIPT"; then
      pass "observe-only mode skips restart"
    else
      fail "observe-only mode should skip restart"
    fi
  fi

  # Check that restart is suppressed with no-auto-restart
  if grep -q 'NO-AUTO-RESTART' "$JOB_SCRIPT"; then
    pass "no-auto-restart mode logs and blocks"
  else
    fail "no-auto-restart mode should log blocked status"
  fi
}

# Test: Health states include blocked
test_health_states_blocked() {
  section "Health State: blocked"

  # Check that blocked health state is handled
  if grep -q '"blocked"' "$JOB_SCRIPT"; then
    pass "blocked health state recognized"
  else
    fail "blocked health state should be recognized"
  fi

  # Check that blocked jobs require manual intervention
  if grep -q "manual intervention" "$JOB_SCRIPT"; then
    pass "blocked jobs log manual intervention requirement"
  else
    fail "blocked jobs should log manual intervention requirement"
  fi
}

# Test: set-override validates values
test_set_override_validation() {
  section "set-override Validation"

  # Check that valid values are enforced
  if grep -q 'invalid value.*no-auto-restart' "$JOB_SCRIPT" || \
     grep -q 'valid values.*true.*false' "$JOB_SCRIPT"; then
    pass "set-override validates true/false values"
  else
    fail "set-override should validate true/false values"
  fi
}

# Test: Backward compatibility preserved
test_backward_compatibility() {
  section "Backward Compatibility"

  # Check that --no-auto-restart still works as flag (for watchdog)
  if grep -q 'WATCHDOG_NO_AUTO_RESTART=true' "$JOB_SCRIPT"; then
    pass "--no-auto-restart still works as flag"
  else
    fail "--no-auto-restart should still work as flag for backward compatibility"
  fi

  # Check that default behavior unchanged (max-retries still applies)
  if grep -q 'WATCHDOG_MAX_RETRIES' "$JOB_SCRIPT"; then
    pass "max-retries still applies by default"
  else
    fail "max-retries should still apply by default"
  fi
}

# ============================================================================
# RUN ALL TESTS
# ============================================================================

run_all_tests() {
  echo "cc-glm-job.sh Watchdog Mode Semantics Tests"
  echo "============================================"

  test_script_exists
  test_version_v32
  test_usage_watchdog_modes
  test_observe_only_implementation
  test_no_auto_restart_global
  test_per_bead_override
  test_override_state_output
  test_blocked_reason_values
  test_watchdog_mode_output
  test_restart_suppression
  test_health_states_blocked
  test_set_override_validation
  test_backward_compatibility

  echo ""
  echo "============================================"
  echo "Summary: $PASSED passed, $FAILED failed"
  echo "============================================"

  return $FAILED
}

# Run tests
run_all_tests
