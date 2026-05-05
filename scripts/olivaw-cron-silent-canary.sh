#!/usr/bin/env bash
set -euo pipefail

run_case() {
  local name="$1"
  local input="$2"

  case "${input}" in
    no-change)
      printf '{"case":"%s","classification":"silent","slack_post":false,"line":"[SILENT] no change","exit_code":0}\n' "${name}"
      ;;
    changed)
      printf '{"case":"%s","classification":"alert","slack_post":true,"severity":"info","failure_reason":"","exit_code":0}\n' "${name}"
      ;;
    failure)
      printf '{"case":"%s","classification":"error","slack_post":true,"severity":"error","failure_reason":"synthetic_failure","exit_code":1}\n' "${name}"
      ;;
    *)
      printf '{"case":"%s","classification":"error","slack_post":false,"failure_reason":"unknown_input","exit_code":2}\n' "${name}"
      ;;
  esac
}

no_change_1="$(run_case no_change_1 no-change)"
no_change_2="$(run_case no_change_2 no-change)"
changed="$(run_case changed changed)"
failure="$(run_case failure failure)"

jq -n \
  --argjson no_change_1 "${no_change_1}" \
  --argjson no_change_2 "${no_change_2}" \
  --argjson changed "${changed}" \
  --argjson failure "${failure}" '
    {
      ok: (
        $no_change_1.slack_post == false and
        $no_change_2.slack_post == false and
        $changed.slack_post == true and
        $failure.slack_post == true and
        $failure.failure_reason == "synthetic_failure"
      ),
      cases: [$no_change_1, $no_change_2, $changed, $failure]
    }
  '
