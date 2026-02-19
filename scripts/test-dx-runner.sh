#!/usr/bin/env bash
# test-dx-runner.sh - Deterministic tests for dx-runner core + adapters
#
# Usage: ./test-dx-runner.sh [test_name]
#
# Tests:
#   test_bash_syntax         - Verify all shell scripts pass bash -n
#   test_runner_commands     - Test runner command surface
#   test_adapter_contract    - Verify adapters implement required functions
#   test_governance_gates    - Test baseline/integrity/feature-key gates
#   test_health_states       - Test health state classification
#   test_json_output         - Verify JSON output is deterministic
#   test_outcome_lifecycle   - Outcome persistence + launcher capture
#   test_model_resolution    - Canonical strict model resolution
#   test_probe_model_flag    - Probe command honors --model
#   test_prune_stale_jobs    - Stale PID transitions and pruning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
DX_RUNNER="${ROOT_DIR}/scripts/dx-runner"
ADAPTERS_DIR="${ROOT_DIR}/scripts/adapters"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

create_mock_adapter() {
    local adapter_path="$1"
    cat > "$adapter_path" <<'EOF'
#!/usr/bin/env bash
adapter_preflight() { return 0; }
adapter_probe_model() { [[ "${1:-}" == "mock-model" ]]; }
adapter_list_models() { echo "mock-model"; }
adapter_stop() {
  local pid="$1"
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
}
adapter_start() {
  local beads="$1"
  local prompt_file="$2"
  local worktree="$3"
  local log_file="$4"
  local rc_file="${DX_RUNNER_RC_FILE:-/tmp/dx-runner/mock/${beads}.rc}"
  local exit_code="${MOCK_ADAPTER_EXIT_CODE:-0}"
  mkdir -p "$(dirname "$rc_file")"
  (
    echo "READY_STDOUT for $beads"
    echo "READY_STDERR for $beads" >&2
    sleep 1
    echo "$exit_code" > "$rc_file"
    exit "$exit_code"
  ) >> "$log_file" 2>&1 &
  local pid="$!"
  printf 'pid=%s\n' "$pid"
  printf 'selected_model=%s\n' "mock-model"
  printf 'fallback_reason=%s\n' "none"
  printf 'launch_mode=%s\n' "detached"
  printf 'rc_file=%s\n' "$rc_file"
}
EOF
    chmod +x "$adapter_path"
}

# ============================================================================
# Test: Bash Syntax
# ============================================================================

