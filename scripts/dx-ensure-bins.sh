#!/usr/bin/env bash
# dx-ensure-bins.sh
# Idempotently ensure canonical agent-skills executables are available in ~/bin.

set -euo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"

mkdir -p "$BIN_DIR"

# Ensure PATH for non-interactive shells (no secrets).
"$AGENTS_ROOT/scripts/ensure-shell-path.sh" >/dev/null 2>&1 || true

link() {
  local src="$1"
  local dest="$2"
  if [[ -e "$src" ]]; then
    ln -sf "$src" "$dest"
    chmod +x "$src" 2>/dev/null || true
  fi
}

# Core control-plane CLIs
# dx-runner is the canonical dispatch surface (bd-xga8.14.8)
link "$AGENTS_ROOT/scripts/dx-runner" "$BIN_DIR/dx-runner"
# dx-batch is the orchestration plane over dx-runner (bd-cbsb.25)
link "$AGENTS_ROOT/scripts/dx-batch" "$BIN_DIR/dx-batch"
# dx-wave is the profile-first operator wrapper for safe dispatch
link "$AGENTS_ROOT/scripts/dx-wave" "$BIN_DIR/dx-wave"
# dx-loop is the PR-aware orchestration operator surface
link "$AGENTS_ROOT/scripts/dx-loop" "$BIN_DIR/dx-loop"
# dx-review is the minimal multi-provider review quorum wrapper
link "$AGENTS_ROOT/scripts/dx-review" "$BIN_DIR/dx-review"
# dx-research is the source-backed research artifact wrapper
link "$AGENTS_ROOT/scripts/dx-research" "$BIN_DIR/dx-research"
# dx-repo-memory-check enforces repo-owned brownfield map freshness.
link "$AGENTS_ROOT/scripts/dx-repo-memory-check" "$BIN_DIR/dx-repo-memory-check"
# dx-dispatch shell shim is canonical compatibility entrypoint.
# Fall back to the legacy Python implementation only if shell shim is missing.
if [[ -x "$AGENTS_ROOT/scripts/dx-dispatch" ]]; then
  link "$AGENTS_ROOT/scripts/dx-dispatch" "$BIN_DIR/dx-dispatch"
else
  link "$AGENTS_ROOT/scripts/dx-dispatch.py" "$BIN_DIR/dx-dispatch"
fi
# fleet-dispatch.py consolidated into dx-dispatch.py (see archive/dispatch-legacy/)
# link "$AGENTS_ROOT/scripts/fleet-dispatch.py" "$BIN_DIR/fleet-dispatch"
link "$AGENTS_ROOT/scripts/worktree-setup.sh" "$BIN_DIR/worktree-setup.sh"
link "$AGENTS_ROOT/scripts/dx-worktree.sh" "$BIN_DIR/dx-worktree"
link "$AGENTS_ROOT/scripts/dx-status.sh" "$BIN_DIR/dx-status"
link "$AGENTS_ROOT/scripts/dx-check.sh" "$BIN_DIR/dx-check"
link "$AGENTS_ROOT/scripts/dx-doctor.sh" "$BIN_DIR/dx-doctor"
link "$AGENTS_ROOT/scripts/dx-bootstrap-auth.sh" "$BIN_DIR/dx-bootstrap-auth"
link "$AGENTS_ROOT/scripts/dx-op-auth-status.sh" "$BIN_DIR/dx-op-auth-status"

# Fleet visibility + toolchain consistency
link "$AGENTS_ROOT/scripts/dx-fleet-status.sh" "$BIN_DIR/dx-fleet-status"
link "$AGENTS_ROOT/scripts/dx-toolchain.sh" "$BIN_DIR/dx-toolchain"
link "$AGENTS_ROOT/scripts/dx-triage.sh" "$BIN_DIR/dx-triage"
link "$AGENTS_ROOT/scripts/dx-janitor.sh" "$BIN_DIR/dx-janitor"
link "$AGENTS_ROOT/scripts/dx-sweeper.sh" "$BIN_DIR/dx-sweeper"
link "$AGENTS_ROOT/scripts/dx-verify-clean.sh" "$BIN_DIR/dx-verify-clean"
link "$AGENTS_ROOT/scripts/dx-worktree-gc.sh" "$BIN_DIR/dx-worktree-gc"
link "$AGENTS_ROOT/scripts/dx-delegate.sh" "$BIN_DIR/dx-delegate"

# Beads helpers (used across repos)
link "$AGENTS_ROOT/scripts/bdx" "$BIN_DIR/bdx"
link "$AGENTS_ROOT/scripts/bdx-remote" "$BIN_DIR/bdx-remote"
link "$AGENTS_ROOT/scripts/beads-dolt" "$BIN_DIR/beads-dolt"
link "$AGENTS_ROOT/scripts/bd-context" "$BIN_DIR/bd-context"
link "$AGENTS_ROOT/scripts/bd-link-pr" "$BIN_DIR/bd-link-pr"
# Legacy sync wrapper is deprecated in canonical Dolt hub-spoke mode.
# Keep available for rollback-only/manual workflows.
link "$AGENTS_ROOT/scripts/bd-sync-safe.sh" "$BIN_DIR/bd-sync-safe"

# Skills plane helpers
link "$AGENTS_ROOT/scripts/dx-agents-skills-install.sh" "$BIN_DIR/dx-agents-skills-install"
link "$AGENTS_ROOT/scripts/dx-codex-skills-install.sh" "$BIN_DIR/dx-codex-skills-install"
link "$AGENTS_ROOT/extended/cc-glm/scripts/cc-glm-headless.sh" "$BIN_DIR/cc-glm-headless"

# Existing tool: run
link "$AGENTS_ROOT/tools/run" "$BIN_DIR/run"

echo "✅ ensured ~/bin tools"
