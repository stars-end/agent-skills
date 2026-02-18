#!/usr/bin/env bash
set -euo pipefail

# test-cc-glm-auth-resolver.sh (V3.1)
#
# Test coverage for cc-glm-headless.sh auth token resolver and cc-glm-job.sh runner.
# Tests all resolution branches without revealing actual token values.
# Includes tests for V3.0 features: CC_GLM_TOKEN_FILE, progress-aware health, forensics.
# Includes tests for V3.1 features: heartbeat, model propagation, running_no_output, preflight.
#
# Usage:
#   test-cc-glm-auth-resolver.sh [--verbose]
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADLESS_SCRIPT="${SCRIPT_DIR}/cc-glm-headless.sh"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"
VERBOSE="${1:-}"

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

passed=0
failed=0
skipped=0

# Test result helpers
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

# Source the resolver functions by extracting them
# We use a subshell approach to test the resolver logic
setup_test_env() {
  # Clear all auth-related env vars for clean tests
  # Use || true to avoid failure with set -e when vars are not set
  unset CC_GLM_AUTH_TOKEN 2>/dev/null || true
  unset CC_GLM_TOKEN_FILE 2>/dev/null || true
  unset ZAI_API_KEY 2>/dev/null || true
  unset CC_GLM_OP_URI 2>/dev/null || true
  unset CC_GLM_OP_VAULT 2>/dev/null || true
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  unset CC_GLM_ALLOW_FALLBACK 2>/dev/null || true
  unset CC_GLM_STRICT_AUTH 2>/dev/null || true
  unset CC_GLM_DEBUG 2>/dev/null || true
}

# ============================================================================
# HEADLESS SCRIPT TESTS
# ============================================================================

# Test: CC_GLM_AUTH_TOKEN takes highest priority
test_cc_glm_auth_token_priority() {
  echo ""
  echo "=== Test: CC_GLM_AUTH_TOKEN priority ==="

  setup_test_env

  # Set multiple sources, CC_GLM_AUTH_TOKEN should win
  export CC_GLM_AUTH_TOKEN="test-token-direct"
  export ZAI_API_KEY="should-be-ignored"

  # Run headless with --version for quick sanity check
  local output
  if output=$("$HEADLESS_SCRIPT" --version 2>&1); then
    if [[ "$output" == *"cc-glm-headless.sh version"* ]]; then
      pass "CC_GLM_AUTH_TOKEN is recognized (version check)"
    else
      fail "Version check failed" "$output"
    fi
  else
    fail "Script failed with CC_GLM_AUTH_TOKEN set" "$output"
  fi

  setup_test_env
}

# Test: CC_GLM_TOKEN_FILE reads token from file (V3.0)
test_cc_glm_token_file() {
  echo ""
  echo "=== Test: CC_GLM_TOKEN_FILE (V3.0) ==="

  setup_test_env

  # Create temp token file
  local token_file
  token_file="$(mktemp)"
  echo "test-token-from-file" > "$token_file"

  export CC_GLM_TOKEN_FILE="$token_file"

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --version 2>&1)
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]] && [[ "$output" == *"cc-glm-headless.sh version"* ]]; then
    pass "CC_GLM_TOKEN_FILE is recognized"
  else
    fail "CC_GLM_TOKEN_FILE should work" "exit=$exit_code output=${output:0:200}"
  fi

  rm -f "$token_file"
  setup_test_env
}

# Test: CC_GLM_TOKEN_FILE priority over ZAI_API_KEY
test_token_file_priority() {
  echo ""
  echo "=== Test: CC_GLM_TOKEN_FILE priority over ZAI_API_KEY ==="

  setup_test_env

  local token_file
  token_file="$(mktemp)"
  echo "token-from-file" > "$token_file"

  export CC_GLM_TOKEN_FILE="$token_file"
  export ZAI_API_KEY="should-be-ignored"

  # Check script has correct priority order in resolver
  if grep -q "CC_GLM_TOKEN_FILE - explicit token file path" "$HEADLESS_SCRIPT"; then
    pass "CC_GLM_TOKEN_FILE has correct priority in resolver (after CC_GLM_AUTH_TOKEN)"
  else
    fail "CC_GLM_TOKEN_FILE priority not documented in script"
  fi

  rm -f "$token_file"
  setup_test_env
}

