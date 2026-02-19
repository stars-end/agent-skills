#!/usr/bin/env bash
# Macmini Heartbeat Script for Dead-Man's Switch
# Updates status/macmini.timestamp in bd repo and pushes to GitHub

set -euo pipefail

BD_REPO="$HOME/bd"
HEARTBEAT_FILE="$BD_REPO/status/macmini.timestamp"

# Ensure bd repo exists
if [[ ! -d "$BD_REPO" ]]; then
    echo "ERROR: bd repo not found at $BD_REPO"
    exit 1
fi

# Create status directory if needed
mkdir -p "$BD_REPO/status"

# Write current timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$TIMESTAMP" > "$HEARTBEAT_FILE"

# Commit and push
cd "$BD_REPO"
git add status/macmini.timestamp
git commit -m "chore: heartbeat $TIMESTAMP"
git push origin master

echo "Heartbeat updated: $TIMESTAMP"
