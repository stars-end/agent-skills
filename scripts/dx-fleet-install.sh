#!/usr/bin/env bash
#
# Fleet Sync convergent install/check lifecycle helper.
#
# Modes:
#   --apply      converge local host tools + IDE configs
#   --check      verify local host convergence
#   --uninstall  fail-open best-effort cleanup
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
MANIFEST_PATH="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
MODE="apply"

STATE_ROOT_LEGACY1="${HOME}/.dx-state/fleet-sync"
STATE_ROOT_LEGACY2="${HOME}/.dx-state/fleet_sync"

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
  dx-fleet-install.sh [--apply|--check|--uninstall] [--state-dir PATH] [--json]
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply|--install)
        MODE="apply"
        shift
        ;;
      --check)
        MODE="check"
        shift
        ;;
      --uninstall)
        MODE="uninstall"
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
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

load_manifest_legacy_roots() {
  [[ -f "$MANIFEST_PATH" ]] || return 0
  local roots
  roots="$(python3 - <<'PY' "$MANIFEST_PATH" 2>/dev/null || true
import sys, yaml
p=sys.argv[1]
try:
    data=yaml.safe_load(open(p, 'r', encoding='utf-8')) or {}
except Exception:
    sys.exit(0)
for r in (data.get('legacy_state_roots') or [])[:2]:
    print(r)
PY
)"
  if [[ -n "$roots" ]]; then
    local i=0 line
    while IFS= read -r line; do
      case "$i" in
        0)
          [[ -n "$line" ]] && STATE_ROOT_LEGACY1="${line/#\~\//$HOME/}"
          ;;
        1)
          [[ -n "$line" ]] && STATE_ROOT_LEGACY2="${line/#\~\//$HOME/}"
          ;;
      esac
      i=$((i + 1))
    done <<<"$roots"
  fi
}

