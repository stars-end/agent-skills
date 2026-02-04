#!/usr/bin/env bash
#
# dx-verify-clean.sh
#
# Verify canonical clones are clean + on trunk.
#
# This is a safety gate for "I am done" claims. It is intentionally simple and
# does not try to auto-fix anything.
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
done

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "🚨 FAIL: Canonical clones must be clean. Move work to a worktree and open a PR."
  exit 1
fi

echo ""
echo "✅ PASS: All canonical clones are clean."
