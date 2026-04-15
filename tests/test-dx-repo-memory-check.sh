#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$ROOT/scripts/dx-repo-memory-check"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

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

run_checker_expect() {
  local expected_rc="$1"
  shift
  set +e
  local out
  out="$("$CHECKER" "$@" 2>&1)"
  local rc=$?
  set -e
  if [[ "$rc" -eq "$expected_rc" ]]; then
    echo "$out"
    return 0
  fi
  echo "$out"
  return 1
}

make_repo() {
  local dir="$1"
  git init -q "$dir" >/dev/null
  git -C "$dir" config user.email "dx-test@example.com"
  git -C "$dir" config user.name "DX Test"
  mkdir -p "$dir/docs/architecture" "$dir/src"
  cat > "$dir/docs/architecture/BROWNFIELD_MAP.md" <<'EOF'
---
status: active
owner: dx
last_verified_commit: deadbeef
last_verified_at: 2026-04-15
stale_if_paths:
  - src/**
---
map
EOF
  cat > "$dir/AGENTS.md" <<'EOF'
# AGENTS
Read [Brownfield](docs/architecture/BROWNFIELD_MAP.md)
EOF
  cat > "$dir/src/app.py" <<'EOF'
print("ok")
EOF
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" >/dev/null
}

test_pass_case() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"

  if run_checker_expect 0 --repo "$t" --json >/dev/null; then
    pass "pass case"
  else
    fail "pass case"
  fi
  rm -rf "$t"
}

test_missing_docs_allow_missing() {
  local t
  t="$(mktemp -d)"
  git init -q "$t" >/dev/null
  git -C "$t" config user.email "dx-test@example.com"
  git -C "$t" config user.name "DX Test"
  echo "# AGENTS" > "$t/AGENTS.md"
  git -C "$t" add .
  git -C "$t" commit -m "initial" >/dev/null

  if run_checker_expect 0 --repo "$t" --allow-missing >/dev/null; then
    pass "missing docs allowed with --allow-missing"
  else
    fail "missing docs allowed with --allow-missing"
  fi
  rm -rf "$t"
}

test_malformed_frontmatter_fails() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  cat > "$t/docs/architecture/BROWNFIELD_MAP.md" <<'EOF'
---
status active
owner: dx
---
broken
EOF
  git -C "$t" add docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "break frontmatter" >/dev/null

  if run_checker_expect 1 --repo "$t" >/dev/null; then
    pass "malformed frontmatter fails"
  else
    fail "malformed frontmatter fails"
  fi
  rm -rf "$t"
}

test_missing_agents_link_fails() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  echo "# AGENTS" > "$t/AGENTS.md"
  git -C "$t" add AGENTS.md
  git -C "$t" commit -m "remove link" >/dev/null

  if run_checker_expect 1 --repo "$t" >/dev/null; then
    pass "missing AGENTS link fails"
  else
    fail "missing AGENTS link fails"
  fi
  rm -rf "$t"
}

test_stale_path_fails() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('changed')" > "$t/src/app.py"
  git -C "$t" add src/app.py
  git -C "$t" commit -m "change src only" >/dev/null

  if run_checker_expect 1 --repo "$t" --base-ref HEAD~1 >/dev/null; then
    pass "stale path fails when doc unchanged"
  else
    fail "stale path fails when doc unchanged"
  fi
  rm -rf "$t"
}

test_stale_path_pass_when_doc_changed() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('changed')" > "$t/src/app.py"
  cat >> "$t/docs/architecture/BROWNFIELD_MAP.md" <<'EOF'

updated
EOF
  git -C "$t" add src/app.py docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "change src and map" >/dev/null

  if run_checker_expect 0 --repo "$t" --base-ref HEAD~1 >/dev/null; then
    pass "stale path passes when doc is changed"
  else
    fail "stale path passes when doc is changed"
  fi
  rm -rf "$t"
}

test_valid_waiver_passes() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('changed')" > "$t/src/app.py"
  git -C "$t" add src/app.py
  git -C "$t" commit -m "change src with waiver

Repo-Memory-Waiver: docs/architecture/BROWNFIELD_MAP.md :: source change is isolated to a local test fixture and does not alter architecture map semantics" >/dev/null

  if run_checker_expect 0 --repo "$t" --base-ref HEAD~1 >/dev/null; then
    pass "valid waiver passes"
  else
    fail "valid waiver passes"
  fi
  rm -rf "$t"
}

test_generic_waiver_reason_fails() {
  local t
  local w
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('changed')" > "$t/src/app.py"
  git -C "$t" add src/app.py
  git -C "$t" commit -m "change src only" >/dev/null
  w="$t/waiver.txt"
  cat > "$w" <<'EOF'
Repo-Memory-Waiver: docs/architecture/BROWNFIELD_MAP.md :: not needed and no impact
EOF

  if run_checker_expect 1 --repo "$t" --base-ref HEAD~1 --waiver-file "$w" >/dev/null; then
    pass "generic waiver reason fails"
  else
    fail "generic waiver reason fails"
  fi
  rm -rf "$t"
}

test_hidden_path_glob_matches() {
  local t
  t="$(mktemp -d)"
  make_repo "$t"
  mkdir -p "$t/.github/workflows"
  cat > "$t/docs/architecture/BROWNFIELD_MAP.md" <<'EOF'
---
status: active
owner: dx
last_verified_commit: deadbeef
last_verified_at: 2026-04-15
stale_if_paths:
  - .github/**
---
map
EOF
  echo "name: ci" > "$t/.github/workflows/ci.yml"
  git -C "$t" add .github/workflows/ci.yml docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "add hidden workflow coverage" >/dev/null
  echo "name: changed" > "$t/.github/workflows/ci.yml"
  git -C "$t" add .github/workflows/ci.yml
  git -C "$t" commit -m "change hidden workflow only" >/dev/null

  if run_checker_expect 1 --repo "$t" --base-ref HEAD~1 >/dev/null; then
    pass "hidden path glob matches"
  else
    fail "hidden path glob matches"
  fi
  rm -rf "$t"
}

test_pass_case
test_missing_docs_allow_missing
test_malformed_frontmatter_fails
test_missing_agents_link_fails
test_stale_path_fails
test_stale_path_pass_when_doc_changed
test_valid_waiver_passes
test_generic_waiver_reason_fails
test_hidden_path_glob_matches

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
