#!/usr/bin/env bash
#
# Cross-agent SessionStart Hook: DX Bootstrap
#
# Canonical entrypoint for session-start bootstrap across IDEs.
# Keeps logic cross-agent: no agent-specific assumptions; adapters call this.
#
set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/.agent/skills}"
if [[ ! -d "$AGENTS_ROOT" ]]; then
  AGENTS_ROOT="$HOME/agent-skills"
fi

# 0) Canonical hard-stop (prevents wasted work that may be reverted by automation).
# Escape hatch: DX_CANONICAL_ACK=1 (use only to run dx-worktree/exit cleanly).
if [[ -f "$AGENTS_ROOT/scripts/lib/canonical-detect.sh" ]]; then
  # shellcheck disable=SC1090
  source "$AGENTS_ROOT/scripts/lib/canonical-detect.sh"
  if _dx_is_canonical_cwd_fast; then
    if [[ "${DX_CANONICAL_ACK:-0}" != "1" ]]; then
      echo ""
      echo "❌ CANNOT PROCEED: You are in a CANONICAL repository"
      echo ""
      echo "   Path: $(pwd -P)"
      echo ""
      echo "   Canonical clones are automation-owned and MUST stay clean."
      echo "   Create a worktree before doing anything:"
      echo "     dx-worktree create <beads-id> <repo>"
      echo "     cd /tmp/agents/<beads-id>/<repo>"
      echo ""
      echo "   (Escape hatch: set DX_CANONICAL_ACK=1 for this session start)"
      echo ""
      exit 1
    fi
    echo ""
    echo "⚠️  WARNING (DX_CANONICAL_ACK=1): continuing in canonical repo: $(pwd -P)"
    echo ""
  fi
fi

# 1) Best-effort baseline check.
if command -v dx-check >/dev/null 2>&1; then
  dx-check 2>&1 || true
elif [[ -f "$AGENTS_ROOT/scripts/dx-check.sh" ]]; then
  "$AGENTS_ROOT/scripts/dx-check.sh" 2>&1 || true
fi

# 2) Optional stranded work reminder.
if [[ -f "$AGENTS_ROOT/scripts/auto-checkpoint-notify.sh" ]]; then
  "$AGENTS_ROOT/scripts/auto-checkpoint-notify.sh" 2>&1 || true
fi

# 3) Optional coordinator checks.
if [[ "${DX_BOOTSTRAP_COORDINATOR:-0}" == "1" ]]; then
  if command -v dx-doctor >/dev/null 2>&1; then
    dx-doctor 2>&1 || true
  elif [[ -f "$AGENTS_ROOT/scripts/dx-doctor.sh" ]]; then
    "$AGENTS_ROOT/scripts/dx-doctor.sh" 2>&1 || true
  fi
fi

exit 0
