#!/usr/bin/env bash
#
# Fleet Sync installer and lifecycle helper for deterministic operations.
# - install / check: runs health + MCP-tool checks and writes install state
# - uninstall: best-effort teardown, no optional Python dependencies required
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
MANIFEST_PATH="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
MODE="install"
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

expand_home() {
  local value="$1"
  if [[ "$value" == "~/"* ]]; then
    printf '%s\n' "${value/#~\//$HOME/}"
  else
    printf '%s\n' "$value"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  dx-fleet-install.sh [--state-dir PATH]
  dx-fleet-install.sh --check [--state-dir PATH]
  dx-fleet-install.sh --uninstall [--state-dir PATH]

Defaults: install mode (deterministic check and state write).
Uninstall is best-effort and does not require optional Python modules.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install)
        MODE="install"
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

load_manifest_roots() {
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    return
  fi
  local -a roots=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*//g' -e 's/^-"//;s/"$//')"
    [[ -z "$line" ]] && continue
    roots+=("$(expand_home "$line")")
  done < <(
    awk '
      /^legacy_state_roots:/ { in_legacy=1; next }
      in_legacy {
        if ($0 ~ /^[^[:space:]]/) { in_legacy=0; exit }
        if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
          s=$0
          sub(/^[[:space:]]*-[[:space:]]*/, "", s)
          gsub(/#.*/, "", s)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          if (s != "") print s
        }
      }
    ' "$MANIFEST_PATH"
  )
  if [[ "${#roots[@]}" -gt 0 ]]; then
    STATE_ROOT_LEGACY1="${roots[0]:-"$STATE_ROOT_LEGACY1"}"
    STATE_ROOT_LEGACY2="${roots[1]:-"$STATE_ROOT_LEGACY2"}"
  fi
}

state_paths_json() {
  cat <<EOF
{
  "state_dir": "$(json_escape "$STATE_ROOT")",
  "tool_health_json": "$(json_escape "${STATE_ROOT}/tool-health.json")",
  "tool_health_lines": "$(json_escape "${STATE_ROOT}/tool-health.lines")",
  "audit_daily_latest": "$(json_escape "${STATE_ROOT}/audit/daily/latest.json")",
  "audit_weekly_latest": "$(json_escape "${STATE_ROOT}/audit/weekly/latest.json")",
  "legacy_state_roots": [
    "$(json_escape "$STATE_ROOT_LEGACY1")",
    "$(json_escape "$STATE_ROOT_LEGACY2")"
  ]
}
EOF
}

json_list() {
  if [[ "$#" -eq 0 ]]; then
    printf '%s\n' "[]"
    return
  fi

  local out="["
  local first=1
  local entry
  for entry in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      out+="\"$(json_escape "$entry")\""
      first=0
    else
      out+=",\"$(json_escape "$entry")\""
    fi
  done
  out+="]"
  printf '%s' "$out"
}

run_json_command() {
  local out_ref="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  local rc=$?
  printf -v "$out_ref" '%s' "$(cat "$tmp")"
  rm -f "$tmp"
  set -e
  return $rc
}

extract_field() {
  local payload="$1"
  local field="$2"
  printf '%s' "$payload" | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([a-zA-Z0-9_:-]*\\)\".*/\\1/p"
}

