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
# Main
# ============================================================================

run_all_tests() {
    test_bash_syntax
    test_runner_commands
    test_adapter_contract
    test_governance_gates
    test_health_states
    test_json_output
    
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