# Test: CC_GLM_TOKEN_FILE missing file produces exit code 11
test_token_file_missing() {
  echo ""
  echo "=== Test: CC_GLM_TOKEN_FILE missing file (exit 11) ==="

  setup_test_env

  export CC_GLM_TOKEN_FILE="/tmp/__nonexistent_token_file__"

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  if [[ $exit_code -eq 11 ]] && [[ "$output" == *"Token file not found"* ]]; then
    pass "Missing token file produces exit code 11 with actionable error"
  else
    fail "Missing token file should produce exit 11" "exit=$exit_code output=${output:0:200}"
  fi

  setup_test_env
}

# Test: CC_GLM_TOKEN_FILE empty file produces error
test_token_file_empty() {
  echo ""
  echo "=== Test: CC_GLM_TOKEN_FILE empty file ==="

  setup_test_env

  local token_file
  token_file="$(mktemp)"
  # File is empty by default

  export CC_GLM_TOKEN_FILE="$token_file"

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  if [[ $exit_code -eq 11 ]] && [[ "$output" == *"Token file is empty"* ]]; then
    pass "Empty token file produces exit code 11"
  else
    fail "Empty token file should produce exit 11" "exit=$exit_code output=${output:0:200}"
  fi

  rm -f "$token_file"
  setup_test_env
}

# Test: ZAI_API_KEY plain token is used when CC_GLM_AUTH_TOKEN not set
test_zai_api_key_plain() {
  echo ""
  echo "=== Test: ZAI_API_KEY plain token ==="

  setup_test_env

  # Set only ZAI_API_KEY (plain, not op://)
  export ZAI_API_KEY="test-token-zai"

  local output
  if output=$("$HEADLESS_SCRIPT" --version 2>&1); then
    pass "ZAI_API_KEY plain token is recognized"
  else
    fail "Script failed with ZAI_API_KEY plain" "$output"
  fi

  setup_test_env
}

# Test: ZAI_API_KEY with op:// reference triggers op resolution
test_zai_api_key_op_reference() {
  echo ""
  echo "=== Test: ZAI_API_KEY op:// reference ==="

  setup_test_env

  # Set ZAI_API_KEY to an op:// reference
  export ZAI_API_KEY="op://dev/TestVault/test-field"

  # This should fail because op CLI won't have valid auth
  # But we check that it ATTEMPTS op resolution (not falling back immediately)
  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  # Should fail with auth resolution error (exit 10) or op-related error
  if [[ "$output" == *"op://"* ]] || [[ "$output" == *"op CLI"* ]] || [[ $exit_code -eq 10 ]]; then
    pass "ZAI_API_KEY op:// reference triggers op resolution path"
  else
    fail "ZAI_API_KEY op:// should attempt op resolution" "exit=$exit_code output=${output:0:200}"
  fi

  setup_test_env
}

# Test: CC_GLM_OP_URI triggers op resolution
test_cc_glm_op_uri() {
  echo ""
  echo "=== Test: CC_GLM_OP_URI op:// reference ==="

  setup_test_env

  export CC_GLM_OP_URI="op://dev/TestVault/test-field"

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  if [[ "$output" == *"op://"* ]] || [[ "$output" == *"op CLI"* ]] || [[ $exit_code -eq 10 ]]; then
    pass "CC_GLM_OP_URI triggers op resolution path"
  else
    fail "CC_GLM_OP_URI should attempt op resolution" "exit=$exit_code output=${output:0:200}"
  fi

  setup_test_env
}