uninstall() {
  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"

  local overall_ok=true
  local reason_code="ok"
  local next_action="noop"
  local -a targets=(
    "${STATE_ROOT}"
    "${HOME}/.config/fleet-sync"
    "${HOME}/.cache/fleet-sync"
    "${HOME}/.dx-state/fleet-link"
    "$STATE_ROOT_LEGACY1"
    "$STATE_ROOT_LEGACY2"
  )
  local -a actions=()
  local -a failures=()

  local target
  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      actions+=("missing_ok:${target}")
      continue
    fi
    if rm -rf "$target" >/dev/null 2>&1; then
      actions+=("removed:${target}")
    else
      actions+=("failed_remove:${target}")
      failures+=("failed_remove:${target}")
      overall_ok=false
    fi
  done

  if [[ "$overall_ok" == "false" ]]; then
    reason_code="partial_failure"
    next_action="rerun"
  fi

  local reason_codes
  if [[ "$overall_ok" == "false" ]]; then
    reason_codes='["partial_failure","partial_uninstall_remediation_required"]'
  else
    reason_codes='["uninstall_complete"]'
  fi

  local actions_json="[]"
  local failures_json="[]"
  if [[ ${#actions[@]} -gt 0 ]]; then
    actions_json="$(json_list "${actions[@]}")"
  fi
  if [[ ${#failures[@]} -gt 0 ]]; then
    failures_json="$(json_list "${failures[@]}")"
  fi

  local out
  out="$(cat <<EOF
{
  "mode": "uninstall",
  "generated_at": "$(json_escape "$timestamp")",
  "generated_at_epoch": $epoch,
  "overall_ok": $overall_ok,
  "reason_code": "$(json_escape "$reason_code")",
  "next_action": "$(json_escape "$next_action")",
  "reason_codes": $reason_codes,
  "summary": {
    "actions_attempted": ${#actions[@]},
    "errors": ${#failures[@]},
    "manifest_present": $([[ -f "$MANIFEST_PATH" ]] && echo true || echo false)
  },
  "actions": $actions_json,
  "failures": $failures_json,
  "state_paths": $(state_paths_json),
  "remediation_hints": [
    "Run dx-fleet-install.sh --uninstall --state-dir $(json_escape "$STATE_ROOT") again for remaining paths"
  ]
}
EOF
)"

  write_atomic "${STATE_ROOT}/uninstall.json" "$out"
  printf '%s\n' "$out"
  if [[ "$overall_ok" == "true" ]]; then
    return 0
  fi
  return 2
}

run_install_or_check() {
  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"

  mkdir -p "$STATE_ROOT"

  local -a checks=()
  local -a reason_codes=("install_suite_started")
  local overall_ok=true
  local reason_code="install_complete"
  local next_action="noop"
  local fail_count=0

  local fleet_check_out=""
  local tools_check_out=""
  local check_status="red"
  local tools_status="red"
  local check_rc=0
  local tools_rc=0

  if run_json_command fleet_check_out "${SCRIPT_DIR}/dx-fleet-check.sh" --json --state-dir "$STATE_ROOT"; then
    check_rc=0
  else
    check_rc=$?
  fi
  if [[ "$check_rc" -eq 0 ]]; then
    check_status="$(extract_field "$fleet_check_out" "fleet_status")"
    [[ -z "$check_status" ]] && check_status="unknown"
  else
    check_status="$(extract_field "$fleet_check_out" "fleet_status")"
    [[ -z "$check_status" ]] && check_status="red"
  fi
  checks+=("{\"id\":\"fleet.v2.2.fleet_check\",\"status\":\"$check_status\",\"severity\":\"medium\",\"details\":\"dx-fleet-check --json --state-dir $(json_escape "$STATE_ROOT")\",\"next_action\":\"dx-fleet-repair --json\"}")
  if [[ "$check_rc" -ne 0 || "$check_status" == "red" || "$check_status" == "unknown" ]]; then
    overall_ok=false
    next_action="rerun"
    reason_codes+=("fleet_check_failed")
  else
    reason_codes+=("fleet_check_pass")
  fi

  if run_json_command tools_check_out "${SCRIPT_DIR}/dx-mcp-tools-sync.sh" --check --json --state-dir "$STATE_ROOT"; then
    tools_rc=0
  else
    tools_rc=$?
  fi
  if [[ "$tools_rc" -eq 0 ]]; then
    tools_status="$(extract_field "$tools_check_out" "overall")"
    [[ -z "$tools_status" ]] && tools_status="unknown"
  else
    tools_status="$(extract_field "$tools_check_out" "overall")"
    [[ -z "$tools_status" ]] && tools_status="red"
  fi
  checks+=("{\"id\":\"fleet.v2.2.mcp_tools\",\"status\":\"$tools_status\",\"severity\":\"medium\",\"details\":\"dx-mcp-tools-sync --check --json --state-dir $(json_escape "$STATE_ROOT")\",\"next_action\":\"dx-mcp-tools-sync --repair --state-dir $(json_escape "$STATE_ROOT") --json\"}")
  if [[ "$tools_rc" -ne 0 || "$tools_status" == "red" || "$tools_status" == "yellow" || "$tools_status" == "unknown" ]]; then
    overall_ok=false
    next_action="rerun"
    reason_codes+=("mcp_tools_sync_failed")
  else
    reason_codes+=("mcp_tools_sync_pass")
  fi

  if [[ "$overall_ok" == "false" ]]; then
    fail_count=1
  fi

  [[ "$overall_ok" == "true" ]] && reason_codes+=("install_complete") || reason_codes+=("install_partial")
  if [[ "$overall_ok" == "true" ]]; then
    reason_code="install_complete"
  else
    reason_code="install_partial"
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
  for row in "${reason_codes[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      reasons_json+="\"$(json_escape "$row")\""
      first=0
    else
      reasons_json+=",\"$(json_escape "$row")\""
    fi
  done
  reasons_json+="]"

  local out
  out="$(cat <<EOF
{
  "mode": "${MODE}",
  "generated_at": "$(json_escape "$timestamp")",
  "generated_at_epoch": $epoch,
  "overall_ok": $overall_ok,
  "reason_code": "$(json_escape "$reason_code")",
  "next_action": "$(json_escape "$next_action")",
  "reason_codes": $reasons_json,
  "checks": $checks_json,
  "summary": {
    "fleet_check_status": "$(json_escape "$check_status")",
    "mcp_tools_sync_status": "$(json_escape "$tools_status")",
    "fail_count": $fail_count,
    "manifest_present": $([[ -f "$MANIFEST_PATH" ]] && echo true || echo false)
  },
  "state_paths": $(state_paths_json),
  "remediation_hints": [
    "Run: dx-fleet-check --json --state-dir $(json_escape "$STATE_ROOT")",
    "Run: dx-fleet-repair --json --state-dir $(json_escape "$STATE_ROOT")"
  ]
}
EOF
)"
  if [[ "$MODE" == "install" ]]; then
    write_atomic "${STATE_ROOT}/install.json" "$out"
  fi
  printf '%s\n' "$out"
  if [[ "$overall_ok" == "true" ]]; then
    return 0
  fi
  return 2
}

parse_args "$@"
load_manifest_roots
if [[ "$MODE" == "uninstall" ]]; then
  uninstall
  exit $?
fi

run_install_or_check
exit $?
