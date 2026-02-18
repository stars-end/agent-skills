#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_SCRIPT="${SCRIPT_DIR}/cc-glm-job.sh"

LOG_DIR="/tmp/cc-glm-jobs-test-v34"
TEST_BEADS="test-v34-$$"

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

passed=0
failed=0

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

cleanup() {
  rm -rf "$LOG_DIR" 2>/dev/null || true
}
trap cleanup EXIT

setup() {
  cleanup
  mkdir -p "$LOG_DIR"
}

test_json_status_health() {
  echo ""
  echo "=== Test: status/health JSON output ==="
  setup

  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
  echo "999999" > "$LOG_DIR/${TEST_BEADS}.pid"
  : > "$LOG_DIR/${TEST_BEADS}.log"

  local status_json
  status_json="$("$JOB_SCRIPT" status --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --json 2>/dev/null || true)"
  if echo "$status_json" | grep -q '"jobs":'; then
    pass "status --json returns jobs payload"
  else
    fail "status --json missing jobs payload" "$status_json"
  fi

  local health_json
  health_json="$("$JOB_SCRIPT" health --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --json 2>/dev/null || true)"
  if echo "$health_json" | grep -q '"reason_code"'; then
    pass "health --json includes reason_code"
  else
    fail "health --json missing reason_code" "$health_json"
  fi
}

test_silent_mutation_substate() {
  echo ""
  echo "=== Test: silent_mutation deterministic substate ==="
  setup

  local worktree
  worktree="$(mktemp -d)"
  (
    cd "$worktree"
    git init -q
    echo "a" > a.txt
    git add a.txt
    git commit -q -m "init"
    echo "changed" >> a.txt
  )

  cat > "$LOG_DIR/${TEST_BEADS}.meta" <<EOF
beads=$TEST_BEADS
worktree=$worktree
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
retries=0
EOF
  : > "$LOG_DIR/${TEST_BEADS}.log"

  sleep 30 &
  local pid=$!
  echo "$pid" > "$LOG_DIR/${TEST_BEADS}.pid"

  local check_json
  check_json="$("$JOB_SCRIPT" check --beads "$TEST_BEADS" --log-dir "$LOG_DIR" --stall-minutes 1 --json 2>/dev/null || true)"
  if echo "$check_json" | grep -q '"health":"silent_mutation"'; then
    pass "check classifies silent_mutation when mutations exist and log is empty"
  else
    fail "silent_mutation not detected" "$check_json"
  fi

  kill "$pid" 2>/dev/null || true
  rm -rf "$worktree"
}

test_baseline_gate() {
  echo ""
  echo "=== Test: baseline gate pass/fail ==="
  setup

  local repo
  repo="$(mktemp -d)"
  (
    cd "$repo"
    git init -q
    echo "1" > f.txt
    git add f.txt
    git commit -q -m "c1"
    local c1
    c1="$(git rev-parse HEAD)"
    echo "2" >> f.txt
    git add f.txt
    git commit -q -m "c2"
    local c2
    c2="$(git rev-parse HEAD)"
    echo "$c1" > "$repo/c1"
    echo "$c2" > "$repo/c2"
  )
  local c1 c2
  c1="$(cat "$repo/c1")"
  c2="$(cat "$repo/c2")"

  if "$JOB_SCRIPT" baseline-gate --worktree "$repo" --required-baseline "$c1" --json >/tmp/test-v34-baseline-pass.json 2>/dev/null; then
    pass "baseline-gate passes when runtime is at/after required baseline"
  else
    fail "baseline-gate should have passed"
  fi

  if "$JOB_SCRIPT" baseline-gate --worktree "$repo" --required-baseline "deadbeef" --json >/tmp/test-v34-baseline-fail.json 2>/dev/null; then
    fail "baseline-gate unexpectedly passed for missing commit"
  else
    if grep -q '"reason_code":"required_commit_missing"' /tmp/test-v34-baseline-fail.json; then
      pass "baseline-gate fails with required_commit_missing reason"
    else
      fail "baseline-gate failure reason mismatch" "$(cat /tmp/test-v34-baseline-fail.json)"
    fi
  fi

  # Keep c2 referenced to avoid shellcheck-like warnings under strict modes.
  [[ -n "$c2" ]] || true
  rm -rf "$repo"
}

