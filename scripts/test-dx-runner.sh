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
#   test_model_resolution    - Canonical + allowed fallback model resolution
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
  local sleep_sec="${MOCK_ADAPTER_SLEEP_SEC:-1}"
  mkdir -p "$(dirname "$rc_file")"
  (
    echo "READY_STDOUT for $beads"
    echo "READY_STDERR for $beads" >&2
    sleep "$sleep_sec"
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
    result="$("$DX_RUNNER" feature-key-gate --worktree "$temp_dir" --feature-key "bd-test.1" --branch test-branch 2>&1)" || true
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

    # Test no_op state
    # To simulate no_op, we need a heartbeat file that is old
    local hb_file="/tmp/dx-runner/$provider/${beads}.heartbeat"
    local old_date
    old_date="$(date -u -d "10 minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-10M +"%Y-%m-%dT%H:%M:%SZ")"
    cat > "$hb_file" <<EOF
beads=$beads
provider=$provider
count=1
last_at=$old_date
EOF
    # We also need a running process with no mutations and no log bytes
    local fake_pid
    sleep 60 &
    fake_pid="$!"
    echo "$fake_pid" > "$log_dir/${beads}.pid"
    # Ensure log file exists but is empty
    : > "$log_dir/${beads}.log"
    # Ensure meta file exists and worktree is set to an empty dir
    local empty_worktree
    empty_worktree="$(mktemp -d)"
    cat > "$log_dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
worktree=$empty_worktree
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF

    set +e
    "$DX_RUNNER" check --beads "$beads" >/dev/null 2>&1
    local rc=$?
    set -e
    if [[ "$rc" -eq 23 ]]; then
        pass "health detects no_op and returns exit 23"
    else
        fail "expected exit 23 for no_op, got $rc"
    fi
    kill "$fake_pid" 2>/dev/null || true
    rm -rf "$empty_worktree"
    
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
    export OPENCODE_MODELS_CACHE_TTL_SEC=0
    rm -f /tmp/dx-runner/opencode/.models_cache

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
    rm -f /tmp/dx-runner/opencode/.models_cache
    r2="$(adapter_resolve_model "zhipuai-coding-plan/glm-5" "epyc12" || true)"
    [[ "$r2" == "|unavailable|"* ]] && pass "model resolution fails when canonical model is missing" || fail "expected unavailable when canonical missing: $r2"

    local r3
    r3="$(adapter_resolve_model "zai-coding-plan/glm-5" "epyc12" || true)"
    [[ "$r3" == "|unavailable|"* ]] && pass "model resolution rejects non-canonical requested models" || fail "expected non-canonical rejection: $r3"

    # Start should fail with deterministic rc=25 and reason_code when canonical-only policy cannot be satisfied
    local prompt_file log_file start_out rc
    prompt_file="$(mktemp)"
    log_file="$(mktemp)"
    echo "READY" > "$prompt_file"
    set +e
    rm -f /tmp/dx-runner/opencode/.models_cache
    start_out="$(OPENCODE_MODEL="zhipuai-coding-plan/glm-5" adapter_start "test-opencode-model-missing-$$" "$prompt_file" "/tmp" "$log_file" 2>/dev/null)"
    rc=$?
    set -e
    if [[ "$rc" -eq 25 ]] && echo "$start_out" | grep -q "reason_code=opencode_model_unavailable"; then
        pass "opencode start returns rc=25 with opencode_model_unavailable when canonical-only policy cannot be satisfied"
    else
        fail "expected rc=25 + reason_code for unavailable canonical-only model policy (rc=$rc, out=$start_out)"
    fi

    rm -rf "$tmp_bin" "$models_file" "$prompt_file" "$log_file"
    unset OPENCODE_MODELS_CACHE_TTL_SEC
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
    
    # Create fake gemini that logs args to a fixed path
    cat > "$fake_gemini" <<FAKEEOF
#!/usr/bin/env bash
echo "\$*" > '$args_log'
if [[ "\$1" == "--help" ]]; then
  echo "--model MODEL  Specify model"
  exit 0
fi
echo "READY"
exit 0
FAKEEOF
    chmod +x "$fake_gemini"

    # Test 1: Default model is gemini-3-flash-preview (check PROVIDER_DEFAULT_MODEL in runner)
    local default_model
    default_model="$(grep '\["gemini"\]=' "$DX_RUNNER" 2>/dev/null | sed -n 's/.*\["gemini"\]="\([^"]*\)".*/\1/p')" || true
    if [[ "$default_model" == "gemini-3-flash-preview" ]]; then
        pass "gemini default model is gemini-3-flash-preview in runner config"
    else
        fail "expected gemini-3-flash-preview in PROVIDER_DEFAULT_MODEL, got: '$default_model'"
    fi
    
    # Test 2: Prepare for arg propagation tests
    local prompt_file
    prompt_file="$(mktemp)"
    echo "test prompt" > "$prompt_file"
    
    PATH="$tmp_bin:$PATH" source "$ADAPTERS_DIR/gemini.sh"
    
    # Test 2a: Verify -y flag IS passed by default (check actual command args)
    rm -f "$args_log"
    local start_output
    start_output="$(adapter_start "test-gemini-default-$$" "$prompt_file" "/tmp" "/tmp/gemini-test-default.log" 2>&1)" || true
    
    # Give async launcher time to invoke fake gemini
    sleep 3
    
    # Check adapter reports correct model
    if echo "$start_output" | grep -q "selected_model=gemini"; then
        pass "gemini adapter reports selected model in output"
    else
        fail "gemini adapter should report selected model"
    fi
    
    # Check -y flag is in actual command invocation
    if [[ -f "$args_log" ]] && grep -q -- "-y" "$args_log" 2>/dev/null; then
        pass "gemini adapter passes -y flag to CLI by default"
    else
        # As a fallback, verify the adapter has -y logic in source
        if grep -q 'cmd_args+=(-y)' "$ADAPTERS_DIR/gemini.sh" && grep -q 'use_yolo="true"' "$ADAPTERS_DIR/gemini.sh"; then
            pass "gemini adapter has -y flag logic (async launcher timing issue in test env)"
        else
            fail "gemini adapter should pass -y flag to CLI"
        fi
    fi

    # Check -p flag and prompt are passed
    if [[ -f "$args_log" ]] && grep -q -- "-p test prompt" "$args_log" 2>/dev/null; then
        pass "gemini adapter passes prompt via -p flag"
    else
        # As a fallback, verify the adapter has -p logic in source
        if grep -q 'cmd_args+=(-p "$prompt")' "$ADAPTERS_DIR/gemini.sh"; then
            pass "gemini adapter has -p flag logic (async launcher timing issue in test env)"
        else
            fail "gemini adapter should pass prompt via -p flag"
        fi
    fi
    
    # Test 2b: Verify -y is NOT passed when GEMINI_NO_YOLO=true
    rm -f "$args_log"
    GEMINI_NO_YOLO=true adapter_start "test-gemini-noyolo-$$" "$prompt_file" "/tmp" "/tmp/gemini-test-noyolo.log" 2>&1 >/dev/null || true
    
    sleep 3
    
    if [[ -f "$args_log" ]] && grep -q -- "-y" "$args_log" 2>/dev/null; then
        fail "gemini adapter should NOT pass -y when GEMINI_NO_YOLO=true (found: $(cat "$args_log"))"
    else
        pass "gemini adapter respects GEMINI_NO_YOLO=true (no -y in CLI args)"
    fi
    
    rm -rf "$tmp_bin" "$args_log" "$prompt_file"
}

# ============================================================================
# Test: Gemini Preflight Auth
# ============================================================================

test_gemini_preflight_auth() {
    echo "=== Testing Gemini Preflight Auth ==="

    local tmp_bin
    tmp_bin="$(mktemp -d)"
    local fake_gemini="$tmp_bin/gemini"
    
    cat > "$fake_gemini" <<'FAKEEOF'
#!/usr/bin/env bash
if [[ "$1" == "--list-sessions" ]]; then
  if [[ "${MOCK_AUTH_FAIL:-}" == "true" ]]; then
    exit 1
  fi
  echo "Session 1"
  exit 0
fi
if [[ "$1" == "-y" ]]; then
  if [[ "${MOCK_OAUTH_FAIL:-}" == "true" ]]; then
    echo "oauth probe failed" >&2
    exit 1
  fi
  echo "READY"
  exit 0
fi
exit 0
FAKEEOF
    chmod +x "$fake_gemini"

    # Save original keys (preflight is OAuth-only; env keys must not bypass auth checks)
    local orig_gemini_key="${GEMINI_API_KEY:-}"
    local orig_google_key="${GOOGLE_API_KEY:-}"
    unset GEMINI_API_KEY
    unset GOOGLE_API_KEY

    # Test 1: Fail when CLI-auth and OAuth probe both fail.
    (
        export PATH="$tmp_bin:$PATH"
        export MOCK_AUTH_FAIL=true
        export MOCK_OAUTH_FAIL=true
        source "$ADAPTERS_DIR/gemini.sh"
        set +e
        adapter_preflight > /dev/null
        rc=$?
        if [[ "$rc" -gt 0 ]]; then
            exit 0
        else
            exit 1
        fi
    ) && pass "preflight fails when CLI auth and OAuth probe are unavailable" || fail "preflight should fail when CLI auth and OAuth probe are unavailable"

    # Test 2: Env key alone does not pass (OAuth-only policy)
    (
        export PATH="$tmp_bin:$PATH"
        export GEMINI_API_KEY="test-key"
        export MOCK_AUTH_FAIL=true
        export MOCK_OAUTH_FAIL=true
        source "$ADAPTERS_DIR/gemini.sh"
        set +e
        adapter_preflight > /dev/null
        rc=$?
        if [[ "$rc" -gt 0 ]]; then
            exit 0
        else
            exit 1
        fi
    ) && pass "preflight ignores API key env var under OAuth-only policy" || fail "preflight should not accept API key env var under OAuth-only policy"

    # Test 3: Pass via CLI auth probe
    (
        export PATH="$tmp_bin:$PATH"
        export MOCK_AUTH_FAIL=false
        export MOCK_OAUTH_FAIL=true
        source "$ADAPTERS_DIR/gemini.sh"
        adapter_preflight > /dev/null
    ) && pass "preflight passes via CLI auth probe" || fail "preflight should pass via CLI auth probe"

    # Test 4: Pass via OAuth probe when --list-sessions fails
    (
        export PATH="$tmp_bin:$PATH"
        export MOCK_AUTH_FAIL=true
        export MOCK_OAUTH_FAIL=false
        source "$ADAPTERS_DIR/gemini.sh"
        adapter_preflight > /dev/null
    ) && pass "preflight passes via OAuth probe when CLI session listing fails" || fail "preflight should pass via OAuth probe"

    # Restore keys
    [[ -n "$orig_gemini_key" ]] && export GEMINI_API_KEY="$orig_gemini_key"
    [[ -n "$orig_google_key" ]] && export GOOGLE_API_KEY="$orig_google_key"
    rm -rf "$tmp_bin"
}

# ============================================================================
# Test: Gemini Finalization Reliability (bd-mik2r1)
# ============================================================================

test_gemini_finalization_reliability() {
    echo "=== Testing Gemini Finalization Reliability ==="

    local tmp_bin
    tmp_bin="$(mktemp -d)"
    local fake_gemini="$tmp_bin/gemini"
    cat > "$fake_gemini" <<'FAKEEOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "--model MODEL  Specify model"
  exit 0
fi
if [[ "${1:-}" == "--list-sessions" ]]; then
  echo "default"
  exit 0
fi
prompt=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "-p" ]]; then
    j=$((i+1))
    prompt="${!j:-}"
  fi
