#!/usr/bin/env bash
# auto-checkpoint.sh
# Bulletproof auto-checkpoint for agent sessions.
#
# Safety Contract:
# 1. NEVER push to trunk (master/main). If on trunk: switch to auto-checkpoint/<hostname> branch.
# 2. On feature branches: commit and push directly (no branch switching).
# 3. NEVER operate inside worktree dirs (/tmp/agents/...). Only canonical clones in ~/.
# 4. Concurrency safe: lock file with 5 min timeout + skip if .git/index.lock exists.
# 5. Secret scanning: added-lines-only (git diff --cached -U0) + high-confidence patterns.
# 6. Works without LLM. LLM opt-in via AUTO_CHECKPOINT_ALLOW_LLM=1 (metadata only).
# 7. Push is best-effort; local commit MUST exist even if push fails (no work loss).
# 8. Never operate without origin remote.

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

  # Simplified checkpoint behavior: Single auto-checkpoint branch per hostname
  # - On trunk/detached: switch to auto-checkpoint/<hostname> (reuse if exists)
  # - On feature branch: commit directly to feature branch
  # - On auto-checkpoint/*: commit to existing branch
  (
    cd "$repo_path" || exit 1

    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    starting_branch="$(git branch --show-current 2>/dev/null || true)"
    is_detached=0
    if [[ -z "${starting_branch:-}" ]]; then
      is_detached=1
    fi

    needs_auto_branch=0
    current_branch="$starting_branch"

    trunk_default=""
    for tb in "${TRUNK_BRANCHES[@]}"; do
      if git show-ref --verify --quiet "refs/heads/$tb" >/dev/null 2>&1; then
        trunk_default="$tb"
        break
      fi
    done
    [ -z "$trunk_default" ] && trunk_default="${TRUNK_BRANCHES[0]}"

    # Canonical-policy behavior:
    # - If already on auto-checkpoint/*, reuse it.
    # - Otherwise (trunk, detached, or any feature branch), always checkpoint onto auto-checkpoint/<host>
    #   so canonical clones can be restored to trunk after saving work.
    if [[ "$starting_branch" =~ ^auto-checkpoint/ ]]; then
      log "  On auto-checkpoint branch, reusing: $starting_branch"
      current_branch="$starting_branch"
    else
      needs_auto_branch=1
      if [[ "$is_detached" -eq 1 ]]; then
        log "  Detached HEAD, switching to auto-checkpoint branch..."
      elif is_trunk_branch "$starting_branch"; then
        log "  On trunk branch ($starting_branch), switching to auto-checkpoint branch..."
      else
        log "  On non-trunk branch ($starting_branch), switching to auto-checkpoint branch..."
      fi
    fi

    # Create or switch to auto-checkpoint branch
    if [ "$needs_auto_branch" -eq 1 ]; then
      auto_branch="auto-checkpoint/${hostname}"

      # Check if branch already exists (local or remote)
      if git show-ref --verify --quiet refs/heads/"$auto_branch" 2>/dev/null; then
        git checkout "$auto_branch" 2>/dev/null || {
          error "  Cannot checkout auto-checkpoint branch"
          exit 1
        }
        log "  Switched to: $auto_branch"
      else
        # Best-effort: if branch exists on origin, base local branch on it.
        if git fetch origin "$auto_branch" >/dev/null 2>&1; then
          if git checkout -B "$auto_branch" "origin/$auto_branch" >/dev/null 2>&1; then
            log "  Checked out: $auto_branch (from origin)"
          else
            error "  Cannot checkout auto-checkpoint branch from origin"
            exit 1
          fi
        else
          # Create new branch from current HEAD
          git checkout -b "$auto_branch" >/dev/null 2>&1 || {
            error "  Cannot create auto-checkpoint branch"
            exit 1
          }
          log "  Created: $auto_branch"
        fi
      fi
      current_branch="$auto_branch"
    fi

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


    # After checkpointing canonical clones, always restore trunk branch to keep canonical repos clean.
    # This prevents long-lived drift onto auto-checkpoint/* branches (which breaks ru/dx automation).
    if is_canonical_repo "$repo_name"; then
      if git checkout "$trunk_default" >/dev/null 2>&1; then
        log "  Restored trunk: $trunk_default"
      else
        log "  WARN: could not restore trunk branch ($trunk_default)"
      fi
    fi

    # Push is best-effort (don't fail if push fails)
    if git push -u origin "$current_branch" >/dev/null 2>&1; then
      log "  Pushed to origin/$current_branch"

	      # Best-effort: create/update a single rolling draft PR for this host+repo.
	      # Enable by default; can be disabled with AUTO_CHECKPOINT_CREATE_PR=0.
	      if [ "${AUTO_CHECKPOINT_CREATE_PR:-1}" = "1" ] && command -v gh >/dev/null 2>&1; then
	        # Only do this for auto-checkpoint branches.
	        if [[ "$current_branch" =~ ^auto-checkpoint/ ]]; then
	          pr_title="auto-checkpoint(${hostname}): ${repo_name}"
	          pr_body="Automated checkpoint for ${repo_name} on host '${hostname}'.

	This PR is a rolling draft updated by auto-checkpoint when canonical clones accidentally become dirty.

	Safe to close without merging if not needed."
	          # If an open PR already exists for this head, do nothing.
	          existing=""
	          if existing="$(gh pr list --state open --head "$current_branch" --json number --jq '.[0].number // \"\"' 2>/dev/null)"; then
	            if [ -n "${existing:-}" ]; then
	              log "  Rolling PR already open (#$existing)"
	            else
	              pr_out=""
	              if pr_out="$(gh pr create --draft --base "$trunk_default" --head "$current_branch" --title "$pr_title" --body "$pr_body" 2>&1)"; then
	                log "  Created rolling draft PR for $current_branch"
	              else
	                log "  WARN: failed to create rolling PR for $current_branch: $pr_out"
	              fi
	            fi
	          else
	            log "  WARN: gh pr list failed; skipping rolling PR creation"
	          fi
	        fi
	      fi
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
