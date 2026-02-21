#!/usr/bin/env bash
# dx-nightly-dispatcher.sh - Nightly Fleet Dispatcher using dx-runner
# Polls Beads for P0/P1 issues and dispatches to available providers.
# MUST BE RUN from macmini (DX_CONTROLLER).

set -euo pipefail

# Config
REPO_ROOT="${REPO_ROOT:-$HOME/prime-radiant-ai}"
AGENTSKILLS_DIR="${AGENTSKILLS_DIR:-$HOME/agent-skills}"
VENV_PATH="${VENV_PATH:-$REPO_ROOT/backend/.venv}"
HOME_DIR="${HOME:-/Users/fengning}"

# Setup environment (include /opt/homebrew/bin for bash 5+ required by dx-runner)
export PATH="/opt/homebrew/bin:$HOME_DIR/bin:$HOME_DIR/.local/bin:$HOME_DIR/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin"
export BEADS_DIR="$HOME_DIR/bd/.beads"
export PYTHONPATH="$REPO_ROOT"

# 1Password service account for non-interactive auth (required for cron jobs)
# Read token from file and export as OP_SERVICE_ACCOUNT_TOKEN (op CLI doesn't support _FILE suffix)
OP_TOKEN_FILE="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-$HOME_DIR/.config/systemd/user/op-macmini-token}"
if [[ -f "$OP_TOKEN_FILE" ]]; then
    export OP_SERVICE_ACCOUNT_TOKEN="$(cat "$OP_TOKEN_FILE")"
fi

# dx-runner configuration: find actual location in PATH
if [ -z "${DX_RUNNER_PATH:-}" ]; then
    DX_RUNNER_PATH=$(command -v dx-runner 2>/dev/null || echo "/usr/local/bin/dx-runner")
fi
export DX_RUNNER_PATH

# Slack webhook for alerts (optional)
export SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

log() { echo -e "\033[0;34m[nightly-dispatch]\033[0m $*"; }

cd "$AGENTSKILLS_DIR"

# Ensure mise is loaded
if command -v mise &> /dev/null; then
    eval "$(mise activate bash)"
fi

# Verify dx-runner is available
if ! command -v dx-runner &> /dev/null && [ ! -x "$DX_RUNNER_PATH" ]; then
    log "ERROR: dx-runner not found at $DX_RUNNER_PATH"
    log "Please install dx-runner or set DX_RUNNER_PATH environment variable"
    exit 1
fi

# Verify Python is available
if [ ! -x "$VENV_PATH/bin/python" ] && ! command -v python3 &> /dev/null; then
    log "ERROR: Python not found"
    exit 1
fi

# Use venv python if available, otherwise system python3
if [ -x "$VENV_PATH/bin/python" ]; then
    PYTHON="$VENV_PATH/bin/python"
else
    PYTHON="python3"
fi

# Run the dispatcher
log "Starting Nightly Fleet Dispatcher..."
log "Using dx-runner at: ${DX_RUNNER_PATH}"

"$PYTHON" scripts/nightly_dispatch.py "$@"

log "Nightly Fleet Dispatcher run complete."
