#!/bin/bash
# dx-heartbeat-push.sh
# Syncs local HEARTBEAT.md to stars-end/bd for external GHA monitoring.

set -euo pipefail

HEARTBEAT_SRC="${HOME}/.dx-state/HEARTBEAT.md"
BD_REPO="${HOME}/bd"
TARGET_FILE="${BD_REPO}/status/macmini.heartbeat"

if [[ ! -f "$HEARTBEAT_SRC" ]]; then
    echo "Error: Heartbeat source not found"
    exit 1
fi

mkdir -p "$(dirname "$TARGET_FILE")"
cp "$HEARTBEAT_SRC" "$TARGET_FILE"

cd "$BD_REPO"
git add "status/macmini.heartbeat"

if [[ -n "$(git status --porcelain status/macmini.heartbeat)" ]]; then
    git commit -m "dx: macmini heartbeat push [skip ci]"
    BEADS_SKIP_LINT=1 git push origin master
    echo "Heartbeat pushed successfully"
else
    echo "No changes in heartbeat, but ensuring it exists in remote"
    # Even if no changes, we might want to push an empty commit or touch a file 
    # if we want the GHA to check commit date. 
    # But for now, if the content is the same, no push.
    # Actually, let's update a timestamp file to GUARANTEE a push.
    date -u > "${BD_REPO}/status/macmini.timestamp"
    git add "${BD_REPO}/status/macmini.timestamp"
    git commit -m "dx: macmini heartbeat pulse [skip ci]"
    BEADS_SKIP_LINT=1 git push origin master
fi