test_integrity_gate() {
  echo ""
  echo "=== Test: integrity gate pass/fail ==="
  setup

  local repo
  repo="$(mktemp -d)"
  (
    cd "$repo"
    git init -q
    echo "1" > f.txt
    git add f.txt
    git commit -q -m "c1"
    local c1
    c1="$(git rev-parse HEAD)"
    echo "2" >> f.txt
    git add f.txt
    git commit -q -m "c2"
    local c2
    c2="$(git rev-parse HEAD)"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo "$c1" > "$repo/c1"
    echo "$c2" > "$repo/c2"
    echo "$branch" > "$repo/branch"
  )
  local c1 c2 branch
  c1="$(cat "$repo/c1")"
  c2="$(cat "$repo/c2")"
  branch="$(cat "$repo/branch")"

  if "$JOB_SCRIPT" integrity-gate --worktree "$repo" --reported-commit "$c1" --branch "$branch" --json >/tmp/test-v34-integrity-pass.json 2>/dev/null; then
    pass "integrity-gate passes when reported commit is ancestor of branch head"
  else
    fail "integrity-gate should have passed"
  fi

  if "$JOB_SCRIPT" integrity-gate --worktree "$repo" --reported-commit "deadbeef" --branch "$branch" --json >/tmp/test-v34-integrity-fail.json 2>/dev/null; then
    fail "integrity-gate unexpectedly passed for missing commit"
  else
    if grep -q '"reason_code":"reported_commit_not_found"' /tmp/test-v34-integrity-fail.json; then
      pass "integrity-gate fails with reported_commit_not_found reason"
    else
      fail "integrity-gate failure reason mismatch" "$(cat /tmp/test-v34-integrity-fail.json)"
    fi
  fi

  [[ -n "$c2" ]] || true
  rm -rf "$repo"
}

test_feature_key_gate() {
  echo ""
  echo "=== Test: feature-key gate pass/fail ==="
  setup

  local repo
  repo="$(mktemp -d)"
  (
    cd "$repo"
    git init -q
    echo "1" > f.txt
    git add f.txt
    git commit -q -m "base"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo "$branch" > "$repo/branch"

    echo "2" >> f.txt
    git add f.txt
    git commit -q -m $'ok commit\n\nFeature-Key: bd-test'

    echo "3" >> f.txt
    git add f.txt
    git commit -q -m "missing feature key"
  )

  local branch
  branch="$(cat "$repo/branch")"

  if "$JOB_SCRIPT" feature-key-gate --worktree "$repo" --feature-key bd-test --branch "$branch" --base-branch "$branch" --json >/tmp/test-v34-fk-empty.json 2>/dev/null; then
    fail "feature-key gate unexpectedly passed for empty range"
  else
    if grep -q '"reason_code":"no_commits_in_range"' /tmp/test-v34-fk-empty.json; then
      pass "feature-key gate reports no_commits_in_range for empty diff"
    else
      fail "feature-key gate empty range reason mismatch" "$(cat /tmp/test-v34-fk-empty.json)"
    fi
  fi

  # Create base pointer to previous commit for explicit range.
  (
    cd "$repo"
    git branch base-ref HEAD~2 >/dev/null 2>&1
  )

  if "$JOB_SCRIPT" feature-key-gate --worktree "$repo" --feature-key bd-test --branch "$branch" --base-branch base-ref --json >/tmp/test-v34-fk-fail.json 2>/dev/null; then
    fail "feature-key gate unexpectedly passed with missing trailer commit"
  else
    if grep -q '"reason_code":"feature_key_missing_in_commits"' /tmp/test-v34-fk-fail.json; then
      pass "feature-key gate fails when commit trailer is missing"
    else
      fail "feature-key gate failure reason mismatch" "$(cat /tmp/test-v34-fk-fail.json)"
    fi
  fi

  # Amend last commit to add trailer and re-check.
  (
    cd "$repo"
    git commit --amend -q -m $'fixed commit\n\nFeature-Key: bd-test'
  )

  if "$JOB_SCRIPT" feature-key-gate --worktree "$repo" --feature-key bd-test --branch "$branch" --base-branch base-ref --json >/tmp/test-v34-fk-pass.json 2>/dev/null; then
    pass "feature-key gate passes when all commits include expected trailer"
  else
    fail "feature-key gate should have passed after commit amend" "$(cat /tmp/test-v34-fk-pass.json 2>/dev/null || true)"
  fi

  rm -rf "$repo"
}

main() {
  echo "========================================"
  echo "cc-glm-job V3.4 Deterministic Gate Tests"
  echo "========================================"

  test_json_status_health
  test_silent_mutation_substate
  test_baseline_gate
  test_integrity_gate
  test_feature_key_gate

  echo ""
  echo "========================================"
  echo "Results: ${passed} passed, ${failed} failed"
  echo "========================================"

  if [[ $failed -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main
