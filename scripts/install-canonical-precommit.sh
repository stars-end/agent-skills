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

All work must happen in a worktree:
  dx-worktree create <beads-id> $REPO_NAME
  cd /tmp/agents/<beads-id>/$REPO_NAME

If you already did work here and need to preserve it:
  auto-checkpoint

EOF
  exit 1
fi

exit 0
HOOK

  chmod +x "$hooks_dir/pre-commit"
}

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_root="$HOME/$repo"
  if [ -d "$repo_root/.git" ]; then
    echo "Installing canonical pre-commit hook in $repo_root"
    install_for_repo "$repo_root"
  fi
done

echo "✅ Canonical pre-commit hooks installed"

