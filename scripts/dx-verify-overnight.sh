#!/bin/bash
# dx-verify-overnight.sh - Local "Verify Overnight" wrapper via Railway
# Part of bd-9zil migration.
# Usage: ./dx-verify-overnight.sh [repo-name]

set -euo pipefail

REPO_NAME=${1:-prime-radiant-ai}
REPO_PATH="${HOME}/${REPO_NAME}"

# Setup environment for cron context
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

if [[ ! -d "$REPO_PATH" ]]; then
    echo "❌ Repo path not found: $REPO_PATH"
    exit 1
fi

cd "$REPO_PATH"

# Ensure mise is loaded for python version management
if command -v mise &> /dev/null; then
    eval "$(mise activate bash)"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🌙 Starting Verify Overnight for ${REPO_NAME}..."
echo "🔗 Environment: $(railway status | grep Environment || echo 'unknown')"

# Execute via railway run for secure secret injection and env parity
# This mirrors the GHA execution but runs on dedicated local hardware.
VITE_RAILWAY_ENVIRONMENT_NAME=dev railway run ./scripts/verification/uismoke-overnight.sh
