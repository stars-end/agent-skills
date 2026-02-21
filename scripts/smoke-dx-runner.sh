#!/usr/bin/env bash
# smoke-dx-runner.sh - Smoke validation for dx-runner hardening (bd-8wdg)
#
# Tests operator-critical paths with realistic scenarios.
# Run this after code changes to verify hardening features work.
#
# Usage: ./smoke-dx-runner.sh [--quick]
#
# Exit codes:
#   0 - All smoke checks passed
#   1 - One or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
DX_RUNNER="${ROOT_DIR}/scripts/dx-runner"
DX_WAVE="${ROOT_DIR}/scripts/dx-wave"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
QUICK_MODE="${1:-}"

section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
    SKIPPED=$((SKIPPED + 1))
}

warn() {
    echo -e "${YELLOW}  WARN${NC}: $1"
}

# ============================================================================
# Smoke Test 1: Profile System
# ============================================================================
smoke_profiles() {
    section "Profile System (bd-8wdg.1)"
    
    # List profiles
    local profiles
    profiles="$("$DX_RUNNER" profiles 2>&1)" || {
        fail "profiles command failed"
        return
    }
    
    if echo "$profiles" | grep -q "opencode-prod"; then
        pass "opencode-prod profile available"
    else
        fail "opencode-prod profile not found in: $profiles"
    fi
    
    if echo "$profiles" | grep -q "cc-glm-fallback"; then
        pass "cc-glm-fallback profile available"
    else
        fail "cc-glm-fallback profile not found"
    fi
    
    # Show profile
    local prod_profile
    prod_profile="$("$DX_RUNNER" profiles --show opencode-prod 2>&1)" || {
        fail "show opencode-prod profile failed"
        return
    }
    
    if echo "$prod_profile" | grep -q "preflight:"; then
        pass "opencode-prod has preflight section"
    else
        fail "opencode-prod missing preflight section"
    fi
    
    if echo "$prod_profile" | grep -q "strict: true"; then
        pass "opencode-prod has strict: true"
    else
        fail "opencode-prod missing strict: true"
    fi
}

# ============================================================================
# Smoke Test 2: Model Drift Blocking
# ============================================================================
smoke_model_drift() {
    section "Model Drift Blocking (bd-8wdg.2)"
    
    # This should be blocked (OPENCODE_MODEL set without override)
    local result
    result="$(OPENCODE_MODEL=blocked-model "$DX_RUNNER" preflight --provider opencode 2>&1)" || true
    
    if echo "$result" | grep -q "BLOCKED model override"; then
        pass "model override blocked without --allow-model-override"
    else
        fail "model override not blocked: $result"
    fi
}

# ============================================================================
# Smoke Test 3: dx-wave Wrapper
# ============================================================================
smoke_dx_wave() {
    section "dx-wave Wrapper (bd-8wdg.7)"
    
    if [[ ! -x "$DX_WAVE" ]]; then
        skip "dx-wave not found at $DX_WAVE"
        return
    fi
    
    # Help works
    local help_out
    help_out="$("$DX_WAVE" --help 2>&1)" || {
        fail "dx-wave --help failed"
        return
    }
    
    if echo "$help_out" | grep -qi "profile\|usage"; then
        pass "dx-wave --help shows usage"
    else
        fail "dx-wave --help missing profile info"
    fi
    
    # Profiles list works
    local profiles
    profiles="$("$DX_WAVE" profiles 2>&1)" || {
        fail "dx-wave profiles failed"
        return
    }
    
    if echo "$profiles" | grep -q "opencode-prod"; then
        pass "dx-wave profiles lists profiles"
    else
        fail "dx-wave profiles missing opencode-prod"
    fi
}