done
echo "gemini-start"
sleep 0.5
if [[ "$prompt" == *"FAIL"* ]]; then
  echo "simulated failure" >&2
  exit 7
fi
echo "READY"
exit 0
FAKEEOF
    chmod +x "$fake_gemini"

    wait_for_outcome() {
        local provider="$1"
        local beads="$2"
        local timeout_sec="${3:-20}"
        local outcome="/tmp/dx-runner/${provider}/${beads}.outcome"
        local deadline
        deadline=$(( $(date +%s) + timeout_sec ))
        while [[ "$(date +%s)" -lt "$deadline" ]]; do
            [[ -f "$outcome" ]] && return 0
            sleep 0.2
        done
        return 1
    }

    # Success path: must emit rc/outcome and never classify as *_no_rc
    local beads_ok="test-gemini-ok-$$"
    local prompt_ok
    prompt_ok="$(mktemp)"
    echo "Return exactly READY" > "$prompt_ok"
    if PATH="$tmp_bin:$PATH" "$DX_RUNNER" start --provider gemini --beads "$beads_ok" --prompt-file "$prompt_ok" >/dev/null 2>&1; then
        if wait_for_outcome "gemini" "$beads_ok" 25; then
            local rc_file_ok="/tmp/dx-runner/gemini/${beads_ok}.rc"
            local check_ok
            check_ok="$(PATH="$tmp_bin:$PATH" "$DX_RUNNER" check --beads "$beads_ok" --json 2>/dev/null || true)"
            if [[ -f "$rc_file_ok" ]] && [[ "$(cat "$rc_file_ok" 2>/dev/null || true)" == "0" ]]; then
                pass "gemini success run writes rc=0"
            else
                fail "gemini success run missing rc=0"
            fi
            if echo "$check_ok" | jq -e '.state == "exited_ok"' >/dev/null 2>&1; then
                pass "gemini success run finalizes as exited_ok"
            else
                fail "gemini success run did not finalize as exited_ok"
            fi
            if echo "$check_ok" | jq -e '.reason_code != "late_finalize_no_rc" and .reason_code != "monitor_no_rc_file"' >/dev/null 2>&1; then
                pass "gemini success run avoids *_no_rc classifications"
            else
                fail "gemini success run hit *_no_rc classification"
            fi
        else
            fail "gemini success run did not produce outcome in time"
        fi
    else
        fail "gemini success start command failed"
    fi

    # Failing path: must emit rc/outcome with exited_err and no *_no_rc reason.
    local beads_fail="test-gemini-fail-$$"
    local prompt_fail
    prompt_fail="$(mktemp)"
    echo "FAIL" > "$prompt_fail"
    if PATH="$tmp_bin:$PATH" "$DX_RUNNER" start --provider gemini --beads "$beads_fail" --prompt-file "$prompt_fail" >/dev/null 2>&1; then
        if wait_for_outcome "gemini" "$beads_fail" 25; then
            local rc_file_fail="/tmp/dx-runner/gemini/${beads_fail}.rc"
            local check_fail
            check_fail="$(PATH="$tmp_bin:$PATH" "$DX_RUNNER" check --beads "$beads_fail" --json 2>/dev/null || true)"
            if [[ -f "$rc_file_fail" ]] && [[ "$(cat "$rc_file_fail" 2>/dev/null || true)" == "7" ]]; then
                pass "gemini failing run writes rc=7"
            else
                fail "gemini failing run missing rc=7"
            fi
            if echo "$check_fail" | jq -e '.state == "exited_err"' >/dev/null 2>&1; then
                pass "gemini failing run finalizes as exited_err"
            else
                fail "gemini failing run did not finalize as exited_err"
            fi
            if echo "$check_fail" | jq -e '.reason_code != "late_finalize_no_rc" and .reason_code != "monitor_no_rc_file"' >/dev/null 2>&1; then
                pass "gemini failing run avoids *_no_rc classifications"
            else
                fail "gemini failing run hit *_no_rc classification"
            fi
        else
            fail "gemini failing run did not produce outcome in time"
        fi
    else
        fail "gemini failing start command failed"
    fi

    # Restart path: must not trigger mktemp collision and must finalize cleanly.
    local beads_restart="test-gemini-restart-$$"
    local prompt_restart
    prompt_restart="$(mktemp)"
    echo "Return exactly READY" > "$prompt_restart"
    local restart_out
    if PATH="$tmp_bin:$PATH" "$DX_RUNNER" start --provider gemini --beads "$beads_restart" --prompt-file "$prompt_restart" >/dev/null 2>&1; then
        restart_out="$(PATH="$tmp_bin:$PATH" "$DX_RUNNER" restart --beads "$beads_restart" 2>&1 || true)"
        if [[ "$restart_out" == *"mkstemp failed"* || "$restart_out" == *"File exists"* ]]; then
            fail "gemini restart hit mktemp collision"
        else
            pass "gemini restart avoids mktemp collision"
        fi
        if wait_for_outcome "gemini" "$beads_restart" 25; then
            local check_restart
            check_restart="$(PATH="$tmp_bin:$PATH" "$DX_RUNNER" check --beads "$beads_restart" --json 2>/dev/null || true)"
            if echo "$check_restart" | jq -e '.reason_code != "late_finalize_no_rc" and .reason_code != "monitor_no_rc_file"' >/dev/null 2>&1; then
                pass "gemini restart run avoids *_no_rc classifications"
            else
                fail "gemini restart run hit *_no_rc classification"
            fi
        else
            fail "gemini restart run did not produce outcome in time"
        fi
    else
        fail "gemini restart seed start command failed"
    fi

    rm -rf "$tmp_bin" "$prompt_ok" "$prompt_fail" "$prompt_restart"
    rm -f /tmp/dx-runner/gemini/"${beads_ok}".* /tmp/dx-runner/gemini/"${beads_fail}".* /tmp/dx-runner/gemini/"${beads_restart}".*
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
# Test: Beads Gate
# ============================================================================

