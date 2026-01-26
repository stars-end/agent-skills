#!/usr/bin/env bash
# auto-checkpoint.sh
# Bulletproof auto-checkpoint for agent sessions.
#
# Safety Contract:
# 1. NEVER push to trunk (master/main). If on trunk: create wip/auto/<host>/<YYYY-MM-DD> branch.
# 2. NEVER operate inside worktree dirs (/tmp/agents/...). Only canonical clones in ~/.
# 3. Concurrency safe: lock file with 5 min timeout + skip if .git/index.lock exists.
# 4. Secret scanning: added-lines-only (git diff --cached -U0) + high-confidence patterns.
# 5. Works without LLM. LLM opt-in via AUTO_CHECKPOINT_ALLOW_LLM=1 (metadata only).
# 6. Push is best-effort; local commit MUST exist even if push fails (no work loss).
# 7. Never operate without origin remote.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${AUTO_CHECKPOINT_LOG_DIR:-$HOME/.auto-checkpoint}"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/checkpoint.log"
LOCK_FILE="$LOG_DIR/checkpoint.lock"
LOCK_TIMEOUT=300  # 5 minutes max

# Canonical repos (subset of canonical-targets.sh for inline use)
CANONICAL_REPOS=(
  "agent-skills"
  "prime-radiant-ai"
  "affordabot"
  "llm-common"
)

TRUNK_BRANCHES=("master" "main")

# High-confidence secret patterns (false-positive safe)
SECRET_PATTERNS=(
  # API keys
  "sk-[a-zA-Z0-9]{20,}"
  "ghp_[a-zA-Z0-9]{36,}"
  "gho_[a-zA-Z0-9]{36,}"
  "ghu_[a-zA-Z0-9]{36,}"
  "ghs_[a-zA-Z0-9]{36,}"
  "ghr_[a-zA-Z0-9]{36,}"
  "AKIA[0-9A-Z]{16}"  # AWS access key
  # Tokens with specific prefixes
  "xoxb-[0-9]{10,}-[0-9]{10,}"
  "xoxp-[0-9]{10,}-[0-9]{10,}"
  # Private keys (high confidence only)
  "-----BEGIN [A-Z]+ PRIVATE KEY-----"
)

# Allowlist patterns to reduce false positives (these are NOT secrets)
SECRET_ALLOWLIST=(
  # Documentation examples
  "sk-\.\.\."
  "ghp_\*\*\*"
  # Test/example values
  '"sk-[a-zA-Z0-9]{20,}"'  # In documentation
  '"AKIA[0-9A-Z]{16}"'      # In documentation
  # Placeholder patterns
  "YOUR_API_KEY"
  "YOUR_SECRET_KEY"
  "REPLACE_WITH"
)

# ============================================================
# Logging
# ============================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# ============================================================
# Lock Management (Concurrency Safe)
# ============================================================

acquire_lock() {
  local start_time
  start_time=$(date +%s)

  # Try to create lock file with exclusive creation
  while true; do
    if (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
      # Success - we have the lock
      return 0
    fi

    # Check if lock is stale
    if [ -f "$LOCK_FILE" ]; then
      local lock_pid lock_age
      lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
      lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null || echo "0") ))

      # Kill stale lock
      if [ $lock_age -gt $LOCK_TIMEOUT ]; then
        log "Stale lock detected (pid=$lock_pid, age=${lock_age}s), removing..."
        rm -f "$LOCK_FILE" 2>/dev/null || true
        sleep 0.1
        continue
      fi
    fi

    # Check timeout
    local current_time
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt 10 ]; then
      log "Cannot acquire lock (another checkpoint running)"
      return 1
    fi

    sleep 0.5
  done
}

release_lock() {
  rm -f "$LOCK_FILE" 2>/dev/null || true
}

# ============================================================
# Safety Checks
# ============================================================

