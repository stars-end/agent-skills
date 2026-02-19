#!/bin/bash
# dx-fleet-health-monitor.sh - Local Fleet Health Maintenance
# Migrated from GHA (fleet-health-monitor.yml)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-fleet-health.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting fleet health check..."

cd /Users/fengning/prime-radiant-ai
python3 scripts/fleet/health_monitor.py --heal

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fleet health check complete"