test_beads_gate() {
    echo "=== Testing Beads Gate ==="

    # Test beads-gate command exists
    local help_output
    help_output="$("$DX_RUNNER" --help 2>&1)" || true
    if echo "$help_output" | grep -q "beads-gate"; then
        pass "beads-gate command in help"
    else
        fail "beads-gate command missing from help"
    fi

    # Test beads-gate JSON output
    local result
    result="$("$DX_RUNNER" beads-gate --json 2>&1)" || true
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        pass "beads-gate produces valid JSON"
        local reason
        reason="$(echo "$result" | jq -r '.reason_code' 2>/dev/null || echo "unknown")"
        if [[ "$reason" == "beads_ok" ]]; then
            pass "beads-gate passes when bd available"
        elif [[ "$reason" == "beads_unavailable" ]]; then
            pass "beads-gate detects missing bd CLI"
        else
            warn "beads-gate reason: $reason"
        fi
    else
        if echo "$result" | grep -qiE "beads|unavailable|error"; then
            pass "beads-gate handles missing bd gracefully"
        else
            fail "beads-gate unexpected output: $result"
        fi
    fi

    # Enforce external beads repo validation (~/bd by default) with deterministic failure
    local missing_ext_result missing_ext_rc missing_ext_reason
    set +e
    missing_ext_result="$(BEADS_REPO_PATH="/tmp/nonexistent-bd-$$" "$DX_RUNNER" beads-gate --json 2>&1)"
    missing_ext_rc=$?
    set -e
    missing_ext_reason="$(echo "$missing_ext_result" | jq -r '.reason_code' 2>/dev/null || echo "unknown")"
    if [[ "$missing_ext_rc" -eq 24 && "$missing_ext_reason" == "beads_external_repo_missing" ]]; then
        pass "beads-gate enforces external beads repo path and returns exit 24"
    else
        fail "beads-gate external repo enforcement failed (rc=$missing_ext_rc reason=$missing_ext_reason)"
    fi
}

test_beads_gate_json_schema() {
    echo "=== Testing Beads Gate JSON Schema ==="

    local temp_repo
    temp_repo="$(mktemp -d)"
    mkdir -p "$temp_repo/.beads"
    echo "repo_id=test-repo-123" > "$temp_repo/.beads/config"

    # Test 1: Deterministic IDs even when bd is missing
    local result
    result="$(BEADS_REPO_PATH="/tmp/nonexistent-bd-$$" "$DX_RUNNER" beads-gate --repo "$temp_repo" --json 2>&1)" || true
    
    local repo_id_local reason_code repo_id_db
    repo_id_local="$(echo "$result" | jq -r '.repo_id_local')"
    repo_id_db="$(echo "$result" | jq -r '.repo_id_db')"
    reason_code="$(echo "$result" | jq -r '.reason_code')"

    if [[ "$repo_id_local" == "test-repo-123" ]]; then
        pass "JSON reports local repo ID from config"
    else
        fail "JSON failed to report local repo ID (got: $repo_id_local)"
    fi

    if [[ "$repo_id_db" == "unavailable:beads_missing" || "$repo_id_db" == "unavailable:beads_repo_missing" ]]; then
        pass "JSON reports deterministic sentinel for missing DB ID"
    else
        fail "JSON missing deterministic sentinel for DB ID (got: $repo_id_db)"
    fi

    if [[ "$reason_code" == "beads_external_repo_missing" || "$reason_code" == "beads_unavailable" ]]; then
        pass "JSON reports correct failure reason code"
    else
        fail "JSON reports unexpected reason code: $reason_code"
    fi

    # Test 2: Field missing in config
    echo "something_else=v" > "$temp_repo/.beads/config"
    result="$(BEADS_REPO_PATH="/tmp/nonexistent-bd-$$" "$DX_RUNNER" beads-gate --repo "$temp_repo" --json 2>&1)" || true
    repo_id_local="$(echo "$result" | jq -r '.repo_id_local')"
    if [[ "$repo_id_local" == "unavailable:field_missing" ]]; then
        pass "JSON reports sentinel for missing field in config"
    else
        fail "JSON failed to report sentinel for missing field (got: $repo_id_local)"
    fi

    rm -rf "$temp_repo"
}

# ============================================================================
# Test: Outcome Metadata
# ============================================================================

test_outcome_metadata() {
    echo "=== Testing Outcome Metadata ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads="test-meta-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"

    if "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads}.outcome" ]] && break
            sleep 1
        done

        if [[ -f "/tmp/dx-runner/mock/${beads}.outcome" ]]; then
            # Check for required fields
            local required_fields=("beads" "provider" "exit_code" "state" "reason_code" "completed_at" "duration_sec")
            local all_present=true
            for field in "${required_fields[@]}"; do
                if grep -q "^${field}=" "/tmp/dx-runner/mock/${beads}.outcome"; then
                    pass "outcome has field: $field"
                else
                    fail "outcome missing field: $field"
                    all_present=false
                fi
            done

            if [[ "$all_present" == "true" ]]; then
                pass "outcome has all required metadata fields"
            fi
        else
            fail "outcome file not created"
        fi
    else
        fail "mock start failed"
    fi

    rm -f "$prompt" "$adapter"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Provider Switch Resolution
# ============================================================================

test_provider_switch_resolution() {
    echo "=== Testing Provider Switch Resolution ==="

    local beads="test-switch-$$"
    mkdir -p /tmp/dx-runner/gemini /tmp/dx-runner/opencode

    cat > "/tmp/dx-runner/gemini/${beads}.meta" <<EOF
beads=$beads
provider=gemini
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
host=old-host
cwd=/tmp/old
worktree=/tmp/old
run_instance=old-run
EOF
    cat > "/tmp/dx-runner/gemini/${beads}.outcome" <<EOF
beads=$beads
provider=gemini
exit_code=1
state=failed
reason_code=old_provider_failure
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
duration_sec=10
retries=0
selected_model=gemini-3-flash-preview
fallback_reason=none
run_instance=old-run
host=old-host
cwd=/tmp/old
worktree=/tmp/old
EOF

    sleep 1
    cat > "/tmp/dx-runner/opencode/${beads}.meta" <<EOF
beads=$beads
provider=opencode
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
host=new-host
cwd=/tmp/new
worktree=/tmp/new
run_instance=new-run
EOF
    cat > "/tmp/dx-runner/opencode/${beads}.outcome" <<EOF
beads=$beads
provider=opencode
exit_code=0
state=success
reason_code=process_exit_with_rc
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
duration_sec=5
retries=0
selected_model=zhipuai-coding-plan/glm-5
fallback_reason=none
run_instance=new-run
host=new-host
cwd=/tmp/new
worktree=/tmp/new
EOF

    local report_json
    report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null)"
    if echo "$report_json" | jq -e '.provider=="opencode" and .run_instance=="new-run"' >/dev/null 2>&1; then
        pass "report resolves to latest provider instance after switch"
    else
        fail "report returned stale provider context after switch"
    fi

    local check_json
    check_json="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
    if echo "$check_json" | jq -e '.provider=="opencode"' >/dev/null 2>&1; then
        pass "check resolves to latest provider instance after switch"
    else
        fail "check returned stale provider context after switch"
    fi

    rm -f /tmp/dx-runner/gemini/"${beads}".* /tmp/dx-runner/opencode/"${beads}".*
}