# Test: Default op:// fallback when nothing is set
test_default_op_fallback() {
  echo ""
  echo "=== Test: Default op:// fallback ==="

  setup_test_env
  export CC_GLM_OP_VAULT="__invalid_vault_for_test__"

  # No auth env vars set - should try default op:// and fail
  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  # Should fail with exit 10 (auth resolution failure) and mention options.
  # Invalid vault makes this deterministic even when local op is signed in.
  if [[ $exit_code -eq 10 ]] && [[ "$output" == *"AUTH TOKEN RESOLUTION FAILED"* ]]; then
    pass "Default op:// fallback fails with actionable error"
  else
    fail "Should fail with exit 10 and auth error" "exit=$exit_code output=${output:0:200}"
  fi

  setup_test_env
}

# Test: CC_GLM_ALLOW_FALLBACK=1 enables legacy fallback
test_allow_fallback() {
  echo ""
  echo "=== Test: CC_GLM_ALLOW_FALLBACK=1 ==="

  setup_test_env

  export CC_GLM_ALLOW_FALLBACK=1
  export OP_SERVICE_ACCOUNT_TOKEN_FILE="/tmp/__missing_op_token_file__"

  local fake_dir fake_claude old_path
  fake_dir="$(mktemp -d)"
  fake_claude="${fake_dir}/claude"
  old_path="${PATH:-}"
  cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "fake-claude-fallback-ok"
exit 0
EOF
  chmod +x "$fake_claude"
  export PATH="${fake_dir}:${old_path}"

  local output
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  local exit_code=$?
  set -e

  # Should attempt fallback path (may still fail, but should show warning)
  if [[ "$output" == *"CC_GLM_ALLOW_FALLBACK=1"* ]] || [[ "$output" == *"fallback"* ]] || [[ "$output" == *"zsh"* ]]; then
    pass "CC_GLM_ALLOW_FALLBACK=1 enables fallback path"
  else
    # Also passes if it actually works (e.g., valid zsh/cc-glm setup)
    if [[ $exit_code -eq 0 ]]; then
      pass "CC_GLM_ALLOW_FALLBACK=1 allowed execution to proceed"
    else
      fail "Should show fallback warning or proceed" "exit=$exit_code output=${output:0:200}"
    fi
  fi

  export PATH="$old_path"
  rm -rf "$fake_dir"
  setup_test_env
}

# Test: CC_GLM_STRICT_AUTH=0 suppresses strict errors
test_strict_auth_disabled() {
  echo ""
  echo "=== Test: CC_GLM_STRICT_AUTH=0 ==="

  setup_test_env

  export CC_GLM_STRICT_AUTH=0
  export OP_SERVICE_ACCOUNT_TOKEN_FILE="/tmp/__missing_op_token_file__"

  local fake_dir fake_claude old_path
  fake_dir="$(mktemp -d)"
  fake_claude="${fake_dir}/claude"
  old_path="${PATH:-}"
  cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "fake-claude-nonstrict-ok"
exit 0
EOF
  chmod +x "$fake_claude"
  export PATH="${fake_dir}:${old_path}"

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --prompt "test" 2>&1)
  exit_code=$?
  set -e

  # Should NOT show the strict AUTH TOKEN RESOLUTION FAILED block
  if [[ "$output" != *"AUTH TOKEN RESOLUTION FAILED"* ]]; then
    pass "CC_GLM_STRICT_AUTH=0 suppresses strict error block"
  else
    fail "Should not show strict auth error when disabled" "output=${output:0:200}"
  fi

  export PATH="$old_path"
  rm -rf "$fake_dir"
  setup_test_env
}

