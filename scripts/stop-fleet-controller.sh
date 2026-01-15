#!/bin/bash
# Stop Fleet Controller daemon
set -e

PID_FILE="$HOME/.fleet-controller/controller.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping Fleet Controller (PID $PID)..."
        kill "$PID"
        rm -f "$PID_FILE"
        echo "Stopped."
    else
        echo "Controller not running (stale PID file)"
        rm -f "$PID_FILE"
    fi
else
    echo "Controller not running (no PID file)"
fi
