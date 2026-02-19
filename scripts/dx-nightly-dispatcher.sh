#!/usr/bin/env bash
# dx-nightly-dispatcher.sh - Local alternative to Nightly Fleet Dispatcher
# Polls Beads for issues and dispatches to OpenCode VMs.
# MUST BE RUN from macmini.

set -euo pipefail

# Config
REPO_ROOT="/Users/fengning/prime-radiant-ai"
AGENTSKILLS_DIR="/Users/fengning/agent-skills"
VENV_PATH="$REPO_ROOT/backend/.venv"
HOME_DIR="/Users/fengning"

# Setup environment
export PATH="$HOME_DIR/.local/bin:$HOME_DIR/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin"
export BEADS_DIR="$HOME_DIR/bd/.beads"
export DX_DISPATCH_PATH="$AGENTSKILLS_DIR/scripts/dx-dispatch.py"
export PYTHONPATH="$REPO_ROOT"

log() { echo -e "\033[0;34m[nightly-dispatch]\033[0m $*"; }

cd "$REPO_ROOT"

# Ensure mise is loaded
if command -v mise &> /dev/null; then
    eval "$(mise activate bash)"
fi

# Run the dispatcher
log "Starting Nightly Fleet Dispatcher..."
"$VENV_PATH/bin/python" scripts/jules/nightly_dispatch.py "$@"

log "Nightly Fleet Dispatcher run complete."
