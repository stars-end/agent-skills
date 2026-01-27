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
link "$AGENTS_ROOT/scripts/dx-dispatch.py" "$BIN_DIR/dx-dispatch"
# fleet-dispatch.py consolidated into dx-dispatch.py (see archive/dispatch-legacy/)
# link "$AGENTS_ROOT/scripts/fleet-dispatch.py" "$BIN_DIR/fleet-dispatch"
link "$AGENTS_ROOT/scripts/worktree-setup.sh" "$BIN_DIR/worktree-setup.sh"
link "$AGENTS_ROOT/scripts/dx-worktree.sh" "$BIN_DIR/dx-worktree"
link "$AGENTS_ROOT/scripts/dx-status.sh" "$BIN_DIR/dx-status"
link "$AGENTS_ROOT/scripts/dx-check.sh" "$BIN_DIR/dx-check"
link "$AGENTS_ROOT/scripts/dx-doctor.sh" "$BIN_DIR/dx-doctor"

# Fleet visibility + toolchain consistency
link "$AGENTS_ROOT/scripts/dx-fleet-status.sh" "$BIN_DIR/dx-fleet-status"
link "$AGENTS_ROOT/scripts/dx-toolchain.sh" "$BIN_DIR/dx-toolchain"
link "$AGENTS_ROOT/scripts/dx-triage.sh" "$BIN_DIR/dx-triage"

# Beads helpers (used across repos)
link "$AGENTS_ROOT/scripts/bd-context" "$BIN_DIR/bd-context"
link "$AGENTS_ROOT/scripts/bd-link-pr" "$BIN_DIR/bd-link-pr"

# Existing tool: run
link "$AGENTS_ROOT/tools/run" "$BIN_DIR/run"

# Auto-checkpoint (work preservation)
link "$AGENTS_ROOT/scripts/auto-checkpoint.sh" "$BIN_DIR/auto-checkpoint"
link "$AGENTS_ROOT/scripts/auto-checkpoint-install.sh" "$BIN_DIR/auto-checkpoint-install"

echo "✅ ensured ~/bin tools"
