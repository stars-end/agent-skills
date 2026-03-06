#!/usr/bin/env bash
#
# dx-fleet-repair.sh
#
# Convergent repair orchestrator for Fleet Sync.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
SIMULATE=0

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

write_atomic() {
  local target="$1"
  local data="$2"
  local tmp
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  printf '%s\n' "$data" > "$tmp"
  mv "$tmp" "$target"
}

json_array_from_strings() {
  local out="["
  local first=1
  local item
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      out+=","
    fi
    out+="\"$(json_escape "$item")\""
  done
  out+="]"
  printf '%s' "$out"
}

json_array_from_objects() {
  local out="["
  local first=1
  local item
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      out+=","
    fi
    out+="$item"
  done
  out+="]"
  printf '%s' "$out"
}

usage() {
  cat <<'USAGE'
Usage:
  dx-fleet-repair.sh [--state-dir PATH] [--simulate] [--json]
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --simulate)
        SIMULATE=1
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        shift 2
        ;;
      --json|--json-only)
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

run_json_command() {
  local out_ref="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  local rc=$?
  set -e
  printf -v "$out_ref" '%s' "$(cat "$tmp")"
  rm -f "$tmp"
  return $rc
}

extract_field() {
  local payload="$1"
  local expr="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$expr" 2>/dev/null || true
    return 0
  fi
  printf ''
}

main() {
  parse_args "$@"

  local timestamp epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"

  local -a checks=()
  local -a hints=()
  local -a reason_codes=()
  local overall_ok=true

  if [[ "$SIMULATE" -eq 1 ]]; then
    checks+=("{\"id\":\"fleet.v2.2.simulation\",\"status\":\"pass\",\"severity\":\"low\",\"details\":\"simulation mode\"}")
    reason_codes+=("simulation_mode")
  else
    local sync_out="" sync_rc=0
    if run_json_command sync_out "${SCRIPT_DIR}/dx-mcp-tools-sync.sh" --repair --json --state-dir "$STATE_ROOT"; then
      sync_rc=0
    else
      sync_rc=$?
    fi
    local sync_status
    sync_status="$(extract_field "$sync_out" '.overall // "red"')"
    [[ -z "$sync_status" || "$sync_status" == "null" ]] && sync_status="red"
    checks+=("{\"id\":\"fleet.v2.2.mcp_tools_repair\",\"status\":\"$(json_escape "$sync_status")\",\"severity\":\"medium\",\"details\":\"dx-mcp-tools-sync --repair\",\"next_action\":\"dx-mcp-tools-sync --repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    if [[ "$sync_rc" -ne 0 || "$sync_status" != "green" ]]; then
      overall_ok=false
      reason_codes+=("mcp_tools_repair_failed")
      hints+=("{\"host\":\"local\",\"check_id\":\"fleet.v2.2.mcp_tools_repair\",\"command\":\"dx-mcp-tools-sync --repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    fi

    local apply_out="" apply_rc=0
    if run_json_command apply_out "${SCRIPT_DIR}/dx-fleet-install.sh" --apply --json --state-dir "$STATE_ROOT"; then
      apply_rc=0
    else
      apply_rc=$?
    fi
    local apply_ok
    apply_ok="$(extract_field "$apply_out" '.overall_ok // false')"
    [[ "$apply_ok" == "true" ]] && apply_ok="pass" || apply_ok="fail"
    checks+=("{\"id\":\"fleet.v2.2.local_apply\",\"status\":\"$apply_ok\",\"severity\":\"medium\",\"details\":\"dx-fleet-install --apply\",\"next_action\":\"dx-fleet-install --apply --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    if [[ "$apply_rc" -ne 0 || "$apply_ok" != "pass" ]]; then
      overall_ok=false
      reason_codes+=("local_apply_failed")
      hints+=("{\"host\":\"local\",\"check_id\":\"fleet.v2.2.local_apply\",\"command\":\"dx-fleet-install --apply --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    fi

    local daily_out="" daily_rc=0
    if run_json_command daily_out "${SCRIPT_DIR}/dx-fleet-check.sh" --mode daily --local-only --json --state-dir "$STATE_ROOT"; then
      daily_rc=0
    else
      daily_rc=$?
    fi
    local daily_status
    daily_status="$(extract_field "$daily_out" '.fleet_status // "red"')"
    checks+=("{\"id\":\"fleet.v2.2.daily_verify\",\"status\":\"$(json_escape "$daily_status")\",\"severity\":\"medium\",\"details\":\"dx-fleet-check --mode daily --local-only\",\"next_action\":\"dx-fleet-repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    if [[ "$daily_rc" -ne 0 || "$daily_status" == "red" ]]; then
      overall_ok=false
      reason_codes+=("daily_verify_failed")
    fi

    local weekly_out="" weekly_rc=0
    if run_json_command weekly_out "${SCRIPT_DIR}/dx-fleet-check.sh" --mode weekly --local-only --json --state-dir "$STATE_ROOT"; then
      weekly_rc=0
    else
      weekly_rc=$?
    fi
    local weekly_status
    weekly_status="$(extract_field "$weekly_out" '.fleet_status // "red"')"
    checks+=("{\"id\":\"fleet.v2.2.weekly_verify\",\"status\":\"$(json_escape "$weekly_status")\",\"severity\":\"medium\",\"details\":\"dx-fleet-check --mode weekly --local-only\",\"next_action\":\"dx-fleet-repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
    if [[ "$weekly_rc" -ne 0 || "$weekly_status" == "red" ]]; then
      overall_ok=false
      reason_codes+=("weekly_verify_failed")
    fi
  fi

  [[ ${#reason_codes[@]} -eq 0 ]] && reason_codes+=("repair_complete")

  local checks_json hints_json reason_json
  checks_json="$(json_array_from_objects "${checks[@]-}")"
  hints_json="$(json_array_from_objects "${hints[@]-}")"
  reason_json="$(json_array_from_strings "${reason_codes[@]-}")"

  local fleet_status next_action reason_code
  if [[ "$overall_ok" == "true" ]]; then
    fleet_status="green"
    next_action="noop"
    reason_code="repair_complete"
  else
    fleet_status="red"
    next_action="rerun"
    reason_code="repair_partial"
  fi

  local out
  out="$(cat <<EOF_JSON
{
  "mode": "repair",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "fleet_status": "$(json_escape "$fleet_status")",
  "overall_ok": $overall_ok,
  "summary": {
    "checks_checked": ${#checks[@]},
    "repaired": $([[ "$SIMULATE" -eq 1 ]] && echo 0 || echo 1),
    "failed": $([[ "$overall_ok" == "true" ]] && echo 0 || echo 1)
  },
  "checks": $checks_json,
  "repair_hints": $hints_json,
  "reason_codes": $reason_json,
  "reason_code": "$(json_escape "$reason_code")",
  "next_action": "$(json_escape "$next_action")",
  "state_paths": {
    "tool_health_json": "$(json_escape "${STATE_ROOT}/tool-health.json")",
    "repair_artifact": "$(json_escape "${STATE_ROOT}/repair.json")"
  }
}
EOF_JSON
)"

  write_atomic "${STATE_ROOT}/repair.json" "$out"
  printf '%s\n' "$out"
  [[ "$overall_ok" == "true" ]]
}

main "$@"
