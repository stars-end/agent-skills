#!/usr/bin/env bash
#
# dx-verify-clean.sh
#
# Verify canonical clones are clean + on trunk.
#
# This is a safety gate for "I am done" claims. It is intentionally simple and
# does not try to auto-fix anything.
#
# Environment Variables:
#   DX_VERIFY_ALLOW_STASHES=1  Allow stashes (use when you've verified they're safe)
#
set -euo pipefail

CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
TRUNK_BRANCH="master"

fail=0

echo "🔍 Verifying canonical repos are clean + on ${TRUNK_BRANCH}..."

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_path="$HOME/$repo"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "⚠️  $repo: missing at $repo_path (skipping)"
    continue
  fi

  branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
  status="$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)"

  if [[ "$branch" != "$TRUNK_BRANCH" ]]; then
    echo "❌ $repo: on '$branch' (expected '$TRUNK_BRANCH')"
    fail=1
  fi

  if [[ -n "$status" ]]; then
    echo "❌ $repo: dirty canonical clone (uncommitted changes)"
    echo "$status" | sed 's/^/   /'
    fail=1
  else
    echo "✅ $repo: clean"
  fi

  # Containment regression guard for llm-tldr runtime artifacts.
  artifact_paths="$(
    find "$repo_path" \
      \( -path "$repo_path/.git" -o -path "$repo_path/.git/*" \) -prune -o \
      \( -type d -name ".tldr" -o -type f -name ".tldrignore" \) -print 2>/dev/null || true
  )"
  if [[ -n "$artifact_paths" ]]; then
    echo "❌ $repo: llm-tldr artifact leakage detected (.tldr/.tldrignore)"
    echo "$artifact_paths" | sed 's/^/   /'
    echo "   Remove leaked artifacts and re-run containment warm via scripts/tldr-contained.sh"
    fail=1
  fi

  # Check for stashes
  stashes="$(git -C "$repo_path" stash list 2>/dev/null || true)"
  if [[ -n "$stashes" ]]; then
    stash_count=$(echo "$stashes" | wc -l | tr -d ' ')
    if [[ "${DX_VERIFY_ALLOW_STASHES:-0}" == "1" ]]; then
      echo "⚠️  $repo: has $stash_count stash(es) (hidden state - allowed by DX_VERIFY_ALLOW_STASHES)"
      echo "$stashes" | sed 's/^/   /'
    else
      echo "❌ $repo: has $stash_count stash(es) (hidden state)"
      echo "$stashes" | sed 's/^/   /'
      fail=1
    fi
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "🚨 FAIL: Canonical clones must be clean. Move work to a worktree and open a PR."
  echo ""
  echo "💡 TIP: If stashes are verified safe, run with DX_VERIFY_ALLOW_STASHES=1"
  exit 1
fi

echo ""
echo "✅ PASS: All canonical clones are clean."
