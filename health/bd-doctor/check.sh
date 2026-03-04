#!/usr/bin/env bash
# bd-doctor check - canonical Beads health checks for Dolt + ~/bd workflow

set -euo pipefail

BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
EXPECTED_REMOTE_SUBSTR="${BEADS_REPO_REMOTE_SUBSTR:-stars-end/bd}"
MIN_BD_VERSION="${DX_MIN_BD_VERSION:-0.49.4}"

ISSUES=0

fail() {
  echo "❌ $1"
  ISSUES=$((ISSUES + 1))
}

warn() {
  echo "⚠️  $1"
}

pass() {
  echo "✅ $1"
}

echo "🔍 Beads Doctor (canonical mode)"
echo "repo: $BEADS_REPO"

if [[ ! -d "$BEADS_REPO/.git" ]]; then
  fail "Canonical repo missing at $BEADS_REPO"
  echo "   Remediation: git clone git@github.com:stars-end/bd.git $BEADS_REPO"
fi

if [[ "$(pwd -P)" != "$(cd "$BEADS_REPO" 2>/dev/null && pwd -P || echo MISSING)" ]]; then
  fail "Must run from canonical Beads repo"
  echo "   Remediation: cd $BEADS_REPO"
else
  pass "Running from canonical repo"
fi

if command -v bd >/dev/null 2>&1; then
  BD_VERSION="$(bd --version 2>/dev/null | awk '{print $NF}' | head -1 || true)"
  if [[ -n "$BD_VERSION" ]]; then
    if [[ "$(printf '%s\n' "$MIN_BD_VERSION" "$BD_VERSION" | sort -V | head -1)" != "$MIN_BD_VERSION" ]]; then
      fail "bd version too old: $BD_VERSION (minimum $MIN_BD_VERSION)"
    else
      pass "bd version OK: $BD_VERSION"
    fi
  else
    warn "Could not parse bd version"
  fi
else
  fail "bd CLI not found in PATH"
fi

REMOTE_URL="$(git -C "$BEADS_REPO" remote get-url origin 2>/dev/null || true)"
if [[ -z "$REMOTE_URL" ]]; then
  fail "origin remote missing in $BEADS_REPO"
elif [[ "$REMOTE_URL" != *"$EXPECTED_REMOTE_SUBSTR"* ]]; then
  fail "origin remote mismatch: $REMOTE_URL"
  echo "   Expected to contain: $EXPECTED_REMOTE_SUBSTR"
else
  pass "origin remote OK: $REMOTE_URL"
fi

if [[ -f "$BEADS_REPO/.beads/beads.db" && -f "$BEADS_REPO/.beads/bd.db" ]]; then
  fail "DB ambiguity detected: both .beads/beads.db and .beads/bd.db exist"
  echo "   Remediation: archive/remove .beads/beads.db"
else
  pass "No DB ambiguity (Dolt data path in ~/bd/.beads/dolt is canonical for active fleet ops)"
fi

if command -v bd >/dev/null 2>&1; then
  if bd doctor --json 2>/dev/null | grep -q '"status":"error"'; then
    fail "bd doctor reports hard errors"
    echo "   Remediation: run ~/.agent/skills/health/bd-doctor/fix.sh"
  else
    pass "bd doctor reports no hard errors"
  fi
fi

if [[ $ISSUES -eq 0 ]]; then
  echo "✅ Beads doctor check passed"
  exit 0
fi

echo "❌ Found $ISSUES issue(s)"
echo "Run: ~/.agent/skills/health/bd-doctor/fix.sh"
exit 1
