#!/usr/bin/env bash
set -euo pipefail

# Ensure canonical repos use versioned `.githooks/` and have fallback shims installed.
# Safe to run repeatedly.

CANONICAL_REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
HOOK_NAMES=(pre-commit commit-msg pre-push post-merge post-checkout post-rewrite)

shim_body() {
  cat <<'SHIM'
#!/usr/bin/env bash
# DX_GITHOOKS_SHIM
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
HOOK="$(basename "$0")"
TARGET="$ROOT/.githooks/$HOOK"

if [[ -x "$TARGET" ]]; then
  exec "$TARGET" "$@"
fi

exit 0
SHIM
}

ensure_hook_shims() {
  local repo_path="$1"
  local git_common_dir
  git_common_dir="$(git -C "$repo_path" rev-parse --git-common-dir 2>/dev/null || echo "$repo_path/.git")"
  if [[ "$git_common_dir" != /* ]]; then
    git_common_dir="$repo_path/$git_common_dir"
  fi

  local hooks_dir="$git_common_dir/hooks"
  mkdir -p "$hooks_dir"

  local hook shim current_target
  for hook in "${HOOK_NAMES[@]}"; do
    shim="$hooks_dir/$hook"

    # Legacy pattern `.git/hooks/<hook> -> ../../hooks/<hook>` causes tracked-file drift.
    if [[ -L "$shim" ]]; then
      current_target="$(readlink "$shim" 2>/dev/null || true)"
      rm -f "$shim"
      echo "dx-git-hooks-bootstrap: repaired symlink hook: $repo_path:$hook (${current_target:-unknown})"
    fi

    if [[ -f "$shim" ]] && ! grep -q "DX_GITHOOKS_SHIM" "$shim" 2>/dev/null; then
      # Preserve unknown custom hooks.
      continue
    fi

    shim_body > "$shim"
    chmod +x "$shim" 2>/dev/null || true
  done
}

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

  # Repair legacy symlink-based hooks before any bootstrap writes.
  ensure_hook_shims "$repo_path"

  if [[ -x "$repo_path/.githooks/_bootstrap.sh" ]]; then
    "$repo_path/.githooks/_bootstrap.sh" >/dev/null 2>&1 || true
  fi

  echo "dx-git-hooks-bootstrap: ok: $repo"
done