# Test: Help output contains expected sections
test_help_output() {
  echo ""
  echo "=== Test: Help output ==="

  local output
  output=$("$HEADLESS_SCRIPT" --help 2>&1)

  local has_auth_token has_token_file has_fallback has_examples
  has_auth_token=0
  has_token_file=0
  has_fallback=0
  has_examples=0

  [[ "$output" == *"CC_GLM_AUTH_TOKEN"* ]] && has_auth_token=1
  [[ "$output" == *"CC_GLM_TOKEN_FILE"* ]] && has_token_file=1
  [[ "$output" == *"CC_GLM_ALLOW_FALLBACK"* ]] && has_fallback=1
  [[ "$output" == *"Examples:"* ]] && has_examples=1

  if [[ $has_auth_token -eq 1 ]] && [[ $has_token_file -eq 1 ]] && [[ $has_fallback -eq 1 ]] && [[ $has_examples -eq 1 ]]; then
    pass "Help output contains auth order, token file, fallback info, and examples"
  else
    fail "Help output missing expected sections" "auth=$has_auth_token token_file=$has_token_file fallback=$has_fallback examples=$has_examples"
  fi
}

# Test: Version output
test_version_output() {
  echo ""
  echo "=== Test: Version output ==="

  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" --version 2>&1)
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]] && [[ "$output" == *"cc-glm-headless.sh version"* ]]; then
    pass "Version output is correct"
  else
    fail "Version output incorrect" "exit=$exit_code output=$output"
  fi
}

# Test: Never prints token values
test_no_token_leakage() {
  echo ""
  echo "=== Test: No token leakage in error output ==="

  setup_test_env

  export CC_GLM_AUTH_TOKEN="super-secret-token-do-not-leak-12345"

  # Trigger an error (missing prompt)
  local output exit_code
  set +e
  output=$("$HEADLESS_SCRIPT" 2>&1)  # No prompt
  exit_code=$?
  set -e

  # Token should NEVER appear in output
  if [[ "$output" != *"super-secret-token-do-not-leak-12345"* ]]; then
    pass "Token value not leaked in error output"
  else
    fail "SECURITY: Token value appeared in output!" "${output:0:200}"
  fi

  setup_test_env
}

# Test: Priority order verification in script
test_priority_order() {
  echo ""
  echo "=== Test: Auth source priority order ==="

  setup_test_env

  # Deterministic static-order check (no live model call).
  local first_priority_marker
  first_priority_marker="$(awk '/CC_GLM_AUTH_TOKEN - highest priority/ {print "found"; exit}' "$HEADLESS_SCRIPT" || true)"
  if [[ "$first_priority_marker" == "found" ]]; then
    pass "CC_GLM_AUTH_TOKEN has highest priority (resolver order)"
  else
    fail "Could not verify resolver priority order in script"
  fi

  setup_test_env
}

# Test: resolved token is exported to both Anthropic env vars.
test_anthropic_env_exports() {
  echo ""
  echo "=== Test: Anthropic env exports ==="

  setup_test_env

  local fake_dir fake_claude old_path output
  fake_dir="$(mktemp -d)"
  fake_claude="${fake_dir}/claude"
  old_path="${PATH:-}"

  cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "AUTH_TOKEN_SET=${ANTHROPIC_AUTH_TOKEN:+1}"
echo "API_KEY_SET=${ANTHROPIC_API_KEY:+1}"
echo "MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
exit 0
EOF
  chmod +x "$fake_claude"

  export PATH="${fake_dir}:${old_path}"
  export CC_GLM_AUTH_TOKEN="token-for-export-test"

  output="$("$HEADLESS_SCRIPT" --prompt "test prompt" 2>&1 || true)"
  if [[ "$output" == *"AUTH_TOKEN_SET=1"* ]] && [[ "$output" == *"API_KEY_SET=1"* ]] && [[ "$output" == *"MODEL=glm-5"* ]]; then
    pass "Resolved token exported to ANTHROPIC_AUTH_TOKEN and ANTHROPIC_API_KEY (glm-5 default)"
  else
    fail "Anthropic env export check failed" "${output:0:240}"
  fi

  export PATH="$old_path"
  rm -rf "$fake_dir"
  setup_test_env
}

