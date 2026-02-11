#!/usr/bin/env bash
set -euo pipefail

# test-cc-glm-wave-parse.sh
#
# Minimal self-check script for cc-glm-wave.sh parser.
# Creates a tiny manifest and proves dependent tasks are placed in later waves.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE_SCRIPT="${SCRIPT_DIR}/cc-glm-wave.sh"

usage() {
  cat <<'EOF'
test-cc-glm-wave-parse.sh

Minimal self-check for cc-glm-wave.sh depends_on array parsing.

Tests that:
  1. Parser correctly handles depends_on = ["a", "b"] -> a,b
  2. Wave planner places dependent tasks in later waves

Usage:
  test-cc-glm-wave-parse.sh
EOF
}

run_test() {
  local test_manifest
  test_manifest="$(mktemp -t cc-glm-parse-test-XXXXXX.toml)"

  # Create minimal test manifest
  cat > "$test_manifest" <<'EOF'
# Minimal test for depends_on parsing
[[tasks]]
id = "task-a"
repo = "test-repo"
worktree = "/tmp/test-a"
prompt_file = "/tmp/a.prompt"
depends_on = []

[[tasks]]
id = "task-b"
repo = "test-repo"
worktree = "/tmp/test-b"
prompt_file = "/tmp/b.prompt"
depends_on = ["task-a"]

[[tasks]]
id = "task-c"
repo = "test-repo"
worktree = "/tmp/test-c"
prompt_file = "/tmp/c.prompt"
depends_on = ["task-a", "task-b"]
EOF

  echo "=== Test: depends_on array parsing and wave planning ==="
  echo ""

  # Create temp output dir
  local out_dir
  out_dir="$(mktemp -d -t cc-glm-wave-out-XXXXXX)"

  # Run plan command
  echo "Running: cc-glm-wave.sh plan --manifest <test.toml> --out-dir <dir>"
  echo ""
  "$WAVE_SCRIPT" plan --manifest "$test_manifest" --out-dir "$out_dir" 2>&1 | grep -E "^Wave|^Total|^    -" || true

  echo ""
  echo "=== Validation Results ==="
  echo ""

  local passed=0 failed=0

  # Test 1: task-a in wave 0 (no deps)
  if grep -q "task-a" "$out_dir/"*"-wave-0.txt" 2>/dev/null; then
    echo "PASS: task-a in wave 0 (no deps)"
    ((passed++))
  else
    echo "FAIL: task-a NOT in wave 0"
    ((failed++))
  fi

  # Test 2: task-b in wave 1 (depends on task-a)
  if grep -q "task-b" "$out_dir/"*"-wave-1.txt" 2>/dev/null; then
    echo "PASS: task-b in wave 1 (depends_on=[task-a])"
    ((passed++))
  else
    echo "FAIL: task-b NOT in wave 1"
    ((failed++))
  fi

  # Test 3: task-c in wave 2 (depends on task-a and task-b)
  if grep -q "task-c" "$out_dir/"*"-wave-2.txt" 2>/dev/null; then
    echo "PASS: task-c in wave 2 (depends_on=[task-a,task-b])"
    ((passed++))
  else
    echo "FAIL: task-c NOT in wave 2"
    ((failed++))
  fi

  # Cleanup
  rm -rf "$test_manifest" "$out_dir"

  echo ""
  echo "=== Summary: $passed passed, $failed failed ==="
  return "$failed"
}

# Run test
run_test