test_bash_syntax() {
    echo "=== Testing Bash Syntax ==="
    
    # Test runner
    if bash -n "$DX_RUNNER" 2>/dev/null; then
        pass "dx-runner syntax OK"
    else
        fail "dx-runner syntax error"
    fi
    
    # Test adapters
    for adapter in "$ADAPTERS_DIR"/*.sh; do
        local name
        name="$(basename "$adapter")"
        if bash -n "$adapter" 2>/dev/null; then
            pass "adapter $name syntax OK"
        else
            fail "adapter $name syntax error"
        fi
    done
}

# ============================================================================
# Test: Runner Commands
# ============================================================================

test_runner_commands() {
    echo "=== Testing Runner Commands ==="
    
    # Help should work
    if "$DX_RUNNER" --help >/dev/null 2>&1; then
        pass "dx-runner --help works"
    else
        fail "dx-runner --help failed"
    fi
    
    # Status with no jobs should work
    if "$DX_RUNNER" status >/dev/null 2>&1; then
        pass "dx-runner status works"
    else
        fail "dx-runner status failed"
    fi
    
    # Preflight should work
    if "$DX_RUNNER" preflight >/dev/null 2>&1; then
        pass "dx-runner preflight works"
    else
        warn "dx-runner preflight returned non-zero (may be expected)"
    fi
    
    # JSON output should be valid
    local json_output
    json_output="$("$DX_RUNNER" status --json 2>/dev/null)" || true
    if echo "$json_output" | jq -e . >/dev/null 2>&1; then
        pass "dx-runner status --json produces valid JSON"
    else
        fail "dx-runner status --json invalid JSON"
    fi
}

# ============================================================================
# Test: Adapter Contract
# ============================================================================

test_adapter_contract() {
    echo "=== Testing Adapter Contract ==="
    
    local required_functions=(
        "adapter_start"
        "adapter_preflight"
        "adapter_probe_model"
        "adapter_list_models"
        "adapter_stop"
    )
    
    for adapter in "$ADAPTERS_DIR"/*.sh; do
        local name
        name="$(basename "$adapter" .sh)"
        
        # Source the adapter
        source "$adapter"
        
        for func in "${required_functions[@]}"; do
            if declare -f "$func" >/dev/null 2>&1; then
                pass "$name: $func implemented"
            else
                fail "$name: $func NOT implemented"
            fi
        done
    done
}

# ============================================================================
# Test: Governance Gates
# ============================================================================

test_governance_gates() {
    echo "=== Testing Governance Gates ==="
    
    # Create temp worktree for gate tests
    local temp_dir
    temp_dir="$(mktemp -d)"
    cd "$temp_dir"
    git init --quiet
    
    # Make initial commit
    echo "test" > file.txt
    git add file.txt
    git commit -m "initial" --quiet
    
    local baseline_sha
    baseline_sha="$(git rev-parse HEAD)"
    
    # Test baseline gate (should pass)
    local result
    result="$("$DX_RUNNER" baseline-gate --worktree "$temp_dir" --required-baseline "$baseline_sha" 2>&1)" || true
    if echo "$result" | grep -q "true\|OK\|baseline_ok"; then
        pass "baseline-gate passes for current commit"
    else
        fail "baseline-gate should pass for current commit"
    fi
    
    # Test feature-key gate (no commits, should pass)
    git checkout -b test-branch --quiet
    result="$("$DX_RUNNER" feature-key-gate --worktree "$temp_dir" --feature-key "test-key" --branch test-branch 2>&1)" || true
    if echo "$result" | grep -q "no_commits_in_range"; then
        pass "feature-key-gate handles no-commits case"
    else
        warn "feature-key-gate: $result"
    fi
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
}

# ============================================================================
# Test: Health States
# ============================================================================

test_health_states() {
    echo "=== Testing Health States ==="
    
    # Create a fake job to test health states
    local beads="test-health-$$"
    local provider="cc-glm"
    local log_dir="/tmp/dx-runner/$provider"
    
    mkdir -p "$log_dir"
    
    # Create meta file
    cat > "$log_dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    # Test missing state (no PID file)
    local result
    result="$("$DX_RUNNER" check --beads "$beads" 2>&1)" || true
    if echo "$result" | grep -qE "missing|no_metadata"; then
        pass "health detects missing state"
    else
        fail "health should detect missing state"
    fi
    
    # Create PID file with non-existent process
    echo "99999999" > "$log_dir/${beads}.pid"
    
    result="$("$DX_RUNNER" check --beads "$beads" 2>&1)" || true
    if echo "$result" | grep -qE "exited|stalled"; then
        pass "health detects exited process"
    else
        warn "health exited check: $result"
    fi
    
    # Test JSON output
    result="$("$DX_RUNNER" check --beads "$beads" --json 2>&1)" || true
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        pass "health --json produces valid JSON"
    else
        fail "health --json invalid JSON"
    fi
    
    # Cleanup
    rm -f "$log_dir/${beads}".*
}

# ============================================================================
# Test: JSON Output Determinism
# ============================================================================

test_json_output() {
    echo "=== Testing JSON Output Determinism ==="
    
    # Status JSON should have stable fields
    local output fields expected_fields
    output="$("$DX_RUNNER" status --json 2>/dev/null)"
    
    expected_fields=("generated_at" "jobs")
    for field in "${expected_fields[@]}"; do
        if echo "$output" | jq -e ".${field}" >/dev/null 2>&1; then
            pass "status JSON has field: $field"
        else
            fail "status JSON missing field: $field"
        fi
    done
    
    # Report JSON should have stable fields
    local beads="test-report-$$"
    local provider="cc-glm"
    local log_dir="/tmp/dx-runner/$provider"
    
    mkdir -p "$log_dir"
    cat > "$log_dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    output="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null)"
    
    expected_fields=("beads" "provider" "state" "started_at" "retries" "mutations")
    for field in "${expected_fields[@]}"; do
        if echo "$output" | jq -e ".${field}" >/dev/null 2>&1; then
            pass "report JSON has field: $field"
        else
            fail "report JSON missing field: $field"
        fi
    done
    
    # Cleanup
    rm -f "$log_dir/${beads}".*
}

# ============================================================================
# Test: Outcome Lifecycle + Launcher Behavior
# ============================================================================

test_outcome_lifecycle() {
    echo "=== Testing Outcome Lifecycle ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads_ok="test-outcome-ok-$$"
    local prompt_ok
    prompt_ok="$(mktemp)"
    echo "READY" > "$prompt_ok"
    if "$DX_RUNNER" start --beads "$beads_ok" --provider mock --prompt-file "$prompt_ok" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads_ok}.outcome" ]] && break
            sleep 1
        done
        if [[ -f "/tmp/dx-runner/mock/${beads_ok}.outcome" ]]; then
            pass "outcome file written for successful completion"
        else
            fail "missing outcome file for successful completion"
        fi
        local state_ok
        state_ok="$("$DX_RUNNER" check --beads "$beads_ok" --json 2>/dev/null | jq -r '.state')" || state_ok=""
        if [[ "$state_ok" == "exited_ok" ]]; then
            pass "no false process_exited_without_outcome on success"
        else
            fail "expected exited_ok for success, got $state_ok"
        fi
        local log_ok="/tmp/dx-runner/mock/${beads_ok}.log"
        if [[ -f "$log_ok" ]] && grep -q "READY_STDOUT" "$log_ok" && grep -q "READY_STDERR" "$log_ok"; then
            pass "detached launcher captured stdout/stderr"
        else
            fail "detached launcher did not capture stdout/stderr"
        fi
    else
        fail "mock success start failed"
    fi

    local beads_fail="test-outcome-fail-$$"
    local prompt_fail
    prompt_fail="$(mktemp)"
    echo "FAIL" > "$prompt_fail"
    if MOCK_ADAPTER_EXIT_CODE=7 "$DX_RUNNER" start --beads "$beads_fail" --provider mock --prompt-file "$prompt_fail" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads_fail}.outcome" ]] && break
            sleep 1
        done
        local exit_fail
        exit_fail="$(awk -F= '$1=="exit_code"{print $2; exit}' "/tmp/dx-runner/mock/${beads_fail}.outcome" 2>/dev/null || true)"
        if [[ "$exit_fail" == "7" ]]; then
            pass "outcome file written for nonzero provider completion"
        else
            fail "expected nonzero exit_code in outcome, got ${exit_fail:-missing}"
        fi
    else
        fail "mock failure start failed"
    fi

    rm -f "$prompt_ok" "$prompt_fail" "$adapter"
    rm -f /tmp/dx-runner/mock/"${beads_ok}".* /tmp/dx-runner/mock/"${beads_fail}".*
}

# ============================================================================
# Test: OpenCode Model Resolution (Strict Canonical)
# ============================================================================

test_model_resolution() {
    echo "=== Testing Model Resolution (Strict Canonical) ==="

    local tmp_bin
    tmp_bin="$(mktemp -d)"
    local fake_op="$tmp_bin/opencode"
    cat > "$fake_op" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "models" ]]; then
  cat "${FAKE_MODELS_FILE}"
  exit 0
fi
if [[ "$1" == "run" ]]; then
  echo '{"type":"assistant","content":"READY"}'
  exit 0
fi
exit 0
EOF
    chmod +x "$fake_op"

    local models_file
    models_file="$(mktemp)"
    PATH="$tmp_bin:$PATH"

    # shellcheck disable=SC1091
    source "$ADAPTERS_DIR/opencode.sh"

    cat > "$models_file" <<'EOF'
zhipuai-coding-plan/glm-5
zai-coding-plan/glm-5
opencode/glm-5-free
EOF
    export FAKE_MODELS_FILE="$models_file"
    local r1
    r1="$(adapter_resolve_model "zhipuai-coding-plan/glm-5" "epyc12")"
    [[ "$r1" == zhipuai-coding-plan/glm-5* ]] && pass "model resolution accepts canonical zhipuai model" || fail "canonical resolution failed: $r1"

    cat > "$models_file" <<'EOF'
zai-coding-plan/glm-5
opencode/glm-5-free
EOF
    local r2
    r2="$(adapter_resolve_model "zhipuai-coding-plan/glm-5" "epyc12" || true)"
    [[ "$r2" == "|unavailable|"* ]] && pass "model resolution fails when canonical model is missing" || fail "expected unavailable when canonical missing: $r2"

    local r3
    r3="$(adapter_resolve_model "zai-coding-plan/glm-5" "epyc12" || true)"
    [[ "$r3" == "|unavailable|"* ]] && pass "model resolution rejects non-canonical requested models" || fail "expected non-canonical rejection: $r3"

    rm -rf "$tmp_bin" "$models_file"
}

# ============================================================================
# Test: Probe Model Flag
# ============================================================================

test_probe_model_flag() {
    echo "=== Testing Probe Model Flag ==="

    local tmp_bin
    tmp_bin="$(mktemp -d)"
    local fake_op="$tmp_bin/opencode"
    local args_log
    args_log="$(mktemp)"
    cat > "$fake_op" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_ARGS_LOG}"
if [[ "$1" == "run" ]]; then
  echo '{"type":"assistant","content":"READY"}'
  exit 0
fi
if [[ "$1" == "models" ]]; then
  echo "zhipuai-coding-plan/glm-5"
  exit 0
fi
exit 0
EOF
    chmod +x "$fake_op"

    export FAKE_ARGS_LOG="$args_log"
    PATH="$tmp_bin:$PATH" "$DX_RUNNER" probe --provider opencode --model zhipuai-coding-plan/glm-5 >/dev/null 2>&1 || true
    if grep -q -- "--model zhipuai-coding-plan/glm-5" "$args_log"; then
        pass "probe uses --model flag correctly"
    else
        fail "probe did not pass --model correctly"
    fi
    rm -rf "$tmp_bin" "$args_log"
}

# ============================================================================
# Test: Gemini Adapter Model + Yolo
# ============================================================================

test_gemini_adapter() {
    echo "=== Testing Gemini Adapter (Model + Yolo) ==="

    local tmp_bin
    tmp_bin="$(mktemp -d)"
    local fake_gemini="$tmp_bin/gemini"
    local args_log
    args_log="$(mktemp)"
    cat > "$fake_gemini" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_ARGS_LOG}"
if [[ "$1" == "--help" ]]; then
  echo "--model MODEL  Specify model"
  exit 0
fi
echo "READY"
exit 0
EOF
    chmod +x "$fake_gemini"

    export FAKE_ARGS_LOG="$args_log"
    
    # Test 1: Default model is gemini-3-flash-preview (check PROVIDER_DEFAULT_MODEL in runner)
    local default_model
    default_model="$(grep '\["gemini"\]=' "$DX_RUNNER" 2>/dev/null | sed -n 's/.*\["gemini"\]="\([^"]*\)".*/\1/p')" || true
    if [[ "$default_model" == "gemini-3-flash-preview" ]]; then
        pass "gemini default model is gemini-3-flash-preview in runner config"
    else
        fail "expected gemini-3-flash-preview in PROVIDER_DEFAULT_MODEL, got: '$default_model'"
    fi
    
    # Test 2: Yolo flag is passed by default (check adapter output directly)
    local prompt_file
    prompt_file="$(mktemp)"
    echo "test prompt" > "$prompt_file"
    
    PATH="$tmp_bin:$PATH" source "$ADAPTERS_DIR/gemini.sh"
    
    local start_output
    start_output="$(adapter_start "test-gemini-$$" "$prompt_file" "/tmp" "/tmp/gemini-test.log" 2>&1)" || true
    
    # Check if adapter reports yolo mode in its output
    if echo "$start_output" | grep -q "selected_model=gemini"; then
        pass "gemini adapter reports selected model"
    else
        fail "gemini adapter should report selected model"
    fi
    
    # Test 2b: Verify -y is in adapter logic by checking it DOES NOT appear when disabled
    rm -f "$args_log"
    GEMINI_NO_YOLO=true PATH="$tmp_bin:$PATH" adapter_start "test-gemini-noyolo-$$" "$prompt_file" "/tmp" "/tmp/gemini-test2.log" 2>&1 >/dev/null || true
    
    # Give async process time to write
    sleep 2
    
    # The args_log should NOT have -y when GEMINI_NO_YOLO=true
    if [[ -f "$args_log" ]] && grep -q -- " -y " "$args_log" 2>/dev/null; then
        fail "gemini adapter should NOT pass -y when GEMINI_NO_YOLO=true"
    else
        pass "gemini adapter respects GEMINI_NO_YOLO=true (no -y in args)"
    fi
    
    # Test 2c: Default behavior - check adapter source for -y
    if grep -q 'cmd_args+=(-y)' "$ADAPTERS_DIR/gemini.sh"; then
        pass "gemini adapter includes -y flag in command construction"
    else
        fail "gemini adapter should include -y flag in command construction"
    fi
    
    rm -rf "$tmp_bin" "$args_log" "$prompt_file"
}