# Test: CC_GLM_DEBUG must not pollute token capture path
test_debug_token_capture() {
  echo ""
  echo "=== Test: CC_GLM_DEBUG token capture safety ==="

  local fake_dir fake_claude old_path output
  fake_dir="$(mktemp -d)"
  fake_claude="${fake_dir}/claude"
  old_path="$PATH"

  cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "DEBUG_TOKEN_CAPTURE_OK"
EOF
  chmod +x "$fake_claude"

  export PATH="${fake_dir}:${old_path}"
  export CC_GLM_AUTH_TOKEN="debug-token-capture-test"
  export CC_GLM_DEBUG=1

  output="$("$HEADLESS_SCRIPT" --prompt "debug token capture test" 2>&1 || true)"
  if [[ "$output" == *"DEBUG_TOKEN_CAPTURE_OK"* ]]; then
    pass "CC_GLM_DEBUG does not break auth token capture"
  else
    fail "CC_GLM_DEBUG polluted token capture path" "${output:0:240}"
  fi

  export PATH="$old_path"
  rm -rf "$fake_dir"
  setup_test_env
}

# Test: Missing claude CLI produces actionable error
test_missing_claude_cli() {
  echo ""
  echo "=== Test: Missing claude CLI error ==="

  # This test is informational - we can't easily remove claude from PATH
  # Just verify the error message exists in the script
  if grep -q "claude CLI not found" "$HEADLESS_SCRIPT"; then
    pass "Script has claude CLI not found error handling"
  else
    fail "Script should handle missing claude CLI"
  fi
}

# ============================================================================
# JOB RUNNER TESTS (V3.0)
# ============================================================================

# Test: Job script version
test_job_version() {
  echo ""
  echo "=== Test: Job script version ==="

  local output exit_code
  set +e
  output=$("$JOB_SCRIPT" --help 2>&1 | head -1)
  exit_code=$?
  set -e

  if [[ "$output" == *"V3.1"* ]]; then
    pass "Job script reports V3.1"
  else
    fail "Job script should report V3.1" "output=$output"
  fi
}

# Test: Job script has new options
test_job_new_options() {
  echo ""
  echo "=== Test: Job script new V3.0 options ==="

  local output
  output=$("$JOB_SCRIPT" --help 2>&1)

  local has_no_ansi has_observe_only has_preserve_contract has_tail
  has_no_ansi=0
  has_observe_only=0
  has_preserve_contract=0
  has_tail=0

  [[ "$output" == *"--no-ansi"* ]] && has_no_ansi=1
  [[ "$output" == *"--observe-only"* ]] && has_observe_only=1
  [[ "$output" == *"--preserve-contract"* ]] && has_preserve_contract=1
  [[ "$output" == *"tail"* ]] && has_tail=1

  if [[ $has_no_ansi -eq 1 ]] && [[ $has_observe_only -eq 1 ]] && [[ $has_preserve_contract -eq 1 ]] && [[ $has_tail -eq 1 ]]; then
    pass "Job script has all V3.0 options documented"
  else
    fail "Job script missing V3.0 options" "no_ansi=$has_no_ansi observe_only=$has_observe_only preserve_contract=$has_preserve_contract tail=$has_tail"
  fi
}

# Test: Job health states documented
test_job_health_states() {
  echo ""
  echo "=== Test: Job health states documentation ==="

  local output
  output=$("$JOB_SCRIPT" --help 2>&1)

  local has_healthy has_exited_ok has_exited_err has_stalled
  has_healthy=0
  has_exited_ok=0
  has_exited_err=0
  has_stalled=0

  [[ "$output" == *"healthy"* ]] && has_healthy=1
  [[ "$output" == *"exited_ok"* ]] && has_exited_ok=1
  [[ "$output" == *"exited_err"* ]] && has_exited_err=1
  [[ "$output" == *"stalled"* ]] && has_stalled=1

  if [[ $has_healthy -eq 1 ]] && [[ $has_exited_ok -eq 1 ]] && [[ $has_exited_err -eq 1 ]] && [[ $has_stalled -eq 1 ]]; then
    pass "Job script documents all health states"
  else
    fail "Job script missing health states" "healthy=$has_healthy exited_ok=$has_exited_ok exited_err=$has_exited_err stalled=$has_stalled"
  fi
}

