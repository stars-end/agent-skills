#!/bin/bash
# canonical-sync.sh - Daily sync of canonical repos to origin/master (safety net)
#
# Safety model (V5/V6):
# - Canonical clones should stay clean + on trunk for planning/reads.
# - If a canonical clone is dirty or on the wrong branch, preserve work first via auto-checkpoint.
# - Then fast-forward/reset to origin/trunk.
#
# IMPORTANT: This script should be safe to run unattended.
# It MUST NOT silently destroy uncommitted work.

set -euo pipefail

REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
LOG_PREFIX="[canonical-sync $(date +'%Y-%m-%d %H:%M:%S')]"

SYNCED=0
SKIPPED=0

ensure_clean_or_checkpoint() {
  local repo_path="$1"
  local repo_name
  repo_name=$(basename -- "$repo_path")

  local current_branch dirty
  current_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "")
  dirty=$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || echo "")

  if [[ -n "$dirty" || "$current_branch" != "master" ]]; then
    echo "$LOG_PREFIX $repo_name: dirty or off-trunk (branch=$current_branch). Running auto-checkpoint..."
    if command -v auto-checkpoint >/dev/null 2>&1; then
      # Best-effort. If checkpoint fails, do NOT proceed with destructive sync.
      if ! auto-checkpoint "$repo_path" >/dev/null 2>&1; then
        echo "$LOG_PREFIX $repo_name: auto-checkpoint failed; skipping sync to avoid data loss"
        return 1
      fi
    else
      echo "$LOG_PREFIX $repo_name: auto-checkpoint not installed; skipping sync to avoid data loss"
      return 1
    fi
  fi

  # Re-check cleanliness after checkpoint
  dirty=$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || echo "")
  current_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "")
  if [[ -n "$dirty" || "$current_branch" != "master" ]]; then
    echo "$LOG_PREFIX $repo_name: still dirty or off-trunk after checkpoint; skipping"
    return 1
  fi

  return 0
}

for repo in "${REPOS[@]}"; do
  repo_path="$HOME/$repo"
  cd "$repo_path" 2>/dev/null || continue

  # Skip if this is a worktree
  GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
  if [[ "$GIT_DIR" =~ worktrees ]]; then
    continue
  fi

  # Skip if git operation in progress
  if [[ -f .git/index.lock ]]; then
    echo "$LOG_PREFIX $repo: Skipped (git operation in progress)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if ! ensure_clean_or_checkpoint "$repo_path"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Fetch from origin
  if ! git fetch origin --prune --quiet 2>/dev/null; then
    echo "$LOG_PREFIX $repo: Failed to fetch (network issue?)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Ensure on master
  if ! git checkout -f master >/dev/null 2>&1; then
    echo "$LOG_PREFIX $repo: Failed to checkout master"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Reset to origin/master (canonical safety net)
  if ! git reset --hard origin/master >/dev/null 2>&1; then
    echo "$LOG_PREFIX $repo: Failed to reset to origin/master"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Keep canonical clones clean without nuking ignored caches.
  git clean -fd >/dev/null 2>&1 || true

  # Enforce V5 External Beads
  if [[ -d ".beads" ]]; then
    echo "$LOG_PREFIX $repo: Removing legacy .beads/ directory"
    rm -rf .beads
  fi

  echo "$LOG_PREFIX $repo: ✅ Synced to origin/master"
  SYNCED=$((SYNCED + 1))
 done

echo "$LOG_PREFIX Complete: $SYNCED synced, $SKIPPED skipped"

# Alert if all syncs failed
if [[ $SYNCED -eq 0 && $SKIPPED -gt 0 ]]; then
  echo "🚨 SYNC FAILED: 0 repos synced" | tee "$HOME/logs/SYNC_ALERT"
  exit 1
fi

exit 0
