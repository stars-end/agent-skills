#!/usr/bin/env bash
# dx-baseline-sync.sh - Local alternative to GHA Baseline Sync
# Orchestrates baseline regeneration and distribution across the fleet.
#
# IMPORTANT: This script MUST be run from the CANONICAL ~/agent-skills clone,
# not from a worktree. It regenerates the baseline in canonical (which dirties
# tracked files) but then resets to clean state after distribution.
#
# Cron schedule: 0 12 * * * (daily at noon)
#
# Exit codes:
#   0 - Success (all repos synced or no changes needed)
#   1 - Partial failure (some repos failed, see logs)
#   2 - Configuration error (missing tools, canonical repo not found)

set -euo pipefail

# Deterministic PATH for cron execution
export PATH="/usr/local/bin:/opt/homebrew/bin:/Users/fengning/bin:/usr/bin:/bin:$PATH"

# Config - ALWAYS use canonical ~/agent-skills
CANONICAL_REPO="$HOME/agent-skills"
SIBLING_REPOS=("prime-radiant-ai" "affordabot" "llm-common")
DX_WORKTREE="/Users/fengning/bin/dx-worktree"

log() { echo -e "\033[0;34m[baseline-sync]\033[0m $*"; }
error() { echo -e "\033[0;31m[error]\033[0m $*" >&2; }
success() { echo -e "\033[0;32m[success]\033[0m $*"; }

# Pre-flight checks
preflight() {
  # Verify canonical repo exists
  if [[ ! -d "$CANONICAL_REPO/.git" ]]; then
    error "Canonical repo not found at $CANONICAL_REPO"
    exit 2
  fi

  # Verify dx-worktree is available
  if [[ ! -x "$DX_WORKTREE" ]]; then
    if ! command -v dx-worktree >/dev/null 2>&1; then
      error "dx-worktree not found. Please install to ~/bin/dx-worktree"
      exit 2
    fi
    DX_WORKTREE="$(command -v dx-worktree)"
  fi

  # Verify make is available
  if ! command -v make >/dev/null 2>&1; then
    error "make not found in PATH"
    exit 2
  fi
}

# Track failures for proper exit code
FAILED_REPOS=()
SUCCESS_REPOS=()

# 1. Regenerate Baseline in CANONICAL agent-skills
regenerate_baseline() {
  log "Regenerating baseline in canonical agent-skills..."
  cd "$CANONICAL_REPO"

  # Stash any existing changes to avoid conflicts
  if [[ -n "$(git status --porcelain)" ]]; then
    log "Stashing existing changes in canonical..."
    git stash push -m "baseline-sync-pre-regen-$(date +%Y%m%d-%H%M%S)" >/dev/null 2>&1 || true
  fi

  # Run baseline generation
  if ! make publish-baseline >/dev/null 2>&1; then
    error "Baseline generation failed"
    return 1
  fi

  if [[ ! -f "dist/universal-baseline.md" ]]; then
    error "Baseline generation failed: dist/universal-baseline.md not found"
    return 1
  fi

  log "Baseline generated successfully"
  return 0
}

# 2. Sync to a single sibling repo
sync_sibling() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  local wt_id="bot-baseline-sync"
  local wt_path="/tmp/agents/$wt_id/$repo"

  log "Syncing $repo..."

  # Verify sibling repo exists
  if [[ ! -d "$repo_path/.git" ]]; then
    error "$repo: Not found at $repo_path"
    FAILED_REPOS+=("$repo:not_found")
    return 1
  fi

  # Ensure worktree exists for automation
  if [[ ! -d "$wt_path" ]]; then
    log "Creating worktree for $repo at $wt_path..."
    if ! "$DX_WORKTREE" create "$wt_id" "$repo" >/dev/null 2>&1; then
      error "$repo: Failed to create worktree"
      FAILED_REPOS+=("$repo:worktree_failed")
      return 1
    fi
  fi

  # Perform sync in worktree
  (
    cd "$wt_path" || exit 1

    # Ensure clean state
    git fetch origin master >/dev/null 2>&1 || true
    git checkout master >/dev/null 2>&1 || true
    git reset --hard origin/master >/dev/null 2>&1 || true

    # Ensure fragments directory exists
    mkdir -p "fragments"

    # Copy baseline from canonical
    cp "$CANONICAL_REPO/dist/universal-baseline.md" "fragments/universal-baseline.md"

    # Run regeneration if script exists
    if [[ -x "scripts/agents-md-compile.zsh" ]]; then
      log "Regenerating AGENTS.md in $repo..."
      ./scripts/agents-md-compile.zsh >/dev/null 2>&1 || true
    fi

    # Check for changes
    if [[ -n "$(git status --porcelain=v1 AGENTS.md fragments/universal-baseline.md 2>/dev/null)" ]]; then
      log "Drift detected in $repo. Committing and pushing to bot branch..."

      local bot_branch="bot/agent-baseline-sync"
      git checkout -B "$bot_branch" >/dev/null 2>&1 || true
      git add AGENTS.md fragments/universal-baseline.md

      if git commit -m "chore: sync baseline from agent-skills [local-sync]" >/dev/null 2>&1; then
        if git push --force-with-lease origin "$bot_branch" >/dev/null 2>&1; then
          success "Pushed baseline update to $repo branch $bot_branch"
          exit 0
        else
          echo "push_failed" >&3
          exit 1
        fi
      else
        log "$repo: No changes to commit"
        exit 0
      fi
    else
      log "$repo: No changes needed"
      exit 0
    fi
  ) 3>&1

  local result=$?
  if [[ $result -eq 0 ]]; then
    SUCCESS_REPOS+=("$repo")
    return 0
  else
    FAILED_REPOS+=("$repo:sync_failed")
    return 1
  fi
}

# 3. Clean up canonical after sync
cleanup_canonical() {
  cd "$CANONICAL_REPO"

  # Reset the generated files to clean state
  log "Resetting generated files in canonical..."

  # Check out the generated files from HEAD to clean them
  git checkout HEAD -- AGENTS.md dist/universal-baseline.md dist/dx-global-constraints.md 2>/dev/null || true

  # If there's a stash from pre-regen, pop it
  if git stash list | grep -q "baseline-sync-pre-regen"; then
    log "Restoring stashed changes..."
    git stash pop >/dev/null 2>&1 || true
  fi

  # Verify clean state
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    error "WARNING: Canonical still has dirty files after cleanup"
    git status --porcelain
    return 1
  fi

  log "Canonical is clean"
  return 0
}

# Main
main() {
  echo "=== DX Baseline Sync ==="
  echo "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""

  preflight

  # Regenerate baseline
  if ! regenerate_baseline; then
    error "Failed to regenerate baseline - aborting"
    exit 1
  fi

  # Sync to siblings
  for repo in "${SIBLING_REPOS[@]}"; do
    sync_sibling "$repo" || true  # Don't exit on failure, track it
  done

  # Clean up canonical
  cleanup_canonical

  # Summary
  echo ""
  echo "=== Summary ==="
  echo "Succeeded: ${#SUCCESS_REPOS[@]} repos"
  echo "Failed: ${#FAILED_REPOS[@]} repos"

  if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
    echo ""
    echo "Failed repos:"
    for fail in "${FAILED_REPOS[@]}"; do
      echo "  - $fail"
    done
    error "Baseline sync completed with failures"
    exit 1
  fi

  success "Baseline sync complete"
  exit 0
}

main "$@"