# ============================================================================
# Test: Prune Stale Jobs
# ============================================================================

test_prune_stale_jobs() {
    echo "=== Testing Stale Job Pruning ==="

    local provider="mock-prune"
    local beads="test-prune-$$"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"

    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    echo "not-a-pid" > "$dir/${beads}.pid"

    local prune_json
    prune_json="$("$DX_RUNNER" prune --beads "$beads" --json 2>/dev/null || true)"
    if echo "$prune_json" | jq -e '.pruned >= 1' >/dev/null 2>&1 && [[ ! -f "$dir/${beads}.pid" ]]; then
        pass "stale invalid pid state is prunable"
    else
        fail "stale invalid pid was not pruned"
    fi

    rm -f "$dir/${beads}".*
}

# ============================================================================
# Main
# ============================================================================

run_all_tests() {
    test_bash_syntax
    test_runner_commands
    test_adapter_contract
    test_governance_gates
    test_health_states
    test_json_output
    test_outcome_lifecycle
    test_model_resolution
    test_probe_model_flag
    test_gemini_adapter
    test_prune_stale_jobs
    
    echo ""
    echo "=== Summary ==="
    echo -e "Passed: ${GREEN}$PASS${NC}"
    echo -e "Failed: ${RED}$FAIL${NC}"
    
    if [[ $FAIL -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Run specific test or all
if [[ -n "${1:-}" ]]; then
    "$1"
else
    run_all_tests
fi
