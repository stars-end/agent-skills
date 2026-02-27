#!/bin/bash
# Beads Fleet Sync Script (SSH/rsync based)
# Replaces MinIO mc mirror with direct host-to-host sync
#
# Usage:
#   bd-fleet-sync.sh push   - Push local fleet-remote to all hosts
#   bd-fleet-sync.sh pull   - Pull fleet-remote from source host
#   bd-fleet-sync.sh status - Show sync status

set -e

BEADS_DIR="${BEADS_DIR:-$HOME/bd}"
FLEET_REMOTE="$BEADS_DIR/.beads/fleet-remote"
SOURCE_HOST="epyc12"
HOSTS=("epyc12" "homedesktop-wsl")

push_to_hosts() {
    echo "Pushing fleet-remote to all hosts..."
    for host in "${HOSTS[@]}"; do
        if [[ "$host" != "$(hostname)" ]]; then
            echo "  → $host"
            rsync -az --delete "$FLEET_REMOTE/" "$host:$FLEET_REMOTE/"
        fi
    done
    echo "Push complete."
}

pull_from_source() {
    echo "Pulling fleet-remote from $SOURCE_HOST..."
    rsync -az --delete "$SOURCE_HOST:$FLEET_REMOTE/" "$FLEET_REMOTE/"
    echo "Pull complete."
}

show_status() {
    echo "=== Fleet Sync Status ==="
    echo "Local: $FLEET_REMOTE"
    ls -la "$FLEET_REMOTE" 2>/dev/null | head -5 || echo "  (not found)"
    echo ""
    for host in "${HOSTS[@]}"; do
        echo "Remote ($host):"
        ssh "$host" "ls -la $FLEET_REMOTE 2>/dev/null | head -3" || echo "  (unreachable)"
        echo ""
    done
}

case "${1:-help}" in
    push)
        push_to_hosts
        ;;
    pull)
        pull_from_source
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {push|pull|status}"
        echo ""
        echo "Sync workflow:"
        echo "  1. On source host after mutations:"
        echo "     cd ~/bd/.beads/dolt/beads_bd && dolt push fleet-cloud main"
        echo "     $0 push"
        echo ""
        echo "  2. On target host to sync:"
        echo "     $0 pull"
        echo "     cd ~/bd/.beads/dolt/beads_bd && dolt pull fleet-cloud main --ff-only"
        exit 1
        ;;
esac
