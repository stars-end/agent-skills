#!/usr/bin/env bash
#
# bd-sync-safe.sh
#
# Deterministic wrapper for Beads sync to keep ~/bd git-clean.
# Multi-writer safe with host-local locking and retry logic.
#
# Usage:
#   bd-sync-safe.sh [--quiet]
#
set -euo pipefail

QUIET="${1:-}"
LOG_FILE="$HOME/logs/dx/bd-sync.log"
LOCK_DIR="$HOME/.dx-state/locks/bd-sync.lock"
BEADS_REPO="$HOME/bd"
MAX_LOCK_WAIT_SECONDS=120
MAX_RETRIES=3

# Ensure environment
export BEADS_DIR="${BEADS_DIR:-$HOME/bd/.beads}"
# Ensure Beads repo-id mismatch is ignored for centralized DB operations (bd-5wys)
export BEADS_IGNORE_REPO_MISMATCH=1

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$LOCK_DIR")"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $(hostname -s) $$: $1"
    if [[ "$QUIET" != "--quiet" ]]; then
        echo "$msg"
    fi
    echo "$msg" >> "$LOG_FILE"
}

cleanup() {
    if [[ -d "$LOCK_DIR" ]]; then
        rmdir "$LOCK_DIR"
    fi
}

trap cleanup EXIT

# 1. Host-local lock
WAIT_START=$(date +%s)
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - WAIT_START))
    if [[ $ELAPSED -ge $MAX_LOCK_WAIT_SECONDS ]]; then
        log "❌ Timeout waiting for lock: $LOCK_DIR (waited ${ELAPSED}s)"
        exit 1
    fi
    sleep 2
done

log "Starting Beads sync on $(hostname -s)..."

# Ensure ~/bd exists
if [[ ! -d "$BEADS_REPO/.git" ]]; then
    log "❌ Beads repo not found: $BEADS_REPO"
    exit 1
fi

cd "$BEADS_REPO"

# Helper for jitter backoff
backoff() {
    local retry=$1
    local delay=$(( (retry * 5) + (RANDOM % 10) ))
    log "Waiting ${delay}s before retry..."
    sleep "$delay"
}

# 2. Safe sync loop with retry
attempt=0
while [[ $attempt -le $MAX_RETRIES ]]; do
    ((attempt += 1))
    log "Sync attempt $attempt/$MAX_RETRIES..."

    # Pull/Rebase
    log "Fetching and pulling latest changes..."
    git fetch origin --prune
    if ! git pull --rebase --autostash; then
        log "⚠️ git pull --rebase failed, retrying..."
        backoff "$attempt"
        continue
    fi

    # Run bd sync
    log "Running bd sync..."
    # bd sync may return non-zero if there are no changes or other minor issues,
    # but we want to ensure issues.jsonl is updated.
    if ! bd sync --no-daemon --quiet; then
        log "⚠️ bd sync returned non-zero (continuing to check for dirty state)"
    fi

    # Check if dirty and commit
    if ! git diff-index --quiet HEAD --; then
        log "📝 Repo dirty after sync, committing changes..."
        git add -A
        if ! git diff --cached --quiet; then
            git commit -m "chore(beads): sync $(hostname -s) $(date +"%Y%m%d-%H%M%S")"
        fi
    fi

    # Verify porcelain is empty before push
    if [[ -n "$(git status --porcelain)" ]]; then
        log "❌ git status --porcelain is NOT empty. Manually resolving or failing."
        git status --porcelain >> "$LOG_FILE"
        # If there are still untracked files, we might want to fail or add them.
        # For now, let's fail to avoid messy pushes.
        exit 1
    fi

    # Push
    log "Pushing changes..."
    if git push; then
        log "✅ Sync successful"
        exit 0
    else
        log "⚠️ git push failed (non-fast-forward or network), retrying..."
        backoff "$attempt"
        continue
    fi
done

log "❌ Failed to sync Beads after $MAX_RETRIES attempts"
exit 1