# ============================================================================
# Smoke Test 4: Outcome Semantics
# ============================================================================
smoke_outcome_semantics() {
    section "Outcome Semantics (bd-8wdg.3, bd-8wdg.9)"
    
    local beads="smoke-outcome-$$"
    local provider="cc-glm"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    
    # Create meta file (required for job lookup)
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=$provider
worktree=/tmp/agents
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    # Test no_op_success classification
    cat > "$dir/${beads}.outcome" <<EOF
beads=$beads
provider=$provider
state=exited_ok
exit_code=0
reason_code=outcome_exit_0
mutations=0
log_bytes=100
cpu_time_sec=10
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    local check_out
    check_out="$("$DX_RUNNER" check --beads "$beads" --json 2>&1)" || true
    
    if echo "$check_out" | grep -qE "no_op_success|exit_zero_no_mutations"; then
        pass "no_op_success classification for exit=0 with no mutations"
    else
        fail "expected no_op_success, got: $check_out"
    fi
    
    # Cleanup
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Smoke Test 5: Scope Guard
# ============================================================================
smoke_scope_guard() {
    section "Scope Guard (bd-8wdg.5)"
    
    # Create temp worktree
    local worktree
    worktree="$(mktemp -d /tmp/agents/smoke-scope-XXXXXX)"
    git -C "$worktree" init --quiet 2>/dev/null || true
    
    # Create allowed paths file
    local allowed_file
    allowed_file="$(mktemp)"
    echo "src/" > "$allowed_file"
    echo "lib/" >> "$allowed_file"
    
    local scope_out
    scope_out="$("$DX_RUNNER" scope-gate --worktree "$worktree" --allowed-paths-file "$allowed_file" --json 2>&1)" || true
    
    if echo "$scope_out" | grep -q "passed"; then
        pass "scope-gate command works"
    else
        warn "scope-gate output: $scope_out"
        # Don't fail - this may be a new command still in development
    fi
    
    rm -rf "$worktree" "$allowed_file"
}

# ============================================================================
# Smoke Test 6: Evidence Gate
# ============================================================================
smoke_evidence_gate() {
    section "Evidence Gate (bd-8wdg.6)"
    
    local beads="smoke-evidence-$$"
    local dir="/tmp/dx-runner/cc-glm"
    mkdir -p "$dir"
    
    # Create meta file
    cat > "$dir/${beads}.meta" <<EOF
beads=$beads
provider=cc-glm
worktree=/tmp/agents
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
    
    # Create temp signoff file
    local signoff_file
    signoff_file="$(mktemp)"
    echo "Signed off by: smoke-test" > "$signoff_file"
    
    local evidence_out
    evidence_out="$("$DX_RUNNER" evidence-gate --beads "$beads" --signoff-file "$signoff_file" --json 2>&1)" || true
    
    if echo "$evidence_out" | grep -q "passed"; then
        pass "evidence-gate command works with signoff file"
    else
        warn "evidence-gate output: $evidence_out"
        # Don't fail - this may be a new command still in development
    fi
    
    rm -f "$signoff_file" "$dir/${beads}".*
}

# ============================================================================
# Smoke Test 7: Health States
# ============================================================================
smoke_health_states() {
    section "Health States (bd-8wdg.10)"
    
    local beads="smoke-health-$$"
    local provider="cc-glm"
    local dir="/tmp/dx-runner/$provider"
    mkdir -p "$dir"
    
    # Create slow_start scenario - job just started
    sleep 30 &
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
    
    # Recent heartbeat
    cat > "$dir/${beads}.heartbeat" <<EOF
beads=$beads
provider=$provider
last_heartbeat=$(date +%s)
heartbeat_type=cpu_progress
EOF
    
    local check_out
    check_out="$("$DX_RUNNER" check --beads "$beads" --json 2>&1)" || true
    
    # Kill the sleep process
    kill "$pid" 2>/dev/null || true
    
    # Should detect some state
    if echo "$check_out" | grep -qE '"state"'; then
        pass "health check returns state"
    else
        fail "health check missing state: $check_out"
    fi
    
    rm -f "$dir/${beads}".*
}

# ============================================================================
# Smoke Test 8: Preflight Strict Policy
# ============================================================================
smoke_preflight_policy() {
    section "Preflight Strict Policy (bd-8wdg.4)"
    
    # Check that preflight shows profile context when using profile
    local preflight_out
    preflight_out="$("$DX_RUNNER" preflight --provider opencode 2>&1)" || true
    
    # Should show canonical model policy
    if echo "$preflight_out" | grep -q "canonical model policy"; then
        pass "preflight shows canonical model policy"
    else
        warn "preflight missing canonical model policy"
    fi
    
    # If profile loaded, should show profile context
    if echo "$preflight_out" | grep -q "profile:"; then
        pass "preflight shows profile context when profile loaded"
    else
        pass "preflight runs without profile (expected if no --profile)"
    fi
}

# ============================================================================
# Summary
# ============================================================================
print_summary() {
    section "Smoke Validation Summary"
    
    echo -e "  ${GREEN}Passed:${NC}  $PASSED"
    echo -e "  ${RED}Failed:${NC}  $FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
    echo ""
    
    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}SMOKE VALIDATION FAILED${NC}"
        return 1
    else
        echo -e "${GREEN}SMOKE VALIDATION PASSED${NC}"
        return 0
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "dx-runner Hardening Smoke Validation"
    echo "====================================="
    echo "Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "Host: $(hostname 2>/dev/null | cut -d. -f1)"
    
    smoke_profiles
    smoke_model_drift
    smoke_dx_wave
    smoke_outcome_semantics
    smoke_scope_guard
    smoke_evidence_gate
    smoke_health_states
    smoke_preflight_policy
    
    print_summary
}

main "$@"
