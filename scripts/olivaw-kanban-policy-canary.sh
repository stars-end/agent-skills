#!/usr/bin/env bash
set -euo pipefail

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

is_valid_bdx() {
  [[ "${1:-}" =~ ^bd-[A-Za-z0-9]+([.][0-9]+)*$ ]]
}

classify_case() {
  local name="$1"
  local source_bdx="$2"
  local requested_action="$3"
  local operator_intent="$4"

  local ok=true
  local can_execute=false
  local action="intake_only"
  local reason="ok"

  if [[ "${requested_action}" == "native_kanban_engineering" ]]; then
    ok=false
    action="stop"
    reason="native_kanban_engineering_forbidden"
  elif [[ -z "${source_bdx}" ]]; then
    ok=true
    action="intake_only"
    reason="missing_source_bdx"
  elif ! is_valid_bdx "${source_bdx}"; then
    ok=false
    action="blocked"
    reason="invalid_source_bdx"
  elif [[ "${operator_intent}" == "launch" ]]; then
    ok=true
    action="ready_for_owner_contract"
    reason="bd_symphony_signoff_required"
  else
    ok=true
    action="pointer_only"
    reason="canonical_state_external"
  fi

  cat <<JSON
{
  "name": "${name}",
  "ok": ${ok},
  "source_bdx": "${source_bdx}",
  "requested_action": "${requested_action}",
  "operator_intent": "${operator_intent}",
  "can_execute": ${can_execute},
  "action": "${action}",
  "reason": "${reason}"
}
JSON
}

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

{
  classify_case "missing_source_bdx" "" "coding_request" "launch"
  classify_case "invalid_source_bdx" "ticket-123" "coding_request" "launch"
  classify_case "valid_source_bdx_followup" "bd-1ocyi.6.1" "coding_request" "followup"
  classify_case "valid_source_bdx_launch_waits_for_owner" "bd-1ocyi.6.1" "coding_request" "launch"
  classify_case "native_kanban_engineering_forbidden" "" "native_kanban_engineering" "launch"
} >"${tmp}"

failures="$(jq -s '[.[] | select((.name == "missing_source_bdx" and .action != "intake_only") or (.name == "invalid_source_bdx" and .action != "blocked") or (.name == "valid_source_bdx_followup" and .action != "pointer_only") or (.name == "valid_source_bdx_launch_waits_for_owner" and .action != "ready_for_owner_contract") or (.name == "native_kanban_engineering_forbidden" and .action != "stop") or (.can_execute != false))]' "${tmp}")"

ok=true
if [[ "$(printf '%s' "${failures}" | jq 'length')" != "0" ]]; then
  ok=false
fi

cat <<JSON
{
  "ok": ${ok},
  "canary": "synthetic-only",
  "scope": "hermes-kanban-policy-no-gascity",
  "allowed_metadata_fields": [
    "source_bdx",
    "gascity_order_id",
    "gascity_run_id",
    "correlation_id",
    "surface",
    "canonical_url",
    "operator_intent",
    "last_known_bdx_status"
  ],
  "stop_condition": "if fulfilling a Kanban action requires creating a parallel task graph, executing repo work without Beads identity, or treating Kanban state as more authoritative than Beads/Gas City, stop and request canonical Beads routing",
  "cases": $(jq -s '.' "${tmp}"),
  "failures": ${failures}
}
JSON

if [[ "${ok}" != true ]]; then
  exit 1
fi
