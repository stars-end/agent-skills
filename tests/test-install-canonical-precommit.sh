#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/test-install-canonical-precommit.XXXXXX)"
TEST_HOME="$TEST_DIR/home"
LOG_DEFAULT="$TEST_DIR/default.log"
LOG_OPTIN="$TEST_DIR/optin.log"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

mkdir -p "$TEST_HOME/agent-skills"
git -C "$TEST_HOME/agent-skills" init >/dev/null
git -C "$TEST_HOME/agent-skills" config user.email test@example.com
git -C "$TEST_HOME/agent-skills" config user.name "Test Agent"

mkdir -p "$TEST_HOME/agent-skills/.githooks"
cat >"$TEST_HOME/agent-skills/.githooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo legacy-pre-commit
EOF
cat >"$TEST_HOME/agent-skills/.githooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
echo legacy-commit-msg
EOF
chmod +x "$TEST_HOME/agent-skills/.githooks/pre-commit" "$TEST_HOME/agent-skills/.githooks/commit-msg"
git -C "$TEST_HOME/agent-skills" add .githooks/pre-commit .githooks/commit-msg
git -C "$TEST_HOME/agent-skills" commit -m "seed hooks" >/dev/null

HOME="$TEST_HOME" "$ROOT_DIR/scripts/install-canonical-precommit.sh" >"$LOG_DEFAULT" 2>&1

git -C "$TEST_HOME/agent-skills" diff --exit-code -- .githooks/pre-commit .githooks/commit-msg >/dev/null \
  || fail "default mode should not mutate tracked .githooks files"
pass "default mode keeps tracked .githooks clean"

grep -q "Not updating in default mode" "$LOG_DEFAULT" \
  || fail "default mode should warn when versioned hooks differ"
pass "default mode prints warning for differing versioned hooks"

grep -q "CANONICAL COMMIT BLOCKED" "$TEST_HOME/agent-skills/.git/hooks/pre-commit" \
  || fail "default mode should still install generated pre-commit into .git/hooks"
pass "default mode installs generated pre-commit in .git/hooks"

HOME="$TEST_HOME" "$ROOT_DIR/scripts/install-canonical-precommit.sh" --update-versioned >"$LOG_OPTIN" 2>&1

cmp -s "$TEST_HOME/agent-skills/.git/hooks/pre-commit" "$TEST_HOME/agent-skills/.githooks/pre-commit" \
  || fail "opt-in mode should sync versioned pre-commit"
cmp -s "$TEST_HOME/agent-skills/.git/hooks/commit-msg" "$TEST_HOME/agent-skills/.githooks/commit-msg" \
  || fail "opt-in mode should sync versioned commit-msg"
pass "opt-in mode updates versioned .githooks files"

git -C "$TEST_HOME/agent-skills" diff --quiet -- .githooks/pre-commit .githooks/commit-msg \
  || pass "opt-in mode intentionally dirties tracked .githooks for commit"

echo "All install-canonical-precommit hook mode assertions passed."
