#!/usr/bin/env bash
#
# Regression test for dx-verify-clean hook-only canonical drift repair.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TEST_DIR="/tmp/dx-verify-clean-test-$$"
HOME_DIR="$TEST_DIR/home"

cleanup() {
  cd / >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

assert_clean() {
  local repo="$1"
  local status
  status="$(git -C "$HOME_DIR/$repo" status --porcelain=v1)"
  [[ -z "$status" ]] || fail "$repo expected clean, got: $status"
}

init_repo() {
  local repo="$1"
  local repo_path="$HOME_DIR/$repo"

  mkdir -p "$repo_path/.githooks"
  git -C "$repo_path" -c init.defaultBranch=master init >/dev/null
  git -C "$repo_path" config user.email test@example.com
  git -C "$repo_path" config user.name "Test Agent"
  cat >"$repo_path/README.md" <<EOF
$repo
EOF
  cat >"$repo_path/.githooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo baseline pre-commit
EOF
  cat >"$repo_path/.githooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
echo baseline commit-msg
EOF
  git -C "$repo_path" add -A
  git -C "$repo_path" commit -m "seed

Feature-Key: bd-seed
Agent: test" >/dev/null
}

mkdir -p "$HOME_DIR"
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
  init_repo "$repo"
done

cat >"$HOME_DIR/affordabot/.githooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo rewritten by local hook bootstrap
EOF

HOME="$HOME_DIR" "$AGENTS_ROOT/scripts/dx-verify-clean.sh" >"$TEST_DIR/hook-only.out"
grep -q "auto-restored hook-only canonical drift" "$TEST_DIR/hook-only.out" \
  || fail "hook-only repair message missing"
assert_clean affordabot
pass "hook-only canonical drift is auto-restored"

cat >"$HOME_DIR/prime-radiant-ai/.githooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo rewritten hook plus real dirt
EOF
cat >>"$HOME_DIR/prime-radiant-ai/README.md" <<'EOF'
real source dirt
EOF

if HOME="$HOME_DIR" "$AGENTS_ROOT/scripts/dx-verify-clean.sh" >"$TEST_DIR/mixed.out" 2>&1; then
  fail "mixed hook + source dirt should fail"
fi
grep -q "README.md" "$TEST_DIR/mixed.out" || fail "mixed dirt output should mention real source dirt"
git -C "$HOME_DIR/prime-radiant-ai" status --porcelain=v1 | grep -q "README.md" \
  || fail "mixed source dirt should not be auto-restored"
pass "mixed canonical dirt still blocks"

cat >"$HOME_DIR/llm-common/.githooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
echo rewritten hook with repair disabled
EOF

if HOME="$HOME_DIR" DX_VERIFY_AUTO_REPAIR_HOOK_DRIFT=0 \
  "$AGENTS_ROOT/scripts/dx-verify-clean.sh" >"$TEST_DIR/disabled.out" 2>&1; then
  fail "disabled hook repair should fail"
fi
git -C "$HOME_DIR/llm-common" status --porcelain=v1 | grep -q ".githooks/commit-msg" \
  || fail "disabled hook drift should remain dirty"
pass "hook repair can be disabled"
