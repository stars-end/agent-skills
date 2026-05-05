#!/usr/bin/env bash
#
# dx-verify-clean.sh
#
# Verify canonical clones are clean + on trunk.
#
# This is a safety gate for "I am done" claims. It normally verifies only. The
# one auto-repair exception is generated hook drift in canonical clones: local
# hook bootstrap/cron paths can rewrite the two tracked hook files and briefly
# block unrelated product work. If those are the only dirty paths, restore them
# from HEAD and re-check.
#
# Environment Variables:
#   DX_VERIFY_FAIL_ON_STASHES=1  Treat canonical stashes as blocking hidden state
#   DX_VERIFY_ALLOW_STASHES=1    Compatibility override; stashes are warn-only
#                                by default for worker done gates
#   DX_VERIFY_AUTO_REPAIR_HOOK_DRIFT=0
#                                Disable auto-restore of hook-only drift
#
set -euo pipefail

CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common" "bd-symphony")
TRUNK_BRANCH="master"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"

fail=0

is_hook_only_dirty() {
  local status="$1"

  [[ -n "$status" ]] || return 1

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "${line:3}" in
      .githooks/commit-msg|.githooks/pre-commit)
        ;;
      *)
        return 1
        ;;
    esac
  done <<< "$status"

  return 0
}

repair_hook_only_dirty() {
  local repo_path="$1"

  git -C "$repo_path" restore --staged --worktree -- .githooks/commit-msg .githooks/pre-commit 2>/dev/null
}

echo "🔍 Verifying canonical repos are clean + on their canonical branches..."

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_path="$HOME/$repo"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "⚠️  $repo: missing at $repo_path (skipping)"
    continue
  fi

  branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
  status="$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)"
  expected_branch="$(canonical_repo_branch "$repo")"

  if [[ "$branch" != "$expected_branch" ]]; then
    echo "❌ $repo: on '$branch' (expected '$expected_branch')"
    fail=1
  fi

  if [[ -n "$status" && "$branch" == "$expected_branch" && "${DX_VERIFY_AUTO_REPAIR_HOOK_DRIFT:-1}" != "0" ]]; then
    if is_hook_only_dirty "$status" && repair_hook_only_dirty "$repo_path"; then
      echo "🧹 $repo: auto-restored hook-only canonical drift"
      status="$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)"
    fi
  fi

  if [[ -n "$status" ]]; then
    echo "❌ $repo: dirty canonical clone (uncommitted changes)"
    echo "$status" | sed 's/^/   /'
    fail=1
  else
    echo "✅ $repo: clean"
  fi

  # Legacy containment regression guard for leftover semantic runtime artifacts.
  artifact_paths="$(
    find "$repo_path" \
      \( -path "$repo_path/.git" -o -path "$repo_path/.git/*" \) -prune -o \
      \( -type d -name ".tldr" -o -type f -name ".tldrignore" \) -print 2>/dev/null || true
  )"
  if [[ -n "$artifact_paths" ]]; then
    echo "❌ $repo: legacy semantic artifact leakage detected (.tldr/.tldrignore)"
    echo "$artifact_paths" | sed 's/^/   /'
    echo "   Remove leaked artifacts (legacy semantic runtime state)."
    fail=1
  fi

  # Check for stashes. Stashes can predate a worker session and should not make
  # unrelated agents fail their done gate by default. Strict fleet audits can opt
  # into failing on hidden stashes with DX_VERIFY_FAIL_ON_STASHES=1.
  stashes="$(git -C "$repo_path" stash list 2>/dev/null || true)"
  if [[ -n "$stashes" ]]; then
    stash_count=$(echo "$stashes" | wc -l | tr -d ' ')
    if [[ "${DX_VERIFY_FAIL_ON_STASHES:-0}" == "1" && "${DX_VERIFY_ALLOW_STASHES:-0}" != "1" ]]; then
      echo "❌ $repo: has $stash_count stash(es) (hidden state; strict stash failure enabled)"
      echo "$stashes" | sed 's/^/   /'
      fail=1
    else
      echo "⚠️  $repo: has $stash_count stash(es) (hidden state; non-blocking for worker done gate)"
      echo "$stashes" | sed 's/^/   /'
    fi
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "🚨 FAIL: Canonical clones must be clean. Move work to a worktree and open a PR."
  echo ""
  echo "💡 TIP: Pre-existing stashes are warn-only by default. Use DX_VERIFY_FAIL_ON_STASHES=1 for strict fleet audits."
  exit 1
fi

echo ""
echo "✅ PASS: All canonical clones have no blocking hygiene issues."
