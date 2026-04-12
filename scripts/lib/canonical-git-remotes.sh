#!/usr/bin/env bash
#
# Canonical Git remote helpers for stars-end canonical repos.
#
set -euo pipefail

canonical_expected_ssh_origin() {
  local repo="$1"
  printf 'git@github.com:stars-end/%s.git\n' "$repo"
}

canonical_is_ssh_origin() {
  local repo="$1"
  local url="$2"
  local base_no_git="git@github.com:stars-end/${repo}"
  local base_with_git="${base_no_git}.git"
  local ssh_no_git="ssh://git@github.com/stars-end/${repo}"
  local ssh_with_git="${ssh_no_git}.git"
  [[ "$url" == "$base_no_git" || "$url" == "$base_with_git" || "$url" == "$ssh_no_git" || "$url" == "$ssh_with_git" ]]
}

canonical_is_convertible_https_origin() {
  local repo="$1"
  local url="$2"
  local https_no_git="https://github.com/stars-end/${repo}"
  local https_with_git="${https_no_git}.git"
  [[ "$url" == "$https_no_git" || "$url" == "$https_with_git" ]]
}

canonical_ensure_origin_ssh() {
  # Output format:
  #   <status>|<current>|<expected>
  # status:
  #   ssh_ok | converted | missing_origin | unsupported_origin | set_failed | read_failed
  local repo="$1"
  local repo_path="$2"
  local mode="${3:-fix}" # fix | check

  local current_url=""
  if ! current_url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"; then
    printf 'read_failed||\n'
    return 0
  fi

  local expected_url
  expected_url="$(canonical_expected_ssh_origin "$repo")"

  if [[ -z "$current_url" ]]; then
    printf 'missing_origin||%s\n' "$expected_url"
    return 0
  fi

  if canonical_is_ssh_origin "$repo" "$current_url"; then
    printf 'ssh_ok|%s|%s\n' "$current_url" "$expected_url"
    return 0
  fi

  if canonical_is_convertible_https_origin "$repo" "$current_url"; then
    if [[ "$mode" == "fix" ]]; then
      if git -C "$repo_path" remote set-url origin "$expected_url" >/dev/null 2>&1; then
        printf 'converted|%s|%s\n' "$current_url" "$expected_url"
      else
        printf 'set_failed|%s|%s\n' "$current_url" "$expected_url"
      fi
    else
      printf 'unsupported_origin|%s|%s\n' "$current_url" "$expected_url"
    fi
    return 0
  fi

  printf 'unsupported_origin|%s|%s\n' "$current_url" "$expected_url"
  return 0
}

canonical_github_ssh_smoke() {
  local repo="${1:-agent-skills}"
  local timeout_s="${2:-8}"
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=${timeout_s} -o StrictHostKeyChecking=accept-new" \
    git ls-remote "git@github.com:stars-end/${repo}.git" HEAD >/dev/null 2>&1
}
