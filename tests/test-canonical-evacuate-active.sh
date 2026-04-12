#!/usr/bin/env bash
#
# Regression test for active-hours canonical rescue evacuation.
# The rescue path must bypass feature-work hooks and preserve dirty files before reset.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TEST_DIR="/tmp/dx-canonical-evacuate-test-$$"
HOME_DIR="$TEST_DIR/home"
ORIGIN="$TEST_DIR/origin.git"
SCRIPT_OUTPUT="$TEST_DIR/canonical-evacuate.out"
TEST_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cleanup() {
  cd / >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -q "$pattern" "$file"; then
    echo "PASS: $message"
  else
    echo "FAIL: $message" >&2
    echo "  missing pattern: $pattern" >&2
    echo "  file: $file" >&2
    exit 1
  fi
}

assert_missing() {
  local path="$1"
  local message="$2"

  if [[ ! -e "$path" ]]; then
    echo "PASS: $message"
  else
    echo "FAIL: $message" >&2
    echo "  still exists: $path" >&2
    exit 1
  fi
}

mkdir -p "$HOME_DIR" "$TEST_DIR/seed"
git -c init.defaultBranch=master init --bare "$ORIGIN" >/dev/null

git -C "$TEST_DIR/seed" -c init.defaultBranch=master init >/dev/null
git -C "$TEST_DIR/seed" config user.email test@example.com
git -C "$TEST_DIR/seed" config user.name "Test Agent"
cat >"$TEST_DIR/seed/README.md" <<'EOF'
seed
EOF
mkdir -p "$TEST_DIR/seed/.githooks"
cat >"$TEST_DIR/seed/.githooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
msg_file="$1"
if ! grep -q '^Feature-Key: bd-[a-z0-9]' "$msg_file"; then
  echo "blocked by test commit-msg hook" >&2
  exit 1
fi
EOF
cat >"$TEST_DIR/seed/.githooks/pre-push" <<'EOF'
#!/usr/bin/env bash
echo "blocked by test pre-push hook" >&2
exit 1
EOF
chmod +x "$TEST_DIR/seed/.githooks/commit-msg" "$TEST_DIR/seed/.githooks/pre-push"
git -C "$TEST_DIR/seed" add -A
git -C "$TEST_DIR/seed" commit -m "seed

Feature-Key: bd-seed
Agent: test" >/dev/null
git -C "$TEST_DIR/seed" branch -M master
git -C "$TEST_DIR/seed" remote add origin "$ORIGIN"
git -C "$TEST_DIR/seed" -c core.hooksPath=/dev/null push origin master >/dev/null

git clone "$ORIGIN" "$HOME_DIR/affordabot" >/dev/null 2>&1
git -C "$HOME_DIR/affordabot" config user.email test@example.com
git -C "$HOME_DIR/affordabot" config user.name "Test Agent"
git -C "$HOME_DIR/affordabot" config core.hooksPath .githooks

mkdir -p "$HOME_DIR/affordabot/docs"
cat >"$HOME_DIR/affordabot/docs/rescue.md" <<'EOF'
dirty rescue content
EOF

HOME="$HOME_DIR" \
PATH="$TEST_PATH" \
DIRTY_EVICT_MINUTES=0 \
DIRTY_WARN_MINUTES=0 \
"$AGENTS_ROOT/scripts/canonical-evacuate-active.sh" >"$SCRIPT_OUTPUT"

assert_missing "$HOME_DIR/affordabot/docs/rescue.md" "canonical dirty file reset after rescue"
assert_file_contains "$SCRIPT_OUTPUT" "OK: affordabot reset to origin/master after dirty evacuation" "evacuation succeeded"

rescue_ref="$(git --git-dir="$ORIGIN" for-each-ref --format='%(refname:short)' 'refs/heads/rescue-*' | head -1)"
if [[ -z "$rescue_ref" ]]; then
  echo "FAIL: rescue branch was not pushed" >&2
  exit 1
fi
git --git-dir="$ORIGIN" show "$rescue_ref:docs/rescue.md" | grep -q "dirty rescue content"
echo "PASS: rescue branch preserves dirty content"

git --git-dir="$ORIGIN" log -1 --format=%B "$rescue_ref" | grep -q "Feature-Key: bd-rescue"
echo "PASS: rescue commit uses hook-compatible Feature-Key"