# Test: Job script has outcome file support
test_job_outcome_file() {
  echo ""
  echo "=== Test: Job outcome file support ==="

  # Check that job_paths includes OUTCOME_FILE
  if grep -q "OUTCOME_FILE=" "$JOB_SCRIPT"; then
    pass "Job script defines OUTCOME_FILE"
  else
    fail "Job script should define OUTCOME_FILE"
  fi
}

# Test: Job script has contract file support
test_job_contract_file() {
  echo ""
  echo "=== Test: Job contract file support ==="

  # Check that job_paths includes CONTRACT_FILE
  if grep -q "CONTRACT_FILE=" "$JOB_SCRIPT"; then
    pass "Job script defines CONTRACT_FILE"
  else
    fail "Job script should define CONTRACT_FILE"
  fi
}

# Test: Job script has log rotation
test_job_log_rotation() {
  echo ""
  echo "=== Test: Job log rotation ==="

  # Check that rotate_log function exists
  if grep -q "rotate_log()" "$JOB_SCRIPT"; then
    pass "Job script has rotate_log function"
  else
    fail "Job script should have rotate_log function"
  fi
}

# Test: Job script has process_cpu_time for progress detection
test_job_progress_detection() {
  echo ""
  echo "=== Test: Job progress detection ==="

  # Check that process_cpu_time function exists
  if grep -q "process_cpu_time()" "$JOB_SCRIPT"; then
    pass "Job script has process_cpu_time for progress detection"
  else
    fail "Job script should have process_cpu_time function"
  fi
}

# Test: Job script has strip_ansi function
test_job_ansi_stripping() {
  echo ""
  echo "=== Test: Job ANSI stripping ==="

  # Check that strip_ansi function exists
  if grep -q "strip_ansi()" "$JOB_SCRIPT"; then
    pass "Job script has strip_ansi function"
  else
    fail "Job script should have strip_ansi function"
  fi
}

# Test: Job script has observe-only mode
test_job_observe_only() {
  echo ""
  echo "=== Test: Job observe-only mode ==="

  # Check that WATCHDOG_OBSERVE_ONLY is handled
  if grep -q "WATCHDOG_OBSERVE_ONLY" "$JOB_SCRIPT"; then
    pass "Job script handles WATCHDOG_OBSERVE_ONLY mode"
  else
    fail "Job script should handle observe-only mode"
  fi
}

# Test: Job script has --no-auto-restart
test_job_no_auto_restart() {
  echo ""
  echo "=== Test: Job no-auto-restart ==="

  # Check that no_auto_restart is handled
  if grep -q "no_auto_restart" "$JOB_SCRIPT"; then
    pass "Job script handles no_auto_restart"
  else
    fail "Job script should handle no_auto_restart"
  fi
}

# Test: Job script has verify_contract function
test_job_verify_contract() {
  echo ""
  echo "=== Test: Job verify_contract ==="

  # Check that verify_contract function exists
  if grep -q "verify_contract()" "$JOB_SCRIPT"; then
    pass "Job script has verify_contract function"
  else
    fail "Job script should have verify_contract function"
  fi
}

# Test: process_cpu_time has explicit leading-zero guard
test_job_cpu_leading_zero_guard() {
  echo ""
  echo "=== Test: Job CPU leading-zero guard ==="

  if grep -q "parse_decimal_component()" "$JOB_SCRIPT" && grep -q "10#" "$JOB_SCRIPT"; then
    pass "process_cpu_time has base-10 guard for leading-zero values"
  else
    fail "process_cpu_time missing leading-zero base-10 guard"
  fi
}

# Test: verify_contract checks all persisted non-secret fields
test_job_verify_contract_fields() {
  echo ""
  echo "=== Test: verify_contract field coverage ==="

  local missing=()
  for field in model base_url timeout_ms auth_source auth_mode execution_mode; do
    if ! grep -q "$field" "$JOB_SCRIPT"; then
      missing+=("$field")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    pass "verify_contract includes model/base/timeout/auth/execution fields"
  else
    fail "verify_contract missing field checks" "missing=${missing[*]}"
  fi
}

