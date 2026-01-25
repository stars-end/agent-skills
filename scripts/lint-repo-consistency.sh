#!/usr/bin/env bash
# lint-repo-consistency.sh
# Repo-wide guardrails to prevent drift in agent-skills.
#
# This is intentionally conservative: fail only on patterns that are always wrong
# (or always confusing) for the canonical stack.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

have_rg=0
if command -v rg >/dev/null 2>&1; then
  have_rg=1
fi

if [[ "$have_rg" != "1" ]]; then
  fail "ripgrep (rg) required to run consistency lint"
fi

# Exclude generated/irrelevant dirs.
RG_BASE=(rg -n -S --hidden --glob '!**/.git/**' --glob '!**/.venv/**' --glob '!**/__pycache__/**' --glob '!**/.beads/**' --glob '!scripts/lint-repo-consistency.sh')

# 1) Do not reintroduce removed components.
if "${RG_BASE[@]}" "\\bagent-mail\\b" . >/dev/null 2>&1; then
  "${RG_BASE[@]}" "\\bagent-mail\\b" . || true
  fail "agent mail must not appear in repo"
fi

if "${RG_BASE[@]}" "\\bhive-dispatch\\b|\\bhive/orchestrator\\b|\\bhive/node\\b" . >/dev/null 2>&1; then
  "${RG_BASE[@]}" "\\bhive-dispatch\\b|\\bhive/orchestrator\\b|\\bhive/node\\b" . || true
  fail "hive orchestrator must not appear in repo"
fi

# 2) Canonical SSH identity (epyc6 user is feng, not fengning).
if "${RG_BASE[@]}" "fengning@epyc6" . >/dev/null 2>&1; then
  "${RG_BASE[@]}" "fengning@epyc6" . || true
  fail "docs/scripts must not reference fengning@epyc6 (use feng@epyc6 or ssh_canonical_vm)"
fi

# 3) Avoid resurrecting dead paths.
if "${RG_BASE[@]}" "~/.agent/skills/dx-doctor/check\\.sh|scripts/cli/dx_doctor\\.sh" . >/dev/null 2>&1; then
  "${RG_BASE[@]}" "~/.agent/skills/dx-doctor/check\\.sh|scripts/cli/dx_doctor\\.sh" . || true
  fail "repo contains references to deprecated dx-doctor paths"
fi

# 4) Do not suggest systemd opencode-server as canonical in documentation.
# (Scripts may retain compatibility fallbacks.)
if "${RG_BASE[@]}" "systemctl\\s+--user\\s+.*opencode-server" docs >/dev/null 2>&1; then
  "${RG_BASE[@]}" "systemctl\\s+--user\\s+.*opencode-server" docs || true
  fail "docs must reference opencode (not opencode-server) for systemd"
fi

# 5) Enforce skills naming convention (SKILL.md).
if find "$ROOT" -type f \( -name 'skill.md' -o -name 'Skill.md' \) | rg -n . >/dev/null 2>&1; then
  find "$ROOT" -type f \( -name 'skill.md' -o -name 'Skill.md' \) | rg -n . || true
  fail "non-standard skill file name found (must be SKILL.md)"
fi

echo "OK: repo consistency checks passed"

