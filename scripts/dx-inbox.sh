#!/usr/bin/env bash
#
# dx-inbox.sh
#
# V7.8 Founder inbox heartbeat (read-only).
# ONE line when healthy; <=6 lines when unhealthy.
#
# MUST NOT modify git state anywhere.
# Should run fast (<10s).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get hostname for reporting
HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

# Collect health signals
ERRORS=()
DIRTY_STALE_LIST=()
NO_UPSTREAM_LIST=()
NEXT_COMMANDS=()

# Check canonical hygiene via dx-verify-clean
if [[ -x "$HOME/agent-skills/scripts/dx-verify-clean.sh" ]]; then
  if ! "$HOME/agent-skills/scripts/dx-verify-clean.sh" >/dev/null 2>&1; then
    ERRORS+=("canonical_not_clean")
  fi
else
  ERRORS+=("verify_clean_missing")
fi

# Parse dx-status for hygiene exceptions
if [[ -x "$HOME/agent-skills/scripts/dx-status.sh" ]]; then
  STATUS_OUTPUT=$("$HOME/agent-skills/scripts/dx-status.sh" 2>/dev/null || true)

  DIRTY_STALE=$(echo "$STATUS_OUTPUT" | grep "Dirty (Stale):" | head -1 || true)
  NO_UPSTREAM=$(echo "$STATUS_OUTPUT" | grep "No Upstream branches:" | head -1 || true)

  DIRTY_STALE_PATH=$(echo "$DIRTY_STALE" | grep -oE '/tmp/agents/[^[:space:]]+' | head -1 || true)
  NO_UPSTREAM_PATH=$(echo "$NO_UPSTREAM" | grep -oE '/tmp/agents/[^[:space:]]+' | head -1 || true)

  if [[ -n "$DIRTY_STALE" ]]; then
    DIRTY_STALE_COUNT=$(echo "$DIRTY_STALE" | sed 's/.*: \([0-9]*\).*/\1/' || echo "0")
    DIRTY_STALE_COUNT="${DIRTY_STALE_COUNT:-0}"
    if [[ "$DIRTY_STALE_COUNT" -gt 0 ]]; then
      ERRORS+=("dirty_stale=$DIRTY_STALE_COUNT")
      [[ -n "$DIRTY_STALE_PATH" ]] && DIRTY_STALE_LIST+=("$DIRTY_STALE_PATH")
      NEXT_COMMANDS+=("run ~/agent-skills/scripts/dx-janitor.sh --dry-run")
    fi
  fi

  if [[ -n "$NO_UPSTREAM" ]]; then
    NO_UPSTREAM_COUNT=$(echo "$NO_UPSTREAM" | sed 's/.*: \([0-9]*\).*/\1/' || echo "0")
    NO_UPSTREAM_COUNT="${NO_UPSTREAM_COUNT:-0}"
    if [[ "$NO_UPSTREAM_COUNT" -gt 0 ]]; then
      ERRORS+=("no_upstream=$NO_UPSTREAM_COUNT")
      [[ -n "$NO_UPSTREAM_PATH" ]] && NO_UPSTREAM_LIST+=("$NO_UPSTREAM_PATH")
      NEXT_COMMANDS+=("run ~/agent-skills/scripts/dx-janitor.sh --dry-run")
    fi
  fi
fi

# Optional: Check PR inbox via gh (best-effort)
if command -v gh >/dev/null 2>&1; then
  RESCUE_PRS=$(gh pr list --search "rescue" --json url --limit 1 --jq 'length' 2>/dev/null || echo "0")
  if [[ "$RESCUE_PRS" -gt 0 ]]; then
    ERRORS+=("rescue_prs=$RESCUE_PRS")
  fi
fi

# Optional: Beads next via bv (best-effort)
if command -v bv >/dev/null 2>&1; then
  BV_NEXT=$(bv --robot-next 2>/dev/null | head -1 || true)
  if [[ -n "$BV_NEXT" ]]; then
    BEADS_HINT=" | next: $BV_NEXT"
  fi
fi

# Output formatting
if [[ ${#ERRORS[@]} -eq 0 ]]; then
  echo "DX PULSE OK ($HOSTNAME): canonicals clean; worktrees=OK; upstream=OK; PRs=OK${BEADS_HINT:-}"
else
  ERROR_SUMMARY=$(IFS=" " ; echo "${ERRORS[*]}")
  echo "DX PULSE NOT OK ($HOSTNAME): $ERROR_SUMMARY"

  if [[ ${#DIRTY_STALE_LIST[@]} -gt 0 ]]; then
    echo "DirtyStale: ${DIRTY_STALE_LIST[0]}${DIRTY_STALE_COUNT:+ ...(+$((DIRTY_STALE_COUNT-1)))}"
  fi

  if [[ ${#NO_UPSTREAM_LIST[@]} -gt 0 ]]; then
    echo "NoUpstream: ${NO_UPSTREAM_LIST[0]}${NO_UPSTREAM_COUNT:+ ...(+$((NO_UPSTREAM_COUNT-1)))}"
  fi

  if [[ ${#NEXT_COMMANDS[@]} -gt 0 ]]; then
    UNIQUE_COMMANDS=$(printf "%s\n" "${NEXT_COMMANDS[@]}" | sort -u)
    while IFS= read -r cmd; do
      echo "Next: $cmd"
    done <<< "$UNIQUE_COMMANDS"
  fi
fi
