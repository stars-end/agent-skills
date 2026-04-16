#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "pr" ]]; then
  echo "unsupported fake gh command" >&2
  exit 2
fi
shift
case "${1:-}" in
  view)
    cat <<'JSON'
{"number":554,"url":"https://github.com/stars-end/agent-skills/pull/554","title":"bd-icwpm: Fix dx-review authoritative worktree preflight","state":"MERGED","baseRefName":"master","headRefName":"feature-bd-icwpm","baseRefOid":"79f2d464bbc052a4bb50fb2f4c77bb950e4a8554","headRefOid":"6771fc8c14cb93d03956a8c373cb328d9140c0ec","files":[{"path":"scripts/dx-review"},{"path":"scripts/test-dx-review.sh"}],"statusCheckRollup":[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}
JSON
    ;;
  diff)
    echo " scripts/dx-review | 12 ++++++++++--"
    echo " 1 file changed, 10 insertions(+), 2 deletions(-)"
    ;;
  *)
    echo "unsupported fake gh pr command" >&2
    exit 2
    ;;
esac
