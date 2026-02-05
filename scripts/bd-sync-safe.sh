#!/usr/bin/env bash
#
# bd-sync-safe.sh
#
# Deterministic wrapper for Beads sync to keep ~/bd git-clean.
# For use in cron/scheduled jobs.
#
# Usage:
#   bd-sync-safe.sh [--quiet]
#
set -euo pipefail

QUIET="${1:-}"

BEADS_REPO="$HOME/bd"
BEADS_DIR="$HOME/bd/.beads"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

log() {
  if [[ "$QUIET" != "--quiet" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  fi
}

# Check if ~/bd exists
if [[ ! -d "$BEADS_REPO/.git" ]]; then
  log "❌ Beads repo not found: $BEADS_REPO"
  exit 1
fi

log "Starting Beads sync on $HOSTNAME..."

# Ensure BEADS_DIR is set
export BEADS_DIR

# Pull latest from remote
cd "$BEADS_REPO"
log "Pulling latest from remote..."
if ! git pull --rebase; then
  log "❌ git pull --rebase failed"
  exit 1
fi

# Run Beads sync
log "Running bd sync..."
if ! bd sync --no-daemon --quiet; then
  log "⚠️  bd sync returned non-zero (continuing to commit if needed)"
fi

# Check if repo is dirty after sync
if ! git diff-index --quiet HEAD --; then
  log "📝 Repo dirty after sync, committing changes..."

  # Add all changes
  git add -A

  # Commit with deterministic message
  git commit -m "chore(beads): sync $HOSTNAME $TIMESTAMP"

  # Push changes
  log "Pushing changes..."
  if ! git push; then
    log "❌ git push failed - repo may have diverged"
    exit 1
  fi

  log "✅ Sync completed and pushed"
else
  log "✅ Sync completed (no changes)"
fi