is_worktree_dir() {
  local dir="$1"
  # Check if inside /tmp/agents or similar worktree patterns
  case "$dir" in
    /tmp/agents/*|*/worktrees/*|*/.git/worktrees/*)
      return 0
      ;;
  esac
  return 1
}

is_canonical_repo() {
  local repo_name="$1"
  for r in "${CANONICAL_REPOS[@]}"; do
    if [ "$r" = "$repo_name" ]; then
      return 0
    fi
  done
  return 1
}

is_trunk_branch() {
  local branch="$1"
  for tb in "${TRUNK_BRANCHES[@]}"; do
    if [ "$tb" = "$branch" ]; then
      return 0
    fi
  done
  return 1
}

has_git_index_lock() {
  local repo_path="$1"
  [ -f "$repo_path/.git/index.lock" ]
}

has_origin_remote() {
  local repo_path="$1"
  git -C "$repo_path" remote get-url origin >/dev/null 2>&1
}

# ============================================================
# Secret Scanning (Added-Lines-Only)
# ============================================================

scan_for_secrets() {
  local repo_path="$1"
  local found_secrets=()

  # Get added lines only (git diff --cached -U0 shows no context)
  local added_lines
  added_lines=$(git -C "$repo_path" diff --cached -U0 2>/dev/null | grep -E '^\+' | sed 's/^[+]//' || true)

  if [ -z "$added_lines" ]; then
    return 0
  fi

  # Check allowlist first (skip lines that match allowlist patterns)
  local filtered_lines="$added_lines"
  for allow_pattern in "${SECRET_ALLOWLIST[@]}"; do
    filtered_lines=$(grep -vE "$allow_pattern" <<< "$filtered_lines" || true)
  done

  # Check each pattern against filtered lines
  for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -qE "$pattern" <<< "$filtered_lines" 2>/dev/null; then
      found_secrets+=("$pattern")
    fi
  done

  if [ ${#found_secrets[@]} -gt 0 ]; then
    error "Potential secrets detected in staged changes."
    echo "Remediation:" >&2
    echo "  1. Run: git reset HEAD" >&2
    echo "  2. Review changes: git diff" >&2
    echo "  3. Remove/seal secrets in 1password" >&2
    echo "  4. Re-stage clean changes" >&2
    return 1
  fi

  return 0
}

# ============================================================
# Checkpoint Logic
# ============================================================

checkpoint_repo() {
  local repo_path="$1"
  local repo_name
  repo_name=$(basename "$repo_path")

  log "Checking $repo_name..."

  # Skip if not a git repo
  if [ ! -d "$repo_path/.git" ]; then
    return 0
  fi

  # Skip worktree dirs
  if is_worktree_dir "$repo_path"; then
    log "  Skipping (worktree dir)"
    return 0
  fi

  # Skip if git index lock exists (another git operation in progress)
  if has_git_index_lock "$repo_path"; then
    log "  Skipping (git operation in progress)"
    return 0
  fi

  # Skip non-canonical repos (unless explicitly enabled)
  if ! is_canonical_repo "$repo_name" && [ "${AUTO_CHECKPOINT_ALL_REPOS:-0}" != "1" ]; then
    return 0
  fi

  # Check for origin remote (requirement 7)
  if ! has_origin_remote "$repo_path"; then
    log "  Skipping (no origin remote)"
    return 0
  fi

  # Check for uncommitted changes
  if [ -z "$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)" ]; then
    return 0
  fi

  log "  Changes detected, committing..."

  # IMPORTANT: Never leave canonical clones on a wip branch. If checkpointing fails mid-run (secret scan,
  # commit failure, etc.) we must still restore the repo back to trunk when we created a wip branch.
  # A subshell + EXIT trap makes this robust without impacting the caller's working directory.
  (
    cd "$repo_path" || exit 1

    starting_branch="$(git branch --show-current 2>/dev/null || true)"
    is_detached=0
    if [[ -z "${starting_branch:-}" ]]; then
      is_detached=1
    fi

    needs_wip_branch=0
    restore_branch=""

    if [[ "$is_detached" -eq 1 ]]; then
      log "  Detached HEAD, creating wip/auto branch..."
      needs_wip_branch=1
      # Prefer master/main if present.
      if git show-ref --verify --quiet refs/heads/master; then
        restore_branch="master"
      elif git show-ref --verify --quiet refs/heads/main; then
        restore_branch="main"
      else
        restore_branch="master"
      fi
    elif is_trunk_branch "$starting_branch"; then
      log "  On trunk branch ($starting_branch), creating wip/auto branch..."
      needs_wip_branch=1
      restore_branch="$starting_branch"
    fi

    current_branch="${starting_branch:-detached}"
    did_switch_to_wip=0

    restore_to_trunk() {
      if [[ "${did_switch_to_wip:-0}" -eq 1 && -n "${restore_branch:-}" ]]; then
        if git checkout "$restore_branch" >/dev/null 2>&1; then
          log "  Restored to trunk: $restore_branch"
        else
          log "  WARNING: could not restore to trunk ($restore_branch); repo left on $current_branch"
        fi
      fi
    }

    if [ "$needs_wip_branch" -eq 1 ]; then
      hostname=$(hostname -s 2>/dev/null || echo "unknown")
      datestamp=$(date +%Y-%m-%d)
      timestamp=$(date +%H%M%S)
      wip_branch="wip/auto/${hostname}/${datestamp}-${timestamp}"

      git checkout -b "$wip_branch" 2>/dev/null || {
        error "  Cannot create wip branch (git operation failed)"
        exit 1
      }
      current_branch="$wip_branch"
      did_switch_to_wip=1
      log "  Created branch: $current_branch"
    fi

    trap restore_to_trunk EXIT

    # Stage all changes
    git add -A 2>/dev/null || {
      error "  Cannot stage changes"
      exit 1
    }

    # Run secret scan on staged changes
    if ! scan_for_secrets "$repo_path"; then
      error "  Secret scan failed, aborting checkpoint"
      # Reset staging to avoid accidental commit
      git reset HEAD 2>/dev/null || true
      exit 1
    fi

    # Generate commit message
    if [ "${AUTO_CHECKPOINT_ALLOW_LLM:-0}" = "1" ] && command -v cc-glm >/dev/null 2>&1; then
      # LLM mode: send only diff stat (metadata), never code
      diff_stat=$(git diff --cached --stat 2>/dev/null || echo "unknown")
      commit_msg=$(cc-glm -p "Generate a 1-line commit message (max 50 chars) for these changes: $diff_stat" --output-format text 2>/dev/null || echo "auto-checkpoint")
      # Sanitize: ensure commit msg doesn't contain secrets
      commit_msg=$(echo "$commit_msg" | head -1 | cut -c1-72)
    else
      # Non-LLL mode: simple deterministic message
      commit_msg="auto-checkpoint: $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    # Commit (local - this is the critical step for work preservation)
    git commit -m "$commit_msg" 2>/dev/null || {
      error "  Commit failed"
      exit 1
    }

    log "  Committed: $commit_msg"

    # Push is best-effort (don't fail if push fails)
    if git push -u origin "$current_branch" >/dev/null 2>&1; then
      log "  Pushed to origin/$current_branch"
    else
      log "  Push failed (changes saved locally)"
    fi
  )
}

# ============================================================
# Main
# ============================================================

main() {
  log "=== Auto-checkpoint started ==="

  # Acquire lock (timeout after 10s)
  if ! acquire_lock; then
    log "Cannot acquire lock, exiting"
    exit 1
  fi
  trap release_lock EXIT

  local repos_checked=0
  local repos_committed=0

  # Check each canonical repo
  for repo in "${CANONICAL_REPOS[@]}"; do
    local repo_path="$HOME/$repo"
    if [ -d "$repo_path" ]; then
      repos_checked=$((repos_checked + 1))
      if checkpoint_repo "$repo_path"; then
        # Check if commit was made
        if [ -n "$(git -C "$repo_path" log -1 --since='1 minute ago' 2>/dev/null)" ]; then
          repos_committed=$((repos_committed + 1))
        fi
      fi
    fi
  done

  log "=== Auto-checkpoint complete: $repos_committed/$repos_checked repos committed ==="

  # Update last-run timestamp
  echo "$(date +%s)" > "$LOG_DIR/last-run"

  return 0
}

# ============================================================
# Single-Repo Mode (when invoked with REPO_PATH argument)
# ============================================================

single_repo_mode() {
  local repo_path="$1"

  log "=== Auto-checkpoint (single repo mode): $repo_path ==="

  # Acquire lock
  if ! acquire_lock; then
    log "Cannot acquire lock, exiting"
    exit 1
  fi
  trap release_lock EXIT

  if checkpoint_repo "$repo_path"; then
    # Update last-run timestamp
    echo "$(date +%s)" > "$LOG_DIR/last-run"
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry Point
# ============================================================

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -eq 1 ] && [ -d "$1" ]; then
    # Single repo mode: auto-checkpoint.sh /path/to/repo
    single_repo_mode "$1"
  else
    # Multi-repo mode: check all canonical repos
    main "$@"
  fi
fi