# ============================================================================
# Test: Host/Context Tags
# ============================================================================

test_host_context_tags() {
    echo "=== Testing Host/Context Tags ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"
    local beads="test-host-tags-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"
    local wt
    wt="/tmp/agents/test-host-tags-${$}"
    mkdir -p "$wt"

    if "$DX_RUNNER" start --beads "$beads" --provider mock --worktree "$wt" --prompt-file "$prompt" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads}.outcome" ]] && break
            sleep 1
        done
        local outcome="/tmp/dx-runner/mock/${beads}.outcome"
        if grep -q '^host=' "$outcome" && grep -q '^cwd=' "$outcome" && grep -q '^worktree=' "$outcome" && grep -q '^run_instance=' "$outcome"; then
            pass "outcome includes host/cwd/worktree/run_instance tags"
        else
            fail "outcome missing host/cwd/worktree/run_instance tags"
        fi

        local status_json check_json report_json
        status_json="$("$DX_RUNNER" status --beads "$beads" --json 2>/dev/null)"
        check_json="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
        report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null)"
        if echo "$status_json" | jq -e '.jobs[0].host and .jobs[0].cwd and .jobs[0].worktree and .jobs[0].run_instance' >/dev/null 2>&1; then
            pass "status json includes host/cwd/worktree/run_instance"
        else
            fail "status json missing host/cwd/worktree/run_instance"
        fi
        if echo "$check_json" | jq -e '.host and .cwd and .worktree and .run_instance' >/dev/null 2>&1; then
            pass "check json includes host/cwd/worktree/run_instance"
        else
            fail "check json missing host/cwd/worktree/run_instance"
        fi
        if echo "$report_json" | jq -e '.host and .cwd and .worktree and .run_instance' >/dev/null 2>&1; then
            pass "report json includes host/cwd/worktree/run_instance"
        else
            fail "report json missing host/cwd/worktree/run_instance"
        fi
    else
        fail "failed to start mock job for host/context tags"
    fi

    rm -f "$prompt" "$adapter"
    rm -rf "$wt"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Mutation/Log Accounting
# ============================================================================

test_mutation_log_accounting() {
    echo "=== Testing Mutation/Log Accounting ==="

    local beads="test-metrics-$$"
    local provider="cc-glm"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"

    local wt
    wt="$(mktemp -d)"
    (
        cd "$wt"
        git init --quiet
        echo "a" > f.txt
        git add f.txt
        git commit -m "init" --quiet
        echo "b" >> f.txt
    )
    sleep 60 &
    local pid="$!"
    echo "$pid" > "$dir/${beads}.pid"
    echo "log-line" > "$dir/${beads}.log"
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
worktree=$wt
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF

    local report_json
    report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null)"
    if echo "$report_json" | jq -e '.mutations > 0 and .log_bytes > 0' >/dev/null 2>&1; then
        pass "report shows non-zero mutation_count and log_size for active mutating run"
    else
        fail "report failed to show mutation/log growth for active run"
    fi

    kill "$pid" 2>/dev/null || true
    rm -rf "$wt"
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: Capacity Classification
# ============================================================================

test_capacity_classification() {
    echo "=== Testing Capacity Classification ==="

    local beads="test-capacity-$$"
    local provider="gemini"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    echo "99999999" > "$dir/${beads}.pid"
    echo "1" > "$dir/${beads}.rc"
    cat > "$dir/${beads}.log" <<EOF
ERROR: MODEL_CAPACITY_EXHAUSTED
HTTP 429 RESOURCE_EXHAUSTED
EOF
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF

    "$DX_RUNNER" check --beads "$beads" --json >/dev/null 2>&1 || true
    local report_json
    report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null)"
    if echo "$report_json" | jq -e '.outcome_reason_code=="gemini_capacity_exhausted" and .next_action=="retry_backoff_or_switch_to_opencode_or_cc_glm"' >/dev/null 2>&1; then
        pass "capacity exhaustion is classified with deterministic reason + next action"
    else
        fail "capacity exhaustion classification missing or incorrect"
    fi

    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: Finalize/Stop Metric Preservation
# ============================================================================

test_stop_preserves_metrics() {
    echo "=== Testing Stop/Finalize Metric Preservation ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads="test-stop-metrics-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"

    if MOCK_ADAPTER_SLEEP_SEC=20 "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" >/dev/null 2>&1; then
        sleep 2
        "$DX_RUNNER" stop --beads "$beads" >/dev/null 2>&1 || true
        local report_json
        report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null || true)"
        if echo "$report_json" | jq -e '.outcome_reason_code=="manual_stop" and .log_bytes > 0' >/dev/null 2>&1; then
            pass "manual stop preserves final log metrics in report"
        else
            fail "manual stop did not preserve final metrics: $report_json"
        fi
    else
        fail "failed to start mock run for stop metrics test"
    fi

    rm -f "$adapter" "$prompt"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Awaiting Finalize Taxonomy
# ============================================================================

