#!/bin/bash
# dx-fleet-qa-validator.sh - Local Fleet QA Validation
# Migrated from GHA (fleet-qa-validator.yml)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-fleet-qa.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting fleet QA validator..."

cd /Users/fengning/prime-radiant-ai
python3 scripts/fleet/qa_validator.py

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fleet QA validation complete"
