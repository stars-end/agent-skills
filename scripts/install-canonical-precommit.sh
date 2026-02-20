#!/usr/bin/env bash
set -euo pipefail

# Installs the canonical commit-blocking pre-commit hook in all canonical clones.
# Purpose: keep canonical repos read-mostly; all work must happen in worktrees.

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common)

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

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common)

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
}

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_root="$HOME/$repo"
  if [ -d "$repo_root/.git" ]; then
    echo "Installing canonical pre-commit and commit-msg hooks in $repo_root"
    install_for_repo "$repo_root"
  fi
done

echo "✅ Canonical hooks installed"
