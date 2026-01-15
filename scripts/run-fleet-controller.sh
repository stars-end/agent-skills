#!/bin/bash
# Fleet Controller Daemon - runs on epyc6
# 
# Usage: ./run-fleet-controller.sh [--once]
#
# This script:
# 1. Sets up environment (slack tokens from .zshenv)
# 2. Runs the Fleet Controller in daemon mode
# 3. Logs to ~/.fleet-controller/controller.log

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$HOME/.fleet-controller"
LOG_FILE="$LOG_DIR/controller.log"
PID_FILE="$LOG_DIR/controller.pid"

# Source environment (for SLACK_MCP tokens)
if [ -f "$HOME/.zshenv" ]; then
    source "$HOME/.zshenv"
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Fleet Controller already running (PID $OLD_PID)"
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

cd "$REPO_ROOT"

echo "Starting Fleet Controller..."
echo "  Log: $LOG_FILE"
echo "  Repo: $REPO_ROOT"

if [ "$1" = "--once" ]; then
    # Run once for testing
    python3 -m lib.fleet.controller --once 2>&1 | tee -a "$LOG_FILE"
elif [ "$1" = "--foreground" ]; then
    # Run in foreground (for debugging)
    echo $$ > "$PID_FILE"
    exec python3 -m lib.fleet.controller 2>&1 | tee -a "$LOG_FILE"
else
    # Run as daemon
    nohup python3 -m lib.fleet.controller >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Started as daemon (PID $(cat "$PID_FILE"))"
    echo "View logs: tail -f $LOG_FILE"
fi
