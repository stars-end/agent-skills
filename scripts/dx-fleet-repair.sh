#!/usr/bin/env bash
#
# dx-fleet-repair.sh
#
# Fleet repair orchestrator.
# Emits valid JSON before every exit path.
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
        cat <<'EOF'
Usage:
  dx-fleet-repair.sh [--state-dir PATH] [--simulate]
EOF
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 1
        ;;
    esac
  done
}

repair_hint_for() {
  local check_id="$1"
  case "$check_id" in
    beads_dolt)
      echo "Run dx-fleet check --json"
      ;;
    tool_mcp_health)
      echo "dx-mcp-tools-sync.sh --repair --json"
      ;;
    required_service_health)
      echo "Install required tools from canonical toolset"
      ;;
    op_auth_readiness)
      echo "Set OP_SERVICE_ACCOUNT_TOKEN from 1Password"
      ;;
    alerts_transport_readiness)
      echo "Set DX_SLACK_WEBHOOK or SLACK_BOT_TOKEN"
      ;;
    *)
      echo "Review state and rerun dx-fleet check"
      ;;
  esac
}

normalize_status() {
  local status="$1"
  case "$status" in
    pass|green)
      printf 'pass'
      ;;
    warn|yellow)
      printf 'warn'
      ;;
    fail|red)
      printf 'fail'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

load_tool_health_source() {
  local source="${STATE_ROOT}/tool-health.json"
  if [[ ! -f "$source" ]]; then
    if [[ -f "${HOME}/.dx-state/fleet-sync/tool-health.json" ]]; then
      source="${HOME}/.dx-state/fleet-sync/tool-health.json"
    elif [[ -f "${HOME}/.dx-state/fleet_sync/tool-health.json" ]]; then
      source="${HOME}/.dx-state/fleet_sync/tool-health.json"
    fi
  fi

  if [[ -f "$source" ]]; then
    printf '%s\n' "$source"
    return 0
  fi
  return 1
}

extract_health_rows() {
  local source_file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hosts[]? | . as $h | $h.checks[]? | "\($h.host // "unknown")\t\(.id // "")\t\(.status // "unknown")\t\(.severity // "low")\t\(.details // "")"' "$source_file"
    return
  fi

  python3 - "$source_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8", errors="ignore") as fp:
    data = json.load(fp)
for host_obj in data.get("hosts", []):
    host = host_obj.get("host", "unknown")
    for c in host_obj.get("checks", []):
        print("\t".join([
            host,
            c.get("id", ""),
            c.get("status", "unknown"),
            c.get("severity", "low"),
            c.get("details", ""),
        ]))
PY
}