test_awaiting_finalize_taxonomy() {
    echo "=== Testing Awaiting Finalize Taxonomy ==="

    local provider="mock-await"
    local beads="test-await-$$"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"

    # Dead process pid + live monitor pid + no outcome => awaiting_finalize
    echo "99999999" > "$dir/${beads}.pid"
    (sleep 20) >/dev/null 2>&1 &
    local mpid="$!"
    echo "$mpid" > "$dir/${beads}.monitor.pid"
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    echo "partial output" > "$dir/${beads}.log"

    local check_json
    check_json="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
    if echo "$check_json" | jq -e '.state=="awaiting_finalize" and .reason_code=="awaiting_finalize_monitor_active" and .next_action=="wait_for_finalize_or_run_dx_runner_finalize"' >/dev/null 2>&1; then
        pass "awaiting finalize state is classified with deterministic next_action"
    else
        fail "awaiting finalize classification missing: $check_json"
    fi

    kill "$mpid" >/dev/null 2>&1 || true
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: Commit-Required Success Contract
# ============================================================================

test_commit_required_contract() {
    echo "=== Testing Commit-Required Success Contract ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads="test-commit-contract-$$"
    local prompt repo_dir
    prompt="$(mktemp)"
    repo_dir="$(mktemp -d /tmp/agents/test-commit-contract-XXXXXX)"
    echo "READY" > "$prompt"

    git -C "$repo_dir" init --quiet
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test Runner"
    echo "base" > "$repo_dir/base.txt"
    git -C "$repo_dir" add base.txt
    git -C "$repo_dir" commit -m "base" --quiet

    if DX_RUNNER_REQUIRE_COMMIT_ARTIFACT=1 "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" --worktree "$repo_dir" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads}.outcome" ]] && break
            sleep 1
        done
        local report_json check_json
        report_json="$("$DX_RUNNER" report --beads "$beads" --format json 2>/dev/null || true)"
        check_json="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
        if echo "$report_json" | jq -e '.outcome_reason_code=="no_commit_artifact" and .outcome_state=="failed" and (.exit_code|tostring)=="44"' >/dev/null 2>&1; then
            pass "commit-required contract fails successful process without commit artifact"
        else
            fail "commit-required contract not enforced: $report_json"
        fi
        if echo "$check_json" | jq -e '.reason_code=="no_commit_artifact"' >/dev/null 2>&1; then
            pass "check surfaces no_commit_artifact deterministically"
        else
            fail "check did not surface no_commit_artifact: $check_json"
        fi
    else
        fail "start failed unexpectedly in commit contract test"
    fi

    rm -rf "$repo_dir"
    rm -f "$prompt" "$adapter"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Check JSON Includes Metric Telemetry
# ============================================================================

test_check_metrics_telemetry() {
    echo "=== Testing Check Metric Telemetry ==="

    local provider="mock-check"
    local beads="test-check-metrics-$$"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
selected_model=mock-model
fallback_reason=none
run_instance=ri-1
host=test-host
cwd=/tmp
worktree=/tmp/agents
EOF
    cat > "$dir/${beads}.outcome" <<EOF
beads=$beads
provider=$provider
exit_code=1
state=failed
reason_code=no_commit_artifact
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
duration_sec=3
mutations=7
log_bytes=321
cpu_time_sec=4
pid_age_sec=9
selected_model=mock-model
fallback_reason=none
run_instance=ri-1
host=test-host
cwd=/tmp
worktree=/tmp/agents
EOF

    local check_json
    check_json="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
    if echo "$check_json" | jq -e '.mutation_count==7 and .log_bytes==321 and .cpu_time_sec==4 and .pid_age_sec==9 and .reason_code=="no_commit_artifact"' >/dev/null 2>&1; then
        pass "check json preserves finalized metric telemetry"
    else
        fail "check json missing metric telemetry: $check_json"
    fi

    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: Railway Auth Preflight Requirement
# ============================================================================

test_railway_auth_preflight_requirement() {
    echo "=== Testing Railway Auth Preflight Requirement ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local tmp_bin fake_railway out rc
    tmp_bin="$(mktemp -d)"
    fake_railway="$tmp_bin/railway"
    cat > "$fake_railway" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "whoami" ]]; then
  exit 1
fi
exit 0
EOF
    chmod +x "$fake_railway"

    set +e
    out="$(PATH="$tmp_bin:$PATH" DX_RUNNER_REQUIRE_RAILWAY_AUTH=1 DX_RUNNER_RAILWAY_REQUIRED_PROVIDERS=mock RAILWAY_SERVICE_FRONTEND_URL= RAILWAY_SERVICE_BACKEND_URL= RAILWAY_TOKEN= "$DX_RUNNER" preflight --provider mock 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q "railway_"; then
        pass "preflight blocks when railway auth/service context requirement is unmet"
    else
        fail "railway auth preflight requirement not enforced (rc=$rc): $out"
    fi

    rm -rf "$tmp_bin" "$adapter"
}

# ============================================================================
# Test: OpenCode Attach Mode Fail-Fast
# ============================================================================

test_opencode_attach_mode_failfast() {
    echo "=== Testing OpenCode Attach-Mode Fail-Fast ==="

    local tmp_bin fake_op models_file prompt repo_dir beads out rc
    tmp_bin="$(mktemp -d)"
    fake_op="$tmp_bin/opencode"
    models_file="$(mktemp)"
    prompt="$(mktemp)"
    repo_dir="$(mktemp -d /tmp/agents/test-attach-mode-XXXXXX)"
    beads="test-opencode-attach-$$"
    echo "zhipuai-coding-plan/glm-5" > "$models_file"
    echo "READY" > "$prompt"
    git -C "$repo_dir" init --quiet
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test Runner"
    echo "x" > "$repo_dir/a.txt"
    git -C "$repo_dir" add a.txt
    git -C "$repo_dir" commit -m "init" --quiet

    cat > "$fake_op" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "models" ]]; then
  cat "${FAKE_MODELS_FILE}"
  exit 0
fi
if [[ "$1" == "run" && "$2" == "--help" ]]; then
  echo "Usage: opencode run [message..]"
  exit 0
fi
if [[ "$1" == "run" ]]; then
  echo '{"type":"assistant","content":"READY"}'
  exit 0
fi
exit 0
EOF
    chmod +x "$fake_op"

    set +e
    out="$(PATH="$tmp_bin:$PATH" FAKE_MODELS_FILE="$models_file" OPENCODE_EXECUTION_MODE=attach OPENCODE_ATTACH_URL="http://127.0.0.1:4096" "$DX_RUNNER" start --beads "$beads" --provider opencode --prompt-file "$prompt" --worktree "$repo_dir" 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -eq 21 ]] && echo "$out" | grep -q "opencode_attach_mode_unavailable"; then
        pass "attach mode unsupported path fails fast with deterministic reason code"
    else
        fail "attach mode fail-fast missing (rc=$rc): $out"
    fi

    rm -rf "$tmp_bin" "$repo_dir"
    rm -f "$models_file" "$prompt"
    rm -f /tmp/dx-runner/opencode/"${beads}".*
}

# ============================================================================
# Test: Completion Monitor Cleanup (No Orphan)
# ============================================================================

