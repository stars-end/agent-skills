#!/usr/bin/env bash
set -euo pipefail

# Installs the canonical commit-blocking pre-commit hook in all canonical clones.
# Purpose: keep canonical repos read-mostly; all work must happen in worktrees.

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common bd-symphony)

install_for_repo() {
  local repo_root="$1"
  local git_common_dir
  git_common_dir="$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null || echo "$repo_root/.git")"
  # rev-parse may return a relative path; normalize to absolute
  if [[ "$git_common_dir" != /* ]]; then
    git_common_dir="$repo_root/$git_common_dir"
  fi
  local hooks_dir="$git_common_dir/hooks"

  mkdir -p "$hooks_dir"

  # If a previous system installed symlinked hooks, remove them first so we do not write through the symlink target.
  rm -f "$hooks_dir/pre-commit" 2>/dev/null || true

  # Remove legacy git-safety-guard symlinked hooks if present (best-effort).
  for h in post-checkout post-merge pre-push; do
    if [ -L "$hooks_dir/$h" ]; then
      target="$(readlink "$hooks_dir/$h" 2>/dev/null || true)"
      if echo "$target" | grep -q "git-safety-guard" || echo "$target" | grep -q "\.claude/hooks"; then
        rm -f "$hooks_dir/$h" 2>/dev/null || true
      fi
    fi
  done

  cat > "$hooks_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename -- "$REPO_ROOT")"

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common bd-symphony)

# Worktree detection: in a worktree, git-dir != git-common-dir.
GIT_DIR="$(git rev-parse --git-dir)"
GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
IS_WORKTREE=0
if [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
  IS_WORKTREE=1
fi

is_canonical=0
for r in "${CANONICAL_REPOS[@]}"; do
  if [ "$REPO_NAME" = "$r" ]; then
    is_canonical=1
    break
  fi
done

if [ "$is_canonical" = "1" ] && [ "$IS_WORKTREE" = "0" ]; then
  cat >&2 <<EOF

❌ CANONICAL COMMIT BLOCKED: $REPO_NAME

You are in the canonical clone:
  $REPO_ROOT

Your changes are NOT lost. They are in your working directory.

TO RECOVER (do NOT rewrite your work):
  1. Stash your changes:
       git stash
  2. Create a worktree:
       dx-worktree create <beads-id> $REPO_NAME
  3. Move to the worktree and apply your changes:
       cd /tmp/agents/<beads-id>/$REPO_NAME
       git stash pop

Then continue working in the worktree.

EOF
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

if [ "$REPO_NAME" = "agent-skills" ] && [ -n "${CURRENT_BRANCH:-}" ]; then
  BRANCH_CONTEXT="${CURRENT_BRANCH##*/}"
  if [[ "$BRANCH_CONTEXT" == feature-* ]]; then
    BRANCH_CONTEXT="${BRANCH_CONTEXT#feature-}"
  fi
  DETECTED_ISSUE_ID=""
  if [[ "$BRANCH_CONTEXT" =~ ^([a-z][a-z0-9]*-[a-z0-9]+(\.[a-z0-9]+)*)$ ]]; then
    DETECTED_ISSUE_ID="${BASH_REMATCH[1]}"
  else
    DETECTED_ISSUE_ID="$(printf '%s\n' "$CURRENT_BRANCH" | rg -o '[a-z][a-z0-9]*-[a-z0-9]+(\.[a-z0-9]+)*' 2>/dev/null | head -1 || true)"
  fi
  if [ -n "${DETECTED_ISSUE_ID:-}" ] && [[ ! "$DETECTED_ISSUE_ID" =~ ^bd-[a-z0-9]+(\.[a-z0-9]+)*$ ]]; then
    cat >&2 <<EOF

❌ COMMIT BLOCKED: incompatible issue prefix for $REPO_NAME

Current branch:
  $CURRENT_BRANCH

Detected issue id:
  $DETECTED_ISSUE_ID

$REPO_NAME requires repo-compatible bd-* Feature-Keys and branch ids.
Do not continue with an af-* (or other non-bd-*) issue id here.

Next steps:
  1. Create or choose the correct bd-* issue for the $REPO_NAME work.
  2. Rename the branch to feature-bd-<issue>.
  3. Retry the commit.

If this work is linked to another prefix elsewhere, track that relationship in Beads instead
of committing from $REPO_NAME with an incompatible Feature-Key.

EOF
    exit 1
  fi
fi

exit 0
HOOK

  chmod +x "$hooks_dir/pre-commit"

  cat > "$hooks_dir/commit-msg" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

COMMIT_MSG_FILE=$1
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

# Skip if it's a merge commit or automated squash
if echo "$COMMIT_MSG" | grep -q "^Merge "; then
  exit 0
fi

if echo "$COMMIT_MSG" | grep -q "^squash!" || echo "$COMMIT_MSG" | grep -q "^fixup!"; then
  exit 0
fi

# Skip if it's an auto-checkpoint commit
if echo "$COMMIT_MSG" | grep -q "^checkpoint:"; then
  exit 0
fi

# Enforce Feature-Key
if ! echo "$COMMIT_MSG" | grep -q "Feature-Key:"; then
  cat >&2 <<EOF

❌ COMMIT BLOCKED: Missing Feature-Key

Every commit must include a Feature-Key trailer for traceability.
Example:
  feat: your summary

  Feature-Key: bd-123
  Agent: claude-code

EOF
  exit 1
fi

FEATURE_KEY_VALUE="$(echo "$COMMIT_MSG" | awk -F': ' '/^Feature-Key: /{print $2; exit}')"
if [[ -z "${FEATURE_KEY_VALUE:-}" ]]; then
  cat >&2 <<EOF

❌ COMMIT BLOCKED: Invalid Feature-Key trailer

Feature-Key trailer is present but empty.
Expected:
  Feature-Key: bd-123
  Feature-Key: bd-123.4

EOF
  exit 1
fi

# Dotted Beads IDs are valid (e.g., bd-5wys.10).
if [[ ! "$FEATURE_KEY_VALUE" =~ ^bd-[a-z0-9]+(\.[a-z0-9]+)*$ ]]; then
  cat >&2 <<EOF

❌ COMMIT BLOCKED: Invalid Feature-Key format

Feature-Key must match:
  ^bd-[a-z0-9]+(\\.[a-z0-9]+)*$

For agent-skills, non-bd prefixes such as af-* are incompatible.
Create or choose the repo-compatible bd-* issue before retrying.

EOF
  exit 1
fi

# Enforce Agent
if ! echo "$COMMIT_MSG" | grep -q "Agent:"; then
  cat >&2 <<EOF

❌ COMMIT BLOCKED: Missing Agent trailer

Every commit must include an Agent trailer for attribution.
Example:
  feat: your summary

  Feature-Key: bd-123
  Agent: claude-code

EOF
  exit 1
fi

exit 0
HOOK

  chmod +x "$hooks_dir/commit-msg"

  # Also update versioned .githooks if they exist (V8.1 pattern)
  if [[ -d "$repo_root/.githooks" ]]; then
    cp "$hooks_dir/pre-commit" "$repo_root/.githooks/pre-commit"
    cp "$hooks_dir/commit-msg" "$repo_root/.githooks/commit-msg"
    chmod +x "$repo_root/.githooks/pre-commit" "$repo_root/.githooks/commit-msg"
  fi
}

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_root="$HOME/$repo"
  if [ -d "$repo_root/.git" ]; then
    echo "Installing canonical pre-commit and commit-msg hooks in $repo_root"
    install_for_repo "$repo_root"
  fi
done

echo "✅ Canonical hooks installed"