run_repair() {
  local -a checks=()
  local -a reasons=()
  local -a hints=()
  local pass=0
  local warn=0
  local fail=0
  local unknown=0
  local attempted_checks=0
  local attempted_repairs=0
  local failed_repairs=0

  if [[ "$SIMULATE" -eq 1 ]]; then
    reasons+=("simulation_mode")
    checks+=("{\"id\":\"fleet.v2.2.simulation\",\"status\":\"pass\",\"severity\":\"low\",\"details\":\"simulation mode executed\"}")
    pass=$((pass + 1))
  else
    if "${SCRIPT_DIR}/dx-mcp-tools-sync.sh" --repair --state-dir "$STATE_ROOT" >/dev/null 2>&1; then
      attempted_repairs=$((attempted_repairs + 1))
    else
      failed_repairs=$((failed_repairs + 1))
      checks+=("{\"id\":\"fleet.v2.2.mcp_tools_sync_repair\",\"status\":\"fail\",\"severity\":\"medium\",\"details\":\"dx-mcp-tools-sync.sh --repair returned non-zero\"}")
      fail=$((fail + 1))
      reasons+=("mcp_tools_sync_repair_failed")
    fi
  fi

  local source_file
  if ! source_file="$(load_tool_health_source)"; then
    checks+=("{\"id\":\"fleet.v2.2.tool_health_cache\",\"status\":\"warn\",\"severity\":\"medium\",\"details\":\"no cached tool health snapshot\"}")
    warn=$((warn + 1))
    reasons+=("tool_health_cache_missing")
  else
    local parsed_any=0
    while IFS=$'\t' read -r host check_id status severity details; do
      if [[ -z "$check_id" ]]; then
        continue
      fi
      parsed_any=1
      attempted_checks=$((attempted_checks + 1))
      local normalized
      normalized="$(normalize_status "$status")"

      case "$normalized" in
        pass) pass=$((pass + 1)) ;;
        warn) warn=$((warn + 1)) ;;
        fail) fail=$((fail + 1)) ;;
        *) unknown=$((unknown + 1)) ;;
      esac

      local hint
      hint="$(repair_hint_for "$check_id")"
      checks+=("{\"id\":\"fleet.v2.2.${check_id}\",\"host\":\"$(json_escape "$host")\",\"status\":\"$normalized\",\"severity\":\"$(json_escape "$severity")\",\"details\":\"$(json_escape "$details")\",\"next_action\":\"$(json_escape "$hint")\"}")
      if [[ "$normalized" != "pass" ]]; then
        hints+=("{\"host\":\"$(json_escape "$host")\",\"check_id\":\"fleet.v2.2.${check_id}\",\"command\":\"$(json_escape "$hint")\"}")
      fi
    done < <(extract_health_rows "$source_file")

    if [[ "$parsed_any" -eq 0 ]]; then
      checks+=("{\"id\":\"fleet.v2.2.tool_health_cache\",\"status\":\"warn\",\"severity\":\"medium\",\"details\":\"tool health snapshot had no checks\"}")
      warn=$((warn + 1))
      reasons+=("empty_tool_health_snapshot")
    fi
  fi

  if [[ ${#reasons[@]} -eq 0 ]]; then
    reasons+=("repair_complete")
  fi

  local checks_json="["
  local first=1
  local row
  for row in "${checks[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      checks_json+="$row"
      first=0
    else
      checks_json+=",$row"
    fi
  done
  checks_json+="]"

  local reasons_json="["
  first=1
  for row in "${reasons[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      reasons_json+="\"$row\""
      first=0
    else
      reasons_json+=",\"$row\""
    fi
  done
  reasons_json+="]"

  local hints_json="["
  first=1
  for row in "${hints[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      hints_json+="$row"
      first=0
    else
      hints_json+=",$row"
    fi
  done
  hints_json+="]"

  if [[ "$SIMULATE" -eq 1 ]]; then
    failed_repairs=0
  fi

  local overall_ok="true"
  if [[ "$fail" -gt 0 || "$failed_repairs" -gt 0 ]]; then
    overall_ok="false"
  fi

  local fleet_status="green"
  if [[ "$warn" -gt 0 && "$fail" -eq 0 ]]; then
    fleet_status="yellow"
  elif [[ "$fail" -gt 0 || "$failed_repairs" -gt 0 ]]; then
    fleet_status="red"
  fi

  local next_action="noop"
  local reason_code="repair_complete"
  if [[ "$overall_ok" == "false" ]]; then
    next_action="rerun"
  fi

  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"
  local out
  out="$(cat <<EOF
{
  "mode": "repair",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "fleet_status": "$fleet_status",
  "overall_ok": $overall_ok,
  "summary": {
    "checks_checked": $attempted_checks,
    "repaired": $attempted_repairs,
    "failed": $failed_repairs,
    "pass": $pass,
    "warn": $warn,
    "fail": $fail,
    "unknown": $unknown
  },
  "checks": $checks_json,
  "repair_hints": $hints_json,
  "reason_codes": $reasons_json,
  "reason_code": "$reason_code",
  "next_action": "$next_action",
  "state_paths": {
    "tool_health_json": "${STATE_ROOT}/tool-health.json",
    "repair_artifact": "${STATE_ROOT}/repair.json"
  }
}
EOF
)"
  printf '%s\n' "$out"
  write_atomic "${STATE_ROOT}/repair.json" "$out"

  if [[ "$overall_ok" == "true" ]]; then
    return 0
  fi
  return 2
}

parse_args "$@"
run_repair
exit $?
