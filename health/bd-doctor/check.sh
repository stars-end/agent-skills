#!/usr/bin/env bash
# bd-doctor check - canonical Beads health checks for Dolt + dedicated runtime workflow

set -euo pipefail

BEADS_RUNTIME="${BEADS_DIR:-$HOME/.beads-runtime/.beads}"
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
echo "runtime: $BEADS_RUNTIME"

if [[ ! -d "$BEADS_RUNTIME" ]]; then
  fail "Active runtime missing at $BEADS_RUNTIME"
  echo "   Remediation: hydrate $BEADS_RUNTIME with epyc12 Dolt SQL metadata/config"
elif [[ ! -f "$BEADS_RUNTIME/metadata.json" || ! -f "$BEADS_RUNTIME/config.yaml" ]]; then
  fail "Active runtime is missing metadata.json or config.yaml"
  echo "   Remediation: hydrate $BEADS_RUNTIME with epyc12 Dolt SQL metadata/config"
else
  pass "Active runtime metadata/config present"
fi

if command -v bd >/dev/null 2>&1; then
  BD_PATH="$(command -v bd)"
  pass "bd binary in PATH: $BD_PATH"
  if [[ "$BD_PATH" == "/home/linuxbrew/.linuxbrew/bin/bd" ]]; then
    fail "Legacy Linuxbrew bd is active in PATH (not Dolt-capable for fleet contract)"
    echo "   Remediation: export PATH=\"$HOME/.local/bin:$PATH\""
    echo "   Remediation: export BD_BIN=\"$HOME/.local/bin/bd\""
  fi
  if [[ -n "${BD_BIN:-}" && "$BD_BIN" != "$HOME/.local/bin/bd" ]]; then
    fail "BD_BIN override points away from canonical binary: $BD_BIN"
    echo "   Remediation: unset BD_BIN"
    echo "   Remediation: export BD_BIN=\"$HOME/.local/bin/bd\""
  fi
  BD_VERSION="$(bd version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ -n "$BD_VERSION" ]]; then
    if [[ "$(printf '%s\n' "$MIN_BD_VERSION" "$BD_VERSION" | sort -V | head -1)" != "$MIN_BD_VERSION" ]]; then
      fail "bd version too old: $BD_VERSION (minimum $MIN_BD_VERSION)"
    else
      pass "bd version OK: $BD_VERSION"
    fi
  else
    warn "Could not parse bd version"
  fi
  if ! bd dolt --help >/dev/null 2>&1; then
    fail "Active bd binary does not support 'bd dolt' commands"
    echo "   Remediation: export BD_BIN=\"$HOME/.local/bin/bd\""
    echo "   Remediation: hash -r"
  else
    pass "bd dolt subcommands available"
  fi
else
  fail "bd CLI not found in PATH"
fi

if [[ -f "$BEADS_RUNTIME/beads.db" && -f "$BEADS_RUNTIME/bd.db" ]]; then
  fail "DB ambiguity detected in runtime: both beads.db and bd.db exist"
  echo "   Remediation: archive/remove $BEADS_RUNTIME/beads.db"
else
  pass "No DB ambiguity in active runtime ($BEADS_RUNTIME)"
fi

if command -v bd >/dev/null 2>&1; then
  if (cd "$(dirname "$BEADS_RUNTIME")" && BEADS_DIR="$BEADS_RUNTIME" bd dolt test --json >/dev/null 2>&1); then
    pass "bd dolt connectivity OK"
  else
    fail "bd dolt connectivity failed"
  fi
  if (cd "$(dirname "$BEADS_RUNTIME")" && BEADS_DIR="$BEADS_RUNTIME" bd doctor --json 2>/dev/null | grep -q '"status":"error"'); then
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
