#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/canonical-git-remotes.sh
source "$ROOT/scripts/lib/canonical-git-remotes.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$(canonical_repo_branch agent-skills)" == "master" ]] || fail "agent-skills branch"
[[ "$(canonical_repo_branch bd-symphony)" == "main" ]] || fail "bd-symphony branch"

[[ "$(canonical_expected_ssh_origin agent-skills)" == "git@github.com:stars-end/agent-skills.git" ]] || fail "agent-skills origin"
[[ "$(canonical_expected_ssh_origin bd-symphony)" == "git@github.com:fengning-starsend/bd-symphony.git" ]] || fail "bd-symphony origin"

canonical_is_ssh_origin bd-symphony "git@github.com:fengning-starsend/bd-symphony.git" || fail "bd-symphony ssh origin"
canonical_is_convertible_https_origin bd-symphony "https://github.com/fengning-starsend/bd-symphony.git" || fail "bd-symphony https origin"

if canonical_is_convertible_https_origin bd-symphony "https://github.com/stars-end/bd-symphony.git"; then
  fail "bd-symphony should not accept stars-end origin"
fi

echo "PASS: canonical git remotes"
