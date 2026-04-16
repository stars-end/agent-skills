#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$ROOT/scripts/dx-repo-memory-audit"
GUARD="$ROOT/scripts/dx-repo-memory-guard"
REFRESH="$ROOT/scripts/dx-repo-memory-refresh"
REFRESH_ALL="$ROOT/scripts/dx-repo-memory-refresh-all"

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

make_repo() {
  local dir="$1"
  git init -q "$dir" >/dev/null
  git -C "$dir" config user.email "dx-test@example.com"
  git -C "$dir" config user.name "DX Test"
  mkdir -p "$dir/docs/architecture" "$dir/src"
  cat > "$dir/src/app.py" <<'EOF'
print("ok")
EOF
  git -C "$dir" add src/app.py
  git -C "$dir" commit -m "initial source" >/dev/null
  local commit
  commit="$(git -C "$dir" rev-parse HEAD)"
  cat > "$dir/docs/architecture/BROWNFIELD_MAP.md" <<EOF
---
repo_memory: true
status: active
owner: dx
last_verified_commit: $commit
last_verified_at: 2026-04-15T00:00:00Z
stale_if_paths:
  - src/**
---
# Map
EOF
  cat > "$dir/AGENTS.md" <<'EOF'
# AGENTS
Read [Brownfield](docs/architecture/BROWNFIELD_MAP.md)
EOF
  git -C "$dir" add docs/architecture/BROWNFIELD_MAP.md AGENTS.md
  git -C "$dir" commit -m "add repo memory" >/dev/null
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
cur = data
for part in sys.argv[2].split("."):
    cur = cur[part]
print(cur)
PY
}

test_audit_clean() {
  local t out
  t="$(mktemp -d)"
  make_repo "$t"
  out="$t/audit.json"
  if "$AUDIT" --repo "$t" --age-days 9999 --json > "$out" && [[ "$(json_field "$out" status)" == "pass" ]]; then
    pass "audit clean repo passes"
  else
    cat "$out" || true
    fail "audit clean repo passes"
  fi
  rm -rf "$t"
}

test_audit_stale_after_source_change() {
  local t out rc
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('changed')" > "$t/src/app.py"
  git -C "$t" add src/app.py
  git -C "$t" commit -m "change source" >/dev/null
  out="$t/audit.json"
  set +e
  "$AUDIT" --repo "$t" --age-days 9999 --json > "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 && "$(json_field "$out" status)" == "stale" && "$(json_field "$out" summary.stale_docs)" == "1" ]]; then
    pass "audit detects stale source changes"
  else
    cat "$out" || true
    fail "audit detects stale source changes"
  fi
  rm -rf "$t"
}

test_audit_passes_when_source_and_map_change_together() {
  local t out rc baseline
  t="$(mktemp -d)"
  make_repo "$t"
  baseline="$(git -C "$t" rev-parse HEAD)"
  echo "print('changed')" > "$t/src/app.py"
  cat > "$t/docs/architecture/BROWNFIELD_MAP.md" <<EOF
---
repo_memory: true
status: active
owner: dx
last_verified_commit: $baseline
last_verified_at: 2026-04-15T00:00:00Z
stale_if_paths:
  - src/**
---
# Map

Updated for source change.
EOF
  git -C "$t" add src/app.py docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "change source and map" >/dev/null
  out="$t/audit.json"
  set +e
  "$AUDIT" --repo "$t" --age-days 9999 --json > "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && "$(json_field "$out" status)" == "pass" ]]; then
    pass "audit passes when source and map change together"
  else
    cat "$out" || true
    fail "audit passes when source and map change together"
  fi
  rm -rf "$t"
}

test_audit_ignores_map_only_changes() {
  local t out rc baseline
  t="$(mktemp -d)"
  make_repo "$t"
  baseline="$(git -C "$t" rev-parse HEAD)"
  cat > "$t/docs/architecture/BROWNFIELD_MAP.md" <<EOF
---
repo_memory: true
status: active
owner: dx
last_verified_commit: $baseline
last_verified_at: 2026-04-15T00:00:00Z
stale_if_paths:
  - docs/**
---
# Map
EOF
  git -C "$t" add docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "set docs stale scope" >/dev/null
  echo "" >> "$t/docs/architecture/BROWNFIELD_MAP.md"
  echo "Metadata-only touch" >> "$t/docs/architecture/BROWNFIELD_MAP.md"
  git -C "$t" add docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "map-only update" >/dev/null
  out="$t/audit.json"
  set +e
  "$AUDIT" --repo "$t" --age-days 9999 --json > "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && "$(json_field "$out" status)" == "pass" ]]; then
    pass "audit ignores repo-memory map-only changes"
  else
    cat "$out" || true
    fail "audit ignores repo-memory map-only changes"
  fi
  rm -rf "$t"
}

test_audit_stale_for_non_map_docs_changes() {
  local t out rc baseline
  t="$(mktemp -d)"
  make_repo "$t"
  baseline="$(git -C "$t" rev-parse HEAD)"
  cat > "$t/docs/architecture/BROWNFIELD_MAP.md" <<EOF
---
status: active
owner: dx
last_verified_commit: $baseline
last_verified_at: 2026-04-15T00:00:00Z
stale_if_paths:
  - docs/**
---
# Map
EOF
  git -C "$t" add docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "set docs stale scope" >/dev/null
  mkdir -p "$t/docs/policy"
  cat > "$t/docs/policy/brief.md" <<'EOF'
Policy note.
EOF
  git -C "$t" add docs/policy/brief.md
  git -C "$t" commit -m "non-map docs update" >/dev/null
  out="$t/audit.json"
  set +e
  "$AUDIT" --repo "$t" --age-days 9999 --json > "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 && "$(json_field "$out" status)" == "stale" && "$(json_field "$out" summary.stale_docs)" == "1" ]]; then
    pass "audit still flags non-map docs changes"
  else
    cat "$out" || true
    fail "audit still flags non-map docs changes"
  fi
  rm -rf "$t"
}

test_audit_ignores_legacy_architecture_docs() {
  local t out
  t="$(mktemp -d)"
  make_repo "$t"
  cat > "$t/docs/architecture/2026-01-01-old-decision.md" <<'EOF'
# Old Decision

This predates the repo-memory map contract.
EOF
  git -C "$t" add docs/architecture/2026-01-01-old-decision.md
  git -C "$t" commit -m "add legacy architecture doc" >/dev/null
  out="$t/audit.json"
  if "$AUDIT" --repo "$t" --age-days 9999 --json > "$out" && [[ "$(json_field "$out" status)" == "pass" ]] && [[ "$(json_field "$out" summary.docs)" == "1" ]]; then
    pass "audit ignores legacy architecture docs"
  else
    cat "$out" || true
    fail "audit ignores legacy architecture docs"
  fi
  rm -rf "$t"
}

test_guard_allows_docs() {
  local t out
  t="$(mktemp -d)"
  make_repo "$t"
  cat >> "$t/docs/architecture/BROWNFIELD_MAP.md" <<'EOF'

Updated.
EOF
  git -C "$t" add docs/architecture/BROWNFIELD_MAP.md
  git -C "$t" commit -m "doc update" >/dev/null
  out="$t/guard.json"
  if "$GUARD" --repo "$t" --base-ref HEAD~1 --json > "$out" && [[ "$(json_field "$out" status)" == "pass" ]]; then
    pass "guard allows docs architecture diff"
  else
    cat "$out" || true
    fail "guard allows docs architecture diff"
  fi
  rm -rf "$t"
}

test_guard_blocks_source() {
  local t out rc
  t="$(mktemp -d)"
  make_repo "$t"
  echo "print('bad')" > "$t/src/app.py"
  git -C "$t" add src/app.py
  git -C "$t" commit -m "source update" >/dev/null
  out="$t/guard.json"
  set +e
  "$GUARD" --repo "$t" --base-ref HEAD~1 --json > "$out"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 && "$(json_field "$out" status)" == "fail" && "$(json_field "$out" summary.forbidden)" == "1" ]]; then
    pass "guard blocks source diff"
  else
    cat "$out" || true
    fail "guard blocks source diff"
  fi
  rm -rf "$t"
}

test_refresh_gh_pr_flags() {
  if grep -Fq -- '--head "$BRANCH"' "$REFRESH" &&
    grep -Fq -- '--base "$DEFAULT_BRANCH"' "$REFRESH"; then
    pass "refresh PR create uses explicit --head and --base"
  else
    fail "refresh PR create uses explicit --head and --base"
  fi
}

test_refresh_pr_creation_verified() {
  if rg -q -- 'gh pr create returned success but no open PR found' "$REFRESH"; then
    pass "refresh verifies PR exists before success log"
  else
    fail "refresh verifies PR exists before success log"
  fi
}

test_refresh_rolling_branch_push_mode() {
  if grep -Fq -- 'push --force-with-lease -u origin "$BRANCH"' "$REFRESH"; then
    pass "refresh rolling branch push uses --force-with-lease"
  else
    fail "refresh rolling branch push uses --force-with-lease"
  fi
}

test_refresh_all_targets_canonical_repos() {
  if grep -Fq -- 'agent-skills affordabot prime-radiant-ai llm-common' "$REFRESH_ALL" &&
    grep -Fq -- 'dx-repo-memory-refresh' "$REFRESH_ALL"; then
    pass "refresh-all targets canonical repos"
  else
    fail "refresh-all targets canonical repos"
  fi
}

test_audit_clean
test_audit_stale_after_source_change
test_audit_passes_when_source_and_map_change_together
test_audit_ignores_map_only_changes
test_audit_stale_for_non_map_docs_changes
test_audit_ignores_legacy_architecture_docs
test_guard_allows_docs
test_guard_blocks_source
test_refresh_gh_pr_flags
test_refresh_pr_creation_verified
test_refresh_rolling_branch_push_mode
test_refresh_all_targets_canonical_repos

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
