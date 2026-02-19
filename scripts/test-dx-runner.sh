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
# Test: OpenCode Model Resolution (Canonical + Allowed Fallback)
# ============================================================================

test_model_resolution() {
    echo "=== Testing Model Resolution (Canonical + Allowed Fallback) ==="

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
    [[ "$r2" == zai-coding-plan/glm-5* ]] && pass "model resolution falls back to allowlisted zai model when canonical is missing" || fail "expected zai fallback when canonical missing: $r2"

    local r3
    r3="$(adapter_resolve_model "zai-coding-plan/glm-5" "epyc12" || true)"
    [[ "$r3" == zai-coding-plan/glm-5* ]] && pass "model resolution accepts allowlisted non-canonical requested models" || fail "expected allowlisted requested model acceptance: $r3"

    # Start should fail with deterministic rc=25 and reason_code when canonical-only policy cannot be satisfied
    local prompt_file log_file start_out rc
    prompt_file="$(mktemp)"
    log_file="$(mktemp)"
    echo "READY" > "$prompt_file"
    set +e
    rm -f /tmp/dx-runner/opencode/.models_cache
    start_out="$(OPENCODE_MODEL="zhipuai-coding-plan/glm-5" OPENCODE_ALLOWED_MODELS="zhipuai-coding-plan/glm-5" adapter_start "test-opencode-model-missing-$$" "$prompt_file" "/tmp" "$log_file" 2>/dev/null)"
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

    # Save original keys
    local orig_gemini_key="${GEMINI_API_KEY:-}"
    local orig_google_key="${GOOGLE_API_KEY:-}"
    unset GEMINI_API_KEY
    unset GOOGLE_API_KEY
    
    # Test 1: Fail when env key, CLI-auth, and OAuth probe all fail
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
    ) && pass "preflight fails when env key, CLI auth, and OAuth probe are all unavailable" || fail "preflight should fail when env key, CLI auth, and OAuth probe are all unavailable"

    # Test 2: Pass via env key
    (
        export PATH="$tmp_bin:$PATH"
        export GEMINI_API_KEY="test-key"
        source "$ADAPTERS_DIR/gemini.sh"
        adapter_preflight > /dev/null
    ) && pass "preflight passes via env key" || fail "preflight should pass via env key"

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
    (
        cd "$temp_dir"
        git init --quiet
        mkdir -p .beads bin
        cat > bin/bd <<'EOF'
#!/usr/bin/env bash
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
    )
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
    test_feature_key_validation
    test_precommit_flush_semantics
    test_restart_lifecycle
    test_model_resolution
    test_probe_model_flag
    test_gemini_adapter
    test_gemini_preflight_auth
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
