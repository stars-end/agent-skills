#!/usr/bin/env bash
#
# dx-inbox.sh
#
# V7.8 Founder inbox heartbeat (read-only).
# ONE line when healthy; <=6 lines when unhealthy.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

ERRORS=()
NEXT_COMMANDS=()

# Check canonical hygiene
if [[ -x "$HOME/agent-skills/scripts/dx-verify-clean.sh" ]]; then
  if ! "$HOME/agent-skills/scripts/dx-verify-clean.sh" >/dev/null 2>&1; then
    ERRORS+=("canonical_not_clean")
  fi
fi

# Parse dx-status for hygiene exceptions
if [[ -x "$SCRIPT_DIR/dx-status.sh" ]]; then
  STATUS_OUTPUT=$("$SCRIPT_DIR/dx-status.sh" 2>/dev/null || true)

  DIRTY_STALE=$(echo "$STATUS_OUTPUT" | grep "Dirty (Stale):" | grep -oE '[0-9]+' | head -1 || echo "0")
  NO_UPSTREAM_UNMERGED=$(echo "$STATUS_OUTPUT" | grep "No Upstream (Unmerged/Dirty):" | grep -oE '[0-9]+' | head -1 || echo "0")
  NO_UPSTREAM_MERGED=$(echo "$STATUS_OUTPUT" | grep "No Upstream (Merged/Clean):" | grep -oE '[0-9]+' | head -1 || echo "0")

  if [[ "$DIRTY_STALE" -gt 0 ]]; then
    ERRORS+=("dirty_stale=$DIRTY_STALE")
    NEXT_COMMANDS+=("run ~/agent-skills/scripts/dx-janitor.sh --dry-run")
  fi

  if [[ "$NO_UPSTREAM_UNMERGED" -gt 0 ]]; then
    ERRORS+=("no_upstream_unmerged=$NO_UPSTREAM_UNMERGED")
    NEXT_COMMANDS+=("run ~/agent-skills/scripts/dx-janitor.sh --dry-run")
  fi

  if [[ "$NO_UPSTREAM_MERGED" -gt 0 ]]; then
    ERRORS+=("gc_candidates=$NO_UPSTREAM_MERGED")
    NEXT_COMMANDS+=("run ~/agent-skills/scripts/dx-worktree-gc.sh --dry-run")
  fi
fi

# Optional: PR Inbox
if [[ -x "$SCRIPT_DIR/dx-pr-gate.sh" ]]; then
  PR_GATE_OUT=$("$SCRIPT_DIR/dx-pr-gate.sh" | head -1 || true)
  if [[ -n "$PR_GATE_OUT" ]]; then
    if [[ "$PR_GATE_OUT" == *"NOT OK"* ]]; then ERRORS+=("pr_gate=NOT_OK"); fi
    PR_HINT=" | $PR_GATE_OUT"
  fi
fi

# Output
if [[ ${#ERRORS[@]} -eq 0 ]]; then
  echo "DX PULSE OK ($HOSTNAME): canonicals clean; worktrees=OK; upstream=OK${PR_HINT:-}"
else
  ERROR_SUMMARY=$(IFS=" " ; echo "${ERRORS[*]}")
  echo "DX PULSE NOT OK ($HOSTNAME): $ERROR_SUMMARY"
  
  printed_pr_gate=false
  if [[ -n "${PR_HINT:-}" ]]; then
    "$SCRIPT_DIR/dx-pr-gate.sh"
    printed_pr_gate=true
  fi

  # Keep output bounded (<=6 lines total in common failure modes).
  # If we already printed PR gate details, omit "Next:" suggestions here.
  if [[ ${#NEXT_COMMANDS[@]} -gt 0 && "$printed_pr_gate" != true ]]; then
    next=$(printf "%s\n" "${NEXT_COMMANDS[@]}" | sort -u | head -1)
    [[ -n "$next" ]] && echo "Next: $next"
  fi
fi
