#!/bin/bash
# dx-fleet-pr-monitor.sh - Local Fleet PR Auto-Merge Monitor
# Migrated from GHA (fleet-pr-monitor.yml)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-fleet-pr.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting fleet PR monitor..."

cd /Users/fengning/prime-radiant-ai
python3 scripts/fleet/pr_monitor.py

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fleet PR monitor complete"