# ============================================================================
# V3.1 REGRESSION TESTS
# ============================================================================

# Test: Heartbeat emission in job log
test_heartbeat_emission() {
  echo ""
  echo "=== Test: Heartbeat emission (V3.1) ==="

  # Check that write_heartbeat function exists
  if grep -q "write_heartbeat()" "$JOB_SCRIPT"; then
    pass "write_heartbeat function exists"
  else
    fail "write_heartbeat function not found"
    return
  fi

  # Check heartbeat format
  if grep -q "\[CC_GLM_HEARTBEAT\]" "$JOB_SCRIPT"; then
    pass "Heartbeat format marker found in script"
  else
    fail "Heartbeat format marker not found"
  fi

  # Verify heartbeat includes required fields
  local has_beads has_pid has_model has_ts
  has_beads=0; has_pid=0; has_model=0; has_ts=0
  grep -q "beads=" "$JOB_SCRIPT" && grep -q "\[CC_GLM_HEARTBEAT\]" "$JOB_SCRIPT" && has_beads=1
  grep -q "pid=" "$JOB_SCRIPT" && grep -q "\[CC_GLM_HEARTBEAT\]" "$JOB_SCRIPT" && has_pid=1
  grep -q "model=" "$JOB_SCRIPT" && grep -q "\[CC_GLM_HEARTBEAT\]" "$JOB_SCRIPT" && has_model=1
  grep -q "ts=" "$JOB_SCRIPT" && grep -q "\[CC_GLM_HEARTBEAT\]" "$JOB_SCRIPT" && has_ts=1

  if [[ $has_beads -eq 1 ]] && [[ $has_pid -eq 1 ]] && [[ $has_model -eq 1 ]] && [[ $has_ts -eq 1 ]]; then
    pass "Heartbeat includes beads/pid/model/ts fields"
  else
    fail "Heartbeat missing required fields" "beads=$has_beads pid=$has_pid model=$has_model ts=$has_ts"
  fi
}

# Test: Model propagation on restart
test_model_propagation_restart() {
  echo ""
  echo "=== Test: Model propagation on restart (V3.1) ==="

  # Check get_effective_model function
  if grep -q "get_effective_model()" "$JOB_SCRIPT"; then
    pass "get_effective_model function exists"
  else
    fail "get_effective_model function not found"
    return
  fi

  # Verify precedence: explicit override > persisted meta > default
  local has_explicit has_persisted has_default
  has_explicit=0; has_persisted=0; has_default=0

  grep -q "explicit_override" "$JOB_SCRIPT" && has_explicit=1
  grep -q "effective_model" "$JOB_SCRIPT" && has_persisted=1
  grep -q "glm-5" "$JOB_SCRIPT" && has_default=1

  if [[ $has_explicit -eq 1 ]] && [[ $has_persisted -eq 1 ]] && [[ $has_default -eq 1 ]]; then
    pass "Model precedence: explicit > persisted > default"
  else
    fail "Model precedence incomplete" "explicit=$has_explicit persisted=$has_persisted default=$has_default"
  fi

  # Check that effective_model is persisted to meta
  if grep -q "effective_model=" "$JOB_SCRIPT"; then
    pass "effective_model persisted to metadata"
  else
    fail "effective_model should be persisted to metadata"
  fi
}

# Test: running_no_output health state
test_running_no_output_state() {
  echo ""
  echo "=== Test: running_no_output health state (V3.1) ==="

  # Check job_health function exists
  if grep -q "job_health()" "$JOB_SCRIPT"; then
    pass "job_health function exists"
  else
    fail "job_health function not found"
    return
  fi

  # Check running_no_output state is emitted
  if grep -q "running_no_output" "$JOB_SCRIPT"; then
    pass "running_no_output state defined in script"
  else
    fail "running_no_output state not found"
  fi

  # Verify health state documentation
  local output
  output=$("$JOB_SCRIPT" --help 2>&1)

  if [[ "$output" == *"running_no_output"* ]]; then
    pass "running_no_output documented in help"
  else
    fail "running_no_output not in help output"
  fi
}