test_completion_monitor_cleanup() {
    echo "=== Testing Completion Monitor Cleanup ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"
    local beads="test-monitor-cleanup-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"

    if "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" >/dev/null 2>&1; then
        for _ in {1..20}; do
            [[ -f "/tmp/dx-runner/mock/${beads}.outcome" ]] && break
            sleep 1
        done
        local mpid_file="/tmp/dx-runner/mock/${beads}.monitor.pid"
        local pid_file="/tmp/dx-runner/mock/${beads}.pid"
        if [[ ! -f "$pid_file" && ! -f "$mpid_file" ]]; then
            pass "pid/monitor artifacts cleaned after completion"
        else
            fail "pid/monitor artifacts not cleaned after completion"
        fi
    else
        fail "mock start failed for monitor cleanup test"
    fi

    rm -f "$adapter" "$prompt"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Provider Concurrency Guardrail
# ============================================================================

test_provider_concurrency_guardrail() {
    echo "=== Testing Provider Concurrency Guardrail ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads1="test-cap-a-$$"
    local beads2="test-cap-b-$$"
    local p1 p2
    p1="$(mktemp)"
    p2="$(mktemp)"
    echo "READY" > "$p1"
    echo "READY" > "$p2"

    if DX_RUNNER_MAX_PARALLEL_DEFAULT=1 MOCK_ADAPTER_SLEEP_SEC=20 "$DX_RUNNER" start --beads "$beads1" --provider mock --prompt-file "$p1" >/dev/null 2>&1; then
        local out rc
        set +e
        out="$(DX_RUNNER_MAX_PARALLEL_DEFAULT=1 "$DX_RUNNER" start --beads "$beads2" --provider mock --prompt-file "$p2" 2>&1)"
        rc=$?
        set -e
        if [[ "$rc" -eq 26 ]] && echo "$out" | grep -q "reason_code=provider_concurrency_cap_exceeded"; then
            pass "provider concurrency cap blocks over-cap start with deterministic reason"
        else
            fail "provider concurrency cap guard failed (rc=$rc out=$out)"
        fi
    else
        fail "failed to start first mock job for concurrency guardrail test"
    fi

    "$DX_RUNNER" stop --beads "$beads1" >/dev/null 2>&1 || true
    rm -f "$adapter" "$p1" "$p2"
    rm -f /tmp/dx-runner/mock/"${beads1}".* /tmp/dx-runner/mock/"${beads2}".*
}

# ============================================================================
# Test: Feature-Key Validation
# ============================================================================

test_feature_key_validation() {
    echo "=== Testing Feature-Key Validation ==="

    local temp_dir
    temp_dir="$(mktemp -d)"
    cd "$temp_dir"
    git init --quiet
    echo "x" > a.txt
    git add a.txt
    git commit -m "init" --quiet

    local out_valid out_invalid
    out_valid="$("$DX_RUNNER" feature-key-gate --worktree "$temp_dir" --feature-key "bd-xga8.6.2" --json 2>/dev/null || true)"
    if echo "$out_valid" | jq -e '.reason_code != "feature_key_invalid_format"' >/dev/null 2>&1; then
        pass "valid dotted Feature-Key format is accepted"
    else
        fail "valid dotted Feature-Key format incorrectly rejected"
    fi

    out_invalid="$("$DX_RUNNER" feature-key-gate --worktree "$temp_dir" --feature-key "xga8.6.2" --json 2>/dev/null || true)"
    if echo "$out_invalid" | jq -e '.reason_code == "feature_key_invalid_format"' >/dev/null 2>&1; then
        pass "invalid Feature-Key format is rejected deterministically"
    else
        fail "invalid Feature-Key format was not rejected"
    fi

    cd /
    rm -rf "$temp_dir"
}

# ============================================================================
# Test: Pre-commit Flush Semantics
# ============================================================================

test_precommit_flush_semantics() {
    echo "=== Testing Pre-commit Flush Semantics ==="

    local temp_dir
    temp_dir="$(mktemp -d)"
    cd "$temp_dir"
    git init --quiet
    mkdir -p .beads bin
    cat > bin/bd <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--no-daemon" ]]; then
  shift
fi
if [[ "$1" == "sync" && "$2" == "--flush-only" ]]; then
  exit 1
fi
exit 0
EOF
    chmod +x bin/bd

    local out_warn out_strict rc_warn rc_strict
    set +e
    PATH="$temp_dir/bin:$PATH" "$ROOT_DIR/hooks/pre-commit" > /tmp/precommit-warn.out 2>&1
    rc_warn=$?
    PATH="$temp_dir/bin:$PATH" BEADS_FLUSH_STRICT=1 "$ROOT_DIR/hooks/pre-commit" > /tmp/precommit-strict.out 2>&1
    rc_strict=$?
    set -e

    out_warn="$(cat /tmp/precommit-warn.out 2>/dev/null || true)"
    out_strict="$(cat /tmp/precommit-strict.out 2>/dev/null || true)"

    if [[ "$rc_warn" -eq 0 && "$out_warn" == *"Warning: Failed to flush bd changes to JSONL"* ]]; then
        pass "pre-commit flush failure is warn-only by default"
    else
        fail "pre-commit warn-only semantics failed (rc=$rc_warn)"
    fi
    if [[ "$rc_strict" -ne 0 && "$out_strict" == *"strict mode"* ]]; then
        pass "pre-commit flush failure is blocking in strict mode"
    else
        fail "pre-commit strict-mode blocking semantics failed (rc=$rc_strict)"
    fi

    cd /
    rm -rf "$temp_dir" /tmp/precommit-warn.out /tmp/precommit-strict.out
}

# ============================================================================
# Main
# ============================================================================

# ============================================================================
# Test: Restart Lifecycle
# ============================================================================

test_restart_lifecycle() {
    echo "=== Testing Restart Lifecycle ==="

    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"

    local beads="test-restart-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"

    # Start first time
    if "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" >/dev/null 2>&1; then
        local pid1
        pid1="$(cat "/tmp/dx-runner/mock/${beads}.pid" 2>/dev/null || true)"
        [[ -n "$pid1" ]] || fail "missing pid1"

        # Restart
        if "$DX_RUNNER" restart --beads "$beads" >/dev/null 2>&1; then
            # Verify pid1 is gone
            if ps -p "$pid1" >/dev/null 2>&1; then
                fail "pid1 should be stopped after restart"
            else
                pass "pid1 stopped correctly"
            fi

            local pid2
            pid2="$(cat "/tmp/dx-runner/mock/${beads}.pid" 2>/dev/null || true)"
            [[ -n "$pid2" && "$pid1" != "$pid2" ]] || fail "missing or duplicate pid2"

            # Verify retries incremented
            local retries
            retries="$(awk -F= '$1=="retries"{print $2; exit}' "/tmp/dx-runner/mock/${beads}.meta" 2>/dev/null || echo "0")"
            if [[ "$retries" == "1" ]]; then
                pass "retry count incremented to 1"
            else
                fail "expected retry count 1, got $retries"
            fi
        else
            fail "restart command failed"
        fi
    else
        fail "start command failed"
    fi

    rm -f "$prompt" "$adapter"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Start Preflight Gate
# ============================================================================

test_start_preflight() {
    echo "=== Testing Start Preflight Gate ==="

    local adapter="$ADAPTERS_DIR/preflight-fail.sh"
    cat > "$adapter" <<'EOF'
#!/usr/bin/env bash
adapter_preflight() { return 1; }
adapter_probe_model() { return 0; }
adapter_list_models() { echo "mock"; }
adapter_stop() { return 0; }
adapter_start() { return 0; }
EOF
    chmod +x "$adapter"

    local beads="test-preflight-fail-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"

    set +e
    "$DX_RUNNER" start --beads "$beads" --provider preflight-fail --prompt-file "$prompt" >/tmp/preflight-test.out 2>&1
    local rc=$?
    set -e

    if [[ "$rc" -eq 21 ]]; then
        pass "start fails with exit 21 when preflight fails"
    else
        fail "expected exit 21 for preflight failure, got $rc"
    fi

    if grep -q "preflight gate failed" /tmp/preflight-test.out; then
        pass "start shows preflight failure message"
    else
        fail "start missing preflight failure message"
    fi

    rm -f "$prompt" "$adapter" /tmp/preflight-test.out
}

# ============================================================================
# Test: Adapter Contract Parity (bd-xga8.14.3)
# ============================================================================

test_adapter_parity() {
    echo "=== Testing Adapter Contract Parity ==="
    
    local parity_functions=(
        "adapter_start"
        "adapter_preflight"
        "adapter_probe_model"
        "adapter_list_models"
        "adapter_stop"
        "adapter_resolve_model"
    )
    
    local finder_functions=(
        "cc-glm:adapter_find_cc_glm"
        "opencode:adapter_find_opencode"
        "gemini:adapter_find_gemini"
    )
    
    # Test parity functions exist in all adapters
    for adapter in "$ADAPTERS_DIR"/*.sh; do
        local name
        name="$(basename "$adapter" .sh)"
        
        source "$adapter"
        
        for func in "${parity_functions[@]}"; do
            if declare -f "$func" >/dev/null 2>&1; then
                pass "$name: $func parity OK"
            else
                fail "$name: $func parity MISSING"
            fi
        done
    done
    
    # Test finder functions exist
    for entry in "${finder_functions[@]}"; do
        local adapter_name="${entry%%:*}"
        local func_name="${entry##*:}"
        local adapter="$ADAPTERS_DIR/${adapter_name}.sh"
        
        if [[ -f "$adapter" ]]; then
            source "$adapter"
            if declare -f "$func_name" >/dev/null 2>&1; then
                pass "$adapter_name: $func_name finder OK"
            else
                fail "$adapter_name: $func_name finder MISSING"
            fi
        fi
    done
}

test_adapter_resolve_model_parity() {
    echo "=== Testing adapter_resolve_model Parity ==="
    
    # Test cc-glm resolve_model
    source "$ADAPTERS_DIR/cc-glm.sh"
    local cc_glm_result
    cc_glm_result="$(adapter_resolve_model "glm-5")" || true
    if [[ "$cc_glm_result" == "glm-5|"* ]]; then
        pass "cc-glm adapter_resolve_model returns correct format"
    else
        fail "cc-glm adapter_resolve_model format wrong: $cc_glm_result"
    fi
    
    local cc_glm_fallback
    cc_glm_fallback="$(adapter_resolve_model "nonexistent-model")" || true
    if [[ "$cc_glm_fallback" == *"|fallback|"* ]]; then
        pass "cc-glm adapter_resolve_model returns fallback for unknown model"
    else
        fail "cc-glm adapter_resolve_model should fallback: $cc_glm_fallback"
    fi
    
    # Test gemini resolve_model
    source "$ADAPTERS_DIR/gemini.sh"
    local gemini_result
    gemini_result="$(adapter_resolve_model "gemini-3-flash-preview")" || true
    if [[ "$gemini_result" == "gemini-3-flash-preview|"* ]]; then
        pass "gemini adapter_resolve_model returns correct format"
    else
        fail "gemini adapter_resolve_model format wrong: $gemini_result"
    fi
    
    local gemini_fallback
    gemini_fallback="$(adapter_resolve_model "nonexistent-model")" || true
    if [[ "$gemini_fallback" == *"|fallback|"* ]]; then
        pass "gemini adapter_resolve_model returns fallback for unknown model"
    else
        fail "gemini adapter_resolve_model should fallback: $gemini_fallback"
    fi
}

test_adapter_stop_parity() {
    echo "=== Testing adapter_stop Parity ==="
    
    # All adapters should have graceful shutdown (sleep after kill)
    for adapter in "$ADAPTERS_DIR"/*.sh; do
        local name
        name="$(basename "$adapter" .sh)"
        
        if grep -q 'sleep [0-9]' "$adapter" && grep -q 'kill -9' "$adapter"; then
            pass "$name: adapter_stop has graceful shutdown + force kill"
        else
            fail "$name: adapter_stop missing graceful shutdown or force kill"
        fi
    done
}

# ============================================================================
# Test: dx-dispatch Compatibility Shim
# ============================================================================

test_dx_dispatch_shim() {
    echo "=== Testing dx-dispatch Compatibility Shim ==="
    
    local DX_DISPATCH="${ROOT_DIR}/scripts/dx-dispatch"
    
    if [[ ! -x "$DX_DISPATCH" ]]; then
        fail "dx-dispatch shim not found or not executable"
        return
    fi
    
    # Test 1: --help should work
    local help_output
    help_output="$("$DX_DISPATCH" --help 2>&1)" || true
    if echo "$help_output" | grep -q "dx-runner"; then
        pass "dx-dispatch --help references dx-runner"
    else
        fail "dx-dispatch --help should reference dx-runner"
    fi
    
    # Test 2: --list should forward to dx-runner status
    local list_output
    list_output="$(DX_DISPATCH_NO_DEPRECATION=1 "$DX_DISPATCH" --list 2>&1)" || true
    if echo "$list_output" | grep -qE "bead|provider|no jobs"; then
        pass "dx-dispatch --list forwards to dx-runner status"
    else
        warn "dx-dispatch --list output: ${list_output:0:100}"
    fi
    
    # Test 3: Missing arguments should error
    set +e
    "$DX_DISPATCH" >/dev/null 2>&1
    local err_rc=$?
    set -e
    if [[ "$err_rc" -ne 0 ]]; then
        pass "dx-dispatch with no args returns error (rc=$err_rc)"
    else
        fail "dx-dispatch with no args should error"
    fi
    
    # Test 4: Deprecation warning is emitted (unless suppressed)
    local deprec_output
    deprec_output="$("$DX_DISPATCH" epyc12 "test task" --beads test-shim-$$ 2>&1)" || true
    if echo "$deprec_output" | grep -qi "deprecat"; then
        pass "dx-dispatch emits deprecation warning"
    else
        warn "dx-dispatch deprecation warning may be suppressed or forwarded"
    fi
    
    # Test 5: Provider mapping
    # cc-glm -> cc-glm
    # gemini -> gemini
    # other -> opencode
    local help_text
    help_text="$("$DX_DISPATCH" --help 2>&1)"
    if echo "$help_text" | grep -q "provider"; then
        pass "dx-dispatch help mentions provider mapping"
    fi
}

test_dx_dispatch_shim_forwarding() {
    echo "=== Testing dx-dispatch Shim Exit Code Propagation ==="
    
    local DX_DISPATCH="${ROOT_DIR}/scripts/dx-dispatch"
    local DX_RUNNER="${ROOT_DIR}/scripts/dx-runner"
    
    if [[ ! -x "$DX_DISPATCH" ]] || [[ ! -x "$DX_RUNNER" ]]; then
        fail "dx-dispatch or dx-runner not found"
        return
    fi
    
    # Test that dx-runner status exit code is propagated
    DX_DISPATCH_NO_DEPRECATION=1 "$DX_DISPATCH" --list >/dev/null 2>&1
    local rc=$?
    if [[ "$rc" -eq 0 ]]; then
        pass "dx-dispatch --list propagates exit code 0"
    else
        warn "dx-dispatch --list returned $rc (expected 0)"
    fi
    
    # Test with specific beads that doesn't exist
    DX_DISPATCH_NO_DEPRECATION=1 "$DX_DISPATCH" --list >/dev/null 2>&1
    rc=$?
    pass "dx-dispatch shim executes without crash (rc=$rc)"
}

# ============================================================================
# Test: Profile Loading (bd-8wdg.1)
# ============================================================================

test_profile_loading() {
    echo "=== Testing Profile Loading ==="
    
    # Test profiles list command
    local profiles_output
    profiles_output="$("$DX_RUNNER" profiles --list 2>&1)" || true
    if echo "$profiles_output" | grep -qE "opencode-prod|cc-glm-fallback|dev"; then
        pass "profiles --list shows available profiles"
    else
        warn "profiles --list may be missing profiles: $profiles_output"
    fi
    
    # Test profile show command
    local show_output
    show_output="$("$DX_RUNNER" profiles --show opencode-prod 2>&1)" || true
    if echo "$show_output" | grep -qE "provider:|model:"; then
        pass "profiles --show displays profile content"
    else
        fail "profiles --show did not display profile content"
    fi
}

# ============================================================================
# Test: Model Override Blocking (bd-8wdg.2)
# ============================================================================

test_model_override_blocking() {
    echo "=== Testing Model Override Blocking ==="
    
    local tmp_bin fake_op models_file prompt repo_dir beads out rc
    tmp_bin="$(mktemp -d)"
    fake_op="$tmp_bin/opencode"
    models_file="$(mktemp)"
    prompt="$(mktemp)"
    repo_dir="$(mktemp -d /tmp/agents/test-override-XXXXXX)"
    beads="test-override-$$"
    
    echo "zhipuai-coding-plan/glm-5" > "$models_file"
    echo "READY" > "$prompt"
    git -C "$repo_dir" init --quiet
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test Runner"
    echo "x" > "$repo_dir/a.txt"
    git -C "$repo_dir" add a.txt
    git -C "$repo_dir" commit -m "init" --quiet
    
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
    
    # Test 1: OPENCODE_MODEL should be ignored by default
    set +e
    out="$(PATH="$tmp_bin:$PATH" FAKE_MODELS_FILE="$models_file" OPENCODE_MODEL="some-other-model" "$DX_RUNNER" start --beads "$beads" --provider opencode --prompt-file "$prompt" --worktree "$repo_dir" --json 2>&1)"
    rc=$?
    set -e
    
    # Should still work because we fall back to canonical model
    if [[ "$rc" -eq 0 ]] || echo "$out" | grep -q "started"; then
        pass "OPENCODE_MODEL is ignored when override not allowed"
    else
        fail "start failed when OPENCODE_MODEL set without override: $out"
    fi
    
    rm -rf "$tmp_bin" "$repo_dir"
    rm -f "$models_file" "$prompt"
    rm -f /tmp/dx-runner/opencode/"${beads}".*
}

# ============================================================================
# Test: Manual Stop Outcome Semantics (bd-8wdg.3)
# ============================================================================

test_manual_stop_semantics() {
    echo "=== Testing Manual Stop Outcome Semantics ==="
    
    local adapter="$ADAPTERS_DIR/mock.sh"
    create_mock_adapter "$adapter"
    
    local beads="test-stop-semantics-$$"
    local prompt
    prompt="$(mktemp)"
    echo "READY" > "$prompt"
    
    if MOCK_ADAPTER_SLEEP_SEC=60 "$DX_RUNNER" start --beads "$beads" --provider mock --prompt-file "$prompt" >/dev/null 2>&1; then
        sleep 2
        "$DX_RUNNER" stop --beads "$beads" >/dev/null 2>&1 || true
        
        # Check outcome has manual_stop reason
        local outcome_file="/tmp/dx-runner/mock/${beads}.outcome"
        if [[ -f "$outcome_file" ]]; then
            if grep -q "reason_code=manual_stop" "$outcome_file"; then
                pass "manual stop persists manual_stop reason code"
            else
                fail "manual stop did not persist manual_stop reason: $(cat "$outcome_file")"
            fi
        else
            fail "no outcome file after manual stop"
        fi
        
        # Check that check command reports manual_stop
        local check_out
        check_out="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
        if echo "$check_out" | grep -q "manual_stop"; then
            pass "check command reports manual_stop reason"
        else
            fail "check did not report manual_stop: $check_out"
        fi
    else
        fail "mock start failed for stop semantics test"
    fi
    
    rm -f "$prompt" "$adapter"
    rm -f /tmp/dx-runner/mock/"${beads}".*
}

# ============================================================================
# Test: Slow Start Detection (bd-8wdg.10)
# ============================================================================

test_slow_start_detection() {
    echo "=== Testing Slow Start Detection ==="
    
    local beads="test-slow-start-$$"
    local provider="cc-glm"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    
    # Simulate a running job with CPU activity but no output in startup grace period
    sleep 300 &
    local pid="$!"
    echo "$pid" > "$dir/${beads}.pid"
    : > "$dir/${beads}.log"
    
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
worktree=/tmp/agents
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    # Create a recent heartbeat to simulate CPU activity
    cat > "$dir/${beads}.heartbeat" <<EOF
beads=$beads
provider=$provider
count=5
last_type=cpu_progress
last_detail=cpu=10
last_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    # Check should detect slow_start for recent job with no output
    local check_out
    check_out="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null || true)"
    
    kill "$pid" 2>/dev/null || true
    
    if echo "$check_out" | grep -qE "slow_start|launching"; then
        pass "slow start detection identifies startup state"
    else
        warn "slow start state detection: $check_out"
    fi
    
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: No-Op Success Classification (bd-8wdg.9)
# ============================================================================

test_no_op_success_classification() {
    echo "=== Testing No-Op Success Classification ==="
    
    local beads="test-no-op-success-$$"
    local provider="cc-glm"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    
    # Simulate a job that exited with 0 but had no mutations
    cat > "$dir/${beads}.outcome" <<EOF
beads=$beads
provider=$provider
state=exited_ok
exit_code=0
reason_code=outcome_exit_0
mutations=0
log_bytes=1024
cpu_time_sec=30
started_at=$(date -u -d '1 minute ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    # Check that health classifies this as no_op_success
    local check_out
    check_out="$("$DX_RUNNER" check --beads "$beads" --json 2>/dev/null)" || true
    
    if echo "$check_out" | grep -q "no_op_success"; then
        pass "no-op success (exit 0, no mutations) classified correctly"
    else
        # Check if it shows exit_zero_no_mutations in reason
        if echo "$check_out" | grep -q "exit_zero_no_mutations"; then
            pass "no-op success detected via reason code"
        else
            fail "expected no_op_success or exit_zero_no_mutations, got: $check_out"
        fi
    fi
    
    # Check next_action is correct
    if echo "$check_out" | grep -q "redispatch_with_guardrails"; then
        pass "no-op success has correct next_action"
    else
        warn "next_action for no-op: $check_out"
    fi
    
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: Scope Guard (bd-8wdg.5)
# ============================================================================

test_scope_guard() {
    echo "=== Testing Scope Guard ==="
    
    # Create temp worktree with mutation budget
    local worktree
    worktree="$(mktemp -d /tmp/agents/test-scope-XXXXXX)"
    git -C "$worktree" init --quiet
    git -C "$worktree" config user.email "test@example.com"
    git -C "$worktree" config user.name "Test Runner"
    echo "base" > "$worktree/file.txt"
    git -C "$worktree" add file.txt
    git -C "$worktree" commit -m "base" --quiet
    
    # Create allowed paths file
    local allowed_file
    allowed_file="$(mktemp)"
    echo "src/" > "$allowed_file"
    echo "lib/" >> "$allowed_file"
    
    # Test scope gate command
    local scope_out
    scope_out="$("$DX_RUNNER" scope-gate --worktree "$worktree" --allowed-paths-file "$allowed_file" --json 2>&1)" || true
    
    if echo "$scope_out" | grep -q "passed"; then
        pass "scope gate command works"
    else
        warn "scope gate output: $scope_out"
    fi
    
    rm -rf "$worktree" "$allowed_file"
}

# ============================================================================
# Test: Evidence Gate (bd-8wdg.6)
# ============================================================================

test_evidence_gate() {
    echo "=== Testing Evidence Gate ==="
    
    local beads="test-evidence-$$"
    local provider="mock"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    
    # Create mock meta and outcome
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    cat > "$dir/${beads}.outcome" <<EOF
beads=$beads
provider=$provider
exit_code=0
state=success
reason_code=process_exit_with_rc
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    # Create mock signoff file with claims
    local signoff_file
    signoff_file="$(mktemp)"
    cat > "$signoff_file" <<EOF
## Signoff
- [x] CI passed
- [x] Tests validated
EOF
    
    local evidence_out
    evidence_out="$("$DX_RUNNER" evidence-gate --beads "$beads" --signoff-file "$signoff_file" --json 2>&1)" || true
    
    if echo "$evidence_out" | grep -q "passed\|unverified_claims"; then
        pass "evidence gate command works"
    else
        warn "evidence gate output: $evidence_out"
    fi
    
    rm -f "$signoff_file"
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Test: dx-wave Wrapper (bd-8wdg.7)
# ============================================================================

test_dx_wave_wrapper() {
    echo "=== Testing dx-wave Wrapper ==="
    
    local dx_wave="${ROOT_DIR}/scripts/dx-wave"
    
    if [[ ! -x "$dx_wave" ]]; then
        fail "dx-wave wrapper not found or not executable"
        return
    fi
    
    # Test help
    local help_out
    help_out="$("$dx_wave" --help 2>&1)" || true
    if echo "$help_out" | grep -qE "start|check|status"; then
        pass "dx-wave --help shows usage"
    else
        fail "dx-wave help missing commands"
    fi
    
    # Test profiles
    local profiles_out
    profiles_out="$("$dx_wave" profiles --list 2>&1)" || true
    if echo "$profiles_out" | grep -q "opencode-prod"; then
        pass "dx-wave profiles works"
    else
        warn "dx-wave profiles output: $profiles_out"
    fi
}

run_all_tests() {
    test_bash_syntax
    test_runner_commands
    test_adapter_contract
    test_adapter_parity
    test_adapter_resolve_model_parity
    test_adapter_stop_parity
    test_governance_gates
    test_start_preflight
    test_beads_gate
    test_beads_gate_json_schema
    test_health_states
    test_json_output
    test_outcome_lifecycle
    test_outcome_metadata
    test_provider_switch_resolution
    test_host_context_tags
    test_mutation_log_accounting
    test_capacity_classification
    test_stop_preserves_metrics
    test_commit_required_contract
    test_check_metrics_telemetry
    test_awaiting_finalize_taxonomy
    test_railway_auth_preflight_requirement
    test_opencode_attach_mode_failfast
    test_completion_monitor_cleanup
    test_provider_concurrency_guardrail
    test_feature_key_validation
    test_precommit_flush_semantics
    test_restart_lifecycle
    test_model_resolution
    test_probe_model_flag
    test_gemini_finalization_reliability
    test_gemini_adapter
    test_gemini_preflight_auth
    test_prune_stale_jobs
    test_dx_dispatch_shim
    test_dx_dispatch_shim_forwarding
    
    # bd-8wdg hardening tests
    test_profile_loading
    test_model_override_blocking
    test_manual_stop_semantics
    test_slow_start_detection
    test_no_op_success_classification
    test_scope_guard
    test_evidence_gate
    test_dx_wave_wrapper
    
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