state_paths_json() {
  cat <<EOF_JSON
{
  "state_dir": "$(json_escape "$STATE_ROOT")",
  "tool_health_json": "$(json_escape "${STATE_ROOT}/tool-health.json")",
  "tool_health_lines": "$(json_escape "${STATE_ROOT}/tool-health.lines")",
  "mcp_tools_sync_json": "$(json_escape "${STATE_ROOT}/mcp-tools-sync.json")",
  "audit_daily_latest": "$(json_escape "${STATE_ROOT}/audit/daily/latest.json")",
  "audit_weekly_latest": "$(json_escape "${STATE_ROOT}/audit/weekly/latest.json")",
  "legacy_state_roots": ["$(json_escape "$STATE_ROOT_LEGACY1")", "$(json_escape "$STATE_ROOT_LEGACY2")"]
}
EOF_JSON
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

extract_json_field() {
  local payload="$1"
  local expr="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$expr" 2>/dev/null || true
    return 0
  fi
  printf ''
}

uninstall_mode() {
  local timestamp epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"

  local overall_ok=true
  local reason_code="uninstall_complete"
  local next_action="noop"
  local -a actions=()
  local -a failures=()
  local -a targets=(
    "$STATE_ROOT"
    "$STATE_ROOT_LEGACY1"
    "$STATE_ROOT_LEGACY2"
    "${HOME}/.config/fleet-sync"
    "${HOME}/.cache/fleet-sync"
  )

  local target
  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      actions+=("missing_ok:$target")
      continue
    fi
    if rm -rf "$target" >/dev/null 2>&1; then
      actions+=("removed:$target")
    else
      overall_ok=false
      actions+=("failed_remove:$target")
      failures+=("failed_remove:$target")
    fi
  done

  if [[ "$overall_ok" == "false" ]]; then
    reason_code="uninstall_partial"
    next_action="rerun"
  fi

  local actions_json failures_json
  actions_json="$(json_array_from_strings "${actions[@]-}")"
  failures_json="$(json_array_from_strings "${failures[@]-}")"

  local out
  out="$(cat <<EOF_JSON
{
  "mode": "uninstall",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "overall_ok": $overall_ok,
  "reason_code": "$(json_escape "$reason_code")",
  "next_action": "$(json_escape "$next_action")",
  "checks": [],
  "reason_codes": ["$(json_escape "$reason_code")"],
  "summary": {
    "actions_attempted": ${#actions[@]},
    "errors": ${#failures[@]}
  },
  "actions": $actions_json,
  "failures": $failures_json,
  "state_paths": $(state_paths_json)
}
EOF_JSON
)"
  write_atomic "${STATE_ROOT}/uninstall.json" "$out"
  printf '%s\n' "$out"
  [[ "$overall_ok" == "true" ]]
}

apply_or_check_mode() {
  local timestamp epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"
  mkdir -p "$STATE_ROOT"

  local -a checks=()
  local -a reason_codes=()
  local overall_ok=true

  local sync_cmd=("${SCRIPT_DIR}/dx-mcp-tools-sync.sh")
  if [[ "$MODE" == "apply" ]]; then
    sync_cmd+=(--apply)
  else
    sync_cmd+=(--check)
  fi
  sync_cmd+=(--json --state-dir "$STATE_ROOT")

  local sync_out="" sync_rc=0
  if run_json_command sync_out "${sync_cmd[@]}"; then
    sync_rc=0
  else
    sync_rc=$?
  fi
  local sync_status
  sync_status="$(extract_json_field "$sync_out" '.overall // .status // "red"')"
  [[ -z "$sync_status" || "$sync_status" == "null" ]] && sync_status="red"
  checks+=("{\"id\":\"fleet.v2.2.mcp_tools_sync\",\"status\":\"$(json_escape "$sync_status")\",\"severity\":\"medium\",\"details\":\"dx-mcp-tools-sync ${MODE}\",\"next_action\":\"dx-mcp-tools-sync --repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
  if [[ "$sync_rc" -ne 0 || "$sync_status" != "green" ]]; then
    overall_ok=false
    reason_codes+=("mcp_tools_sync_failed")
  else
    reason_codes+=("mcp_tools_sync_pass")
  fi

  local daily_out="" daily_rc=0
  if run_json_command daily_out "${SCRIPT_DIR}/dx-fleet-check.sh" --mode daily --local-only --json --state-dir "$STATE_ROOT"; then
    daily_rc=0
  else
    daily_rc=$?
  fi
  local daily_status
  daily_status="$(extract_json_field "$daily_out" '.fleet_status // "red"')"
  [[ -z "$daily_status" || "$daily_status" == "null" ]] && daily_status="red"
  checks+=("{\"id\":\"fleet.v2.2.daily_check\",\"status\":\"$(json_escape "$daily_status")\",\"severity\":\"medium\",\"details\":\"dx-fleet-check --mode daily --local-only\",\"next_action\":\"dx-fleet-repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
  if [[ "$daily_rc" -ne 0 || "$daily_status" == "red" ]]; then
    overall_ok=false
    reason_codes+=("daily_check_failed")
  else
    reason_codes+=("daily_check_pass")
  fi

  local weekly_out="" weekly_rc=0
  if run_json_command weekly_out "${SCRIPT_DIR}/dx-fleet-check.sh" --mode weekly --local-only --json --state-dir "$STATE_ROOT"; then
    weekly_rc=0
  else
    weekly_rc=$?
  fi
  local weekly_status
  weekly_status="$(extract_json_field "$weekly_out" '.fleet_status // "red"')"
  [[ -z "$weekly_status" || "$weekly_status" == "null" ]] && weekly_status="red"
  checks+=("{\"id\":\"fleet.v2.2.weekly_check\",\"status\":\"$(json_escape "$weekly_status")\",\"severity\":\"medium\",\"details\":\"dx-fleet-check --mode weekly --local-only\",\"next_action\":\"dx-fleet-repair --json --state-dir $(json_escape "$STATE_ROOT")\"}")
  if [[ "$weekly_rc" -ne 0 || "$weekly_status" == "red" ]]; then
    overall_ok=false
    reason_codes+=("weekly_check_failed")
  else
    reason_codes+=("weekly_check_pass")
  fi

  local checks_json reasons_json
  checks_json="$(json_array_from_objects "${checks[@]-}")"
  reasons_json="$(json_array_from_strings "${reason_codes[@]-}")"

  local reason_code next_action
  if [[ "$overall_ok" == "true" ]]; then
    reason_code="${MODE}_complete"
    next_action="noop"
  else
    reason_code="${MODE}_partial"
    next_action="rerun"
  fi

  local out
  out="$(cat <<EOF_JSON
{
  "mode": "${MODE}",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "overall_ok": $overall_ok,
  "reason_code": "$(json_escape "$reason_code")",
  "next_action": "$(json_escape "$next_action")",
  "reason_codes": $reasons_json,
  "checks": $checks_json,
  "summary": {
    "mcp_tools_sync": "$(json_escape "$sync_status")",
    "daily_check": "$(json_escape "$daily_status")",
    "weekly_check": "$(json_escape "$weekly_status")"
  },
  "state_paths": $(state_paths_json)
}
EOF_JSON
)"

  write_atomic "${STATE_ROOT}/${MODE}.json" "$out"
  printf '%s\n' "$out"
  [[ "$overall_ok" == "true" ]]
}

main() {
  parse_args "$@"
  load_manifest_legacy_roots

  case "$MODE" in
    uninstall)
      uninstall_mode
      ;;
    apply|check)
      apply_or_check_mode
      ;;
    *)
      echo "Unsupported mode: $MODE" >&2
      exit 2
      ;;
  esac
}

main "$@"