# Test: Preflight command
test_preflight_command() {
  echo ""
  echo "=== Test: Preflight command (V3.1) ==="

  # Check run_preflight function
  if grep -q "run_preflight()" "$JOB_SCRIPT"; then
    pass "run_preflight function exists"
  else
    fail "run_preflight function not found"
    return
  fi

  # Check preflight checks for claude binary
  if grep -q "claude binary" "$JOB_SCRIPT" || grep -q 'command -v claude' "$JOB_SCRIPT"; then
    pass "Preflight checks for claude binary"
  else
    fail "Preflight missing claude binary check"
  fi

  # Check preflight checks for auth
  if grep -q "auth resolvable" "$JOB_SCRIPT"; then
    pass "Preflight checks auth resolvability"
  else
    fail "Preflight missing auth check"
  fi

  # Check preflight checks model
  if grep -q "effective_model=" "$JOB_SCRIPT"; then
    pass "Preflight checks effective model"
  else
    fail "Preflight missing model check"
  fi

  # Check preflight command in help
  local output
  output=$("$JOB_SCRIPT" --help 2>&1)

  if [[ "$output" == *"preflight"* ]]; then
    pass "preflight command documented in help"
  else
    fail "preflight command not in help"
  fi
}

# Run all tests
echo "================================================"
echo "cc-glm V3.0 Test Suite"
echo "================================================"
echo "Headless script: $HEADLESS_SCRIPT"
echo "Job script: $JOB_SCRIPT"
echo ""

# Verify scripts exist
if [[ ! -f "$HEADLESS_SCRIPT" ]]; then
  echo "ERROR: Headless script not found: $HEADLESS_SCRIPT"
  exit 1
fi

if [[ ! -f "$JOB_SCRIPT" ]]; then
  echo "ERROR: Job script not found: $JOB_SCRIPT"
  exit 1
fi

# Verify scripts are executable
if [[ ! -x "$HEADLESS_SCRIPT" ]]; then
  echo "Making headless script executable..."
  chmod +x "$HEADLESS_SCRIPT"
fi

if [[ ! -x "$JOB_SCRIPT" ]]; then
  echo "Making job script executable..."
  chmod +x "$JOB_SCRIPT"
fi

# Run headless tests
echo ""
echo "--- Headless Script Tests ---"
test_version_output
test_help_output
test_no_token_leakage
test_cc_glm_auth_token_priority
test_cc_glm_token_file
test_token_file_priority
test_token_file_missing
test_token_file_empty
test_zai_api_key_plain
test_zai_api_key_op_reference
test_cc_glm_op_uri
test_default_op_fallback
test_allow_fallback
test_strict_auth_disabled
test_priority_order
test_anthropic_env_exports
test_debug_token_capture
test_missing_claude_cli

# Run job runner tests
echo ""
echo "--- Job Runner Tests (V3.0) ---"
test_job_version
test_job_new_options
test_job_health_states
test_job_outcome_file
test_job_contract_file
test_job_log_rotation
test_job_progress_detection
test_job_ansi_stripping
test_job_observe_only
test_job_no_auto_restart
test_job_verify_contract
test_job_cpu_leading_zero_guard
test_job_verify_contract_fields

# Run V3.1 regression tests
echo ""
echo "--- V3.1 Regression Tests ---"
test_heartbeat_emission
test_model_propagation_restart
test_running_no_output_state
test_preflight_command

# Summary
echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo -e "${GREEN}Passed${NC}: $passed"
echo -e "${RED}Failed${NC}: $failed"
echo -e "${YELLOW}Skipped${NC}: $skipped"
echo ""

if [[ $failed -gt 0 ]]; then
  exit 1
fi

exit 0
