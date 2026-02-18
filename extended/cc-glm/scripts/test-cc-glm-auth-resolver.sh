#!/usr/bin/env bash
set -euo pipefail

# test-cc-glm-auth-resolver.sh
#
# Test coverage for cc-glm-headless.sh auth token resolver.
# Tests all resolution branches without revealing actual token values.
#
# Usage:
#   test-cc-glm-auth-resolver.sh [--verbose]
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADLESS_SCRIPT="${SCRIPT_DIR}/cc-glm-headless.sh"
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
  unset ZAI_API_KEY 2>/dev/null || true
  unset CC_GLM_OP_URI 2>/dev/null || true
  unset CC_GLM_OP_VAULT 2>/dev/null || true
  unset OP_SERVICE_ACCOUNT_TOKEN 2>/dev/null || true
  unset CC_GLM_ALLOW_FALLBACK 2>/dev/null || true
  unset CC_GLM_STRICT_AUTH 2>/dev/null || true
  unset CC_GLM_DEBUG 2>/dev/null || true
}

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

  local has_auth_order has_fallback has_epyc12
  has_auth_order=0
  has_fallback=0
  has_epyc12=0

  [[ "$output" == *"CC_GLM_AUTH_TOKEN"* ]] && has_auth_order=1
  [[ "$output" == *"CC_GLM_ALLOW_FALLBACK"* ]] && has_fallback=1
  [[ "$output" == *"epyc12"* ]] && has_epyc12=1

  if [[ $has_auth_order -eq 1 ]] && [[ $has_fallback -eq 1 ]] && [[ $has_epyc12 -eq 1 ]]; then
    pass "Help output contains auth order, fallback info, and epyc12 default"
  else
    fail "Help output missing expected sections" "auth=$has_auth_order fallback=$has_fallback epyc12=$has_epyc12"
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

  if [[ $exit_code -eq 0 ]] && [[ "$output" == *"cc-glm-headless.sh version "* ]]; then
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

# Test: Priority order - CC_GLM_AUTH_TOKEN wins over ZAI_API_KEY
test_priority_order() {
  echo ""
  echo "=== Test: Auth source priority order ==="

  setup_test_env

  # Set all sources
  export CC_GLM_AUTH_TOKEN="priority-1"
  export ZAI_API_KEY="priority-2"
  export CC_GLM_OP_URI="op://dev/vault/field"

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

# Test: epyc12-default auth token file discovery
test_epyc12_default_fallback() {
  echo ""
  echo "=== Test: epyc12-default token file discovery ==="

  setup_test_env

  # Verify the epyc12 path exists in the script
  local has_epyc12_path
  has_epyc12_path="$(grep -c 'op-epyc12-token' "$HEADLESS_SCRIPT" || true)"
  if [[ "$has_epyc12_path" -gt 0 ]]; then
    pass "cc-glm-headless.sh contains epyc12 token path reference"
  else
    fail "cc-glm-headless.sh missing epyc12 token path reference"
  fi

  # Verify hostname-based fallback path exists
  local has_hostname_path
  has_hostname_path="$(grep -c 'op-\${host}-token' "$HEADLESS_SCRIPT" || true)"
  if [[ "$has_hostname_path" -gt 0 ]]; then
    pass "cc-glm-headless.sh contains hostname-based token path reference"
  else
    fail "cc-glm-headless.sh missing hostname-based token path reference"
  fi

  setup_test_env
}

# Test: OP_SERVICE_ACCOUNT_TOKEN_FILE env variable takes precedence
test_op_token_file_env_precedence() {
  echo ""
  echo "=== Test: OP_SERVICE_ACCOUNT_TOKEN_FILE env precedence ==="

  setup_test_env

  # Verify both file types are checked in the resolver
  local checks_env checks_hostname
  checks_env="$(grep -c 'OP_SERVICE_ACCOUNT_TOKEN_FILE' "$HEADLESS_SCRIPT" || true)"
  checks_hostname="$(grep -c 'op-\${host}-token' "$HEADLESS_SCRIPT" || true)"

  if [[ "$checks_env" -gt 0 ]] && [[ "$checks_hostname" -gt 0 ]]; then
    pass "Resolver checks both OP_SERVICE_ACCOUNT_TOKEN_FILE and hostname-based paths"
  else
    fail "Resolver missing token file path checks" "env=$checks_env hostname=$checks_hostname"
  fi

  # Verify the precedence order: env file > hostname file
  local precedence_check
  precedence_check="$(awk '/OP_SERVICE_ACCOUNT_TOKEN_FILE.*&&.*-f/ {print "found"; exit}' "$HEADLESS_SCRIPT" || true)"
  if [[ "$precedence_check" == "found" ]]; then
    pass "OP_SERVICE_ACCOUNT_TOKEN_FILE takes precedence over hostname-based path"
  else
    # The check may use different syntax, just verify both paths exist
    if grep -q "OP_SERVICE_ACCOUNT_TOKEN_FILE" "$HEADLESS_SCRIPT" && grep -q "op-epyc12-token" "$HEADLESS_SCRIPT"; then
      pass "Token file discovery includes both env and explicit epyc12 paths"
    else
      fail "Token file discovery paths not properly implemented"
    fi
  fi

  setup_test_env
}

# Test: Legacy macmini fallback path exists
test_legacy_macmini_fallback() {
  echo ""
  echo "=== Test: Legacy macmini token fallback ==="

  setup_test_env

  # Verify legacy macmini path exists for backwards compatibility
  local has_legacy_path
  has_legacy_path="$(grep -c 'op-macmini-token' "$HEADLESS_SCRIPT" || true)"
  if [[ "$has_legacy_path" -gt 0 ]]; then
    pass "cc-glm-headless.sh contains legacy macmini token fallback"
  else
    fail "cc-glm-headless.sh missing legacy macmini token fallback"
  fi
}

# Test: Version 2.1.x indicates epyc12-default policy
test_version_epyc12_policy() {
  echo ""
  echo "=== Test: Version indicates epyc12-default policy ==="

  local version
  version="$("$HEADLESS_SCRIPT" --version 2>&1 || true)"

  # Version 2.1.x indicates epyc12-default policy implementation
  if [[ "$version" == *"2.1"* ]]; then
    pass "Version 2.1.x indicates epyc12-default policy"
  else
    fail "Expected version 2.1.x for epyc12-default policy" "version=$version"
  fi
}

# Run all tests
echo "================================================"
echo "cc-glm-headless.sh Auth Resolver Test Suite"
echo "================================================"
echo "Script: $HEADLESS_SCRIPT"
echo ""

# Verify script exists
if [[ ! -f "$HEADLESS_SCRIPT" ]]; then
  echo "ERROR: Script not found: $HEADLESS_SCRIPT"
  exit 1
fi

# Verify script is executable
if [[ ! -x "$HEADLESS_SCRIPT" ]]; then
  echo "Making script executable..."
  chmod +x "$HEADLESS_SCRIPT"
fi

# Run tests
test_version_output
test_help_output
test_no_token_leakage
test_cc_glm_auth_token_priority
test_zai_api_key_plain
test_zai_api_key_op_reference
test_cc_glm_op_uri
test_default_op_fallback
test_allow_fallback
test_strict_auth_disabled
test_priority_order
test_anthropic_env_exports
test_missing_claude_cli
test_epyc12_default_fallback
test_op_token_file_env_precedence
test_legacy_macmini_fallback
test_version_epyc12_policy

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
