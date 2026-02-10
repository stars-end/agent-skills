#!/usr/bin/env bash
set -euo pipefail

# Ensure canonical repos use versioned `.githooks/` and have fallback shims installed.
# Safe to run repeatedly.

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common)

for repo in "${CANONICAL_REPOS[@]}"; do
  repo_path="$HOME/$repo"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "dx-git-hooks-bootstrap: skip (missing repo): $repo_path" >&2
    continue
  fi
  if [[ ! -d "$repo_path/.githooks" ]]; then
    echo "dx-git-hooks-bootstrap: skip (missing .githooks): $repo_path" >&2
    continue
  fi

  git -C "$repo_path" config core.hooksPath .githooks >/dev/null 2>&1 || true

  if [[ -x "$repo_path/.githooks/_bootstrap.sh" ]]; then
    "$repo_path/.githooks/_bootstrap.sh" >/dev/null 2>&1 || true
  fi

  echo "dx-git-hooks-bootstrap: ok: $repo"
done

