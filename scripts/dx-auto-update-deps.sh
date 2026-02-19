#!/bin/bash
# dx-auto-update-deps.sh - Local Dependency Auto-Update
# Migrated from GHA (auto-update-deps.yml)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-auto-update.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting dependency update..."

cd /Users/fengning/prime-radiant-ai
./scripts/maintenance/update-llm-common.sh

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Dependency update complete"
