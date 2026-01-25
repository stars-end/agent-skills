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
link "$AGENTS_ROOT/scripts/fleet-dispatch.py" "$BIN_DIR/fleet-dispatch"
link "$AGENTS_ROOT/scripts/worktree-setup.sh" "$BIN_DIR/worktree-setup.sh"
link "$AGENTS_ROOT/scripts/dx-status.sh" "$BIN_DIR/dx-status"
link "$AGENTS_ROOT/scripts/dx-check.sh" "$BIN_DIR/dx-check"

# Fleet visibility + toolchain consistency
link "$AGENTS_ROOT/scripts/dx-fleet-status.sh" "$BIN_DIR/dx-fleet-status"
link "$AGENTS_ROOT/scripts/dx-toolchain.sh" "$BIN_DIR/dx-toolchain"

# Existing tool: run
link "$AGENTS_ROOT/tools/run" "$BIN_DIR/run"

echo "✅ ensured ~/bin tools"
