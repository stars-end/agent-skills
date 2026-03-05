#!/usr/bin/env bash
#
# dx-fleet-check.sh
#
# Fleet health probe for Fleet Sync runtime checks.
# Emits JSON output and writes canonical state artifacts.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
STATE_JSON="${STATE_ROOT}/tool-health.json"
STATE_LINES="${STATE_ROOT}/tool-health.lines"
MCP_TOOLS_SYNC_JSON="${STATE_ROOT}/mcp-tools-sync.json"
OUTPUT_FORMAT="text"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

DAILY_CHECK_IDS=(
  beads_dolt
  tool_mcp_health
  required_service_health
  op_auth_readiness
  alerts_transport_readiness
)

STATE_ROOT_LEGACY1="${HOME}/.dx-state/fleet-sync"
STATE_ROOT_LEGACY2="${HOME}/.dx-state/fleet_sync"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
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

fleet_local_host() {
  if [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    case "${CANONICAL_HOST_KEY}" in
      macmini|homedesktop-wsl|epyc6|epyc12)
        echo "${CANONICAL_HOST_KEY}"
        return 0
        ;;
    esac
  fi

  local current_host
  current_host="$(hostname -s 2>/dev/null | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')"
  if [[ "$current_host" =~ macmini ]] || [[ "$current_host" =~ mac[-]?mini ]]; then
    echo "macmini"
  elif [[ "$current_host" =~ homedesktop ]]; then
    echo "homedesktop-wsl"
  elif [[ "$current_host" =~ epyc12 ]]; then
    echo "epyc12"
  elif [[ "$current_host" =~ epyc ]]; then
    echo "epyc6"
  elif [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    echo "${CANONICAL_HOST_KEY}"
  else
    echo "local"
  fi
}

normalize_host_key() {
  local target="$1"
  target="${target##*/}"
  target="${target%%:*}"
  printf '%s' "${target##*@}"
}

canonical_host_to_target() {
  local host_key="$1"
  local entry
  local entry_host
  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      entry_host="$(normalize_host_key "$entry")"
      if [[ "$entry_host" == "$host_key" ]]; then
        printf '%s\n' "${entry%%:*}"
        return 0
      fi
    done
  fi
  if [[ "$host_key" == *"@"* ]]; then
    printf '%s\n' "$host_key"
    return 0
  fi
  if [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    echo "${USER:-fengning}@$host_key"
    return 0
  fi
  echo "${USER:-fengning}@$host_key"
}

is_member() {
  local target="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$target" ]] && return 0
  done
  return 1
}

normalize_status() {
  local status="$1"
  case "$status" in
    pass|green)
      echo pass
      ;;
    warn|yellow|caution)
      echo warn
      ;;
    fail|red)
      echo fail
      ;;
    *)
      echo unknown
      ;;
  esac
}

required_tools_for_host() {
  local host_key="$1"
  case "$host_key" in
    macmini|homedesktop-wsl|macos)
      printf '%s\n' "bd" "gh" "git" "railway" "op" "mise" "ru"
      ;;
    *)
      printf '%s\n' "bd" "gh" "git" "railway" "op" "mise"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        STATE_JSON="${STATE_ROOT}/tool-health.json"
        STATE_LINES="${STATE_ROOT}/tool-health.lines"
        MCP_TOOLS_SYNC_JSON="${STATE_ROOT}/mcp-tools-sync.json"
        shift 2
        ;;
      --help|-h)
        cat <<'EOF'
Usage: dx-fleet-check.sh [--json] [--state-dir PATH]
  --json       emit machine-readable JSON
  --state-dir  override state root (default: ~/.dx-state/fleet)
EOF
        exit 0
        ;;
      *)
        echo "Unknown flag: $1" >&2
        exit 1
        ;;
    esac
  done
}

collect_hosts() {
  local local_host="$1"
  local -a raw=()
  local -a seen=()
  local host
  local entry

  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      raw+=("$(normalize_host_key "$entry")")
    done
  else
    raw=("macmini" "homedesktop-wsl" "epyc6" "epyc12")
  fi

  echo "$local_host"
  seen+=("$local_host")
  for host in "${raw[@]}"; do
    if is_member "$host" "${seen[@]}"; then
      continue
    fi
    if [[ -z "$host" ]]; then
      continue
    fi
    seen+=("$host")
    echo "$host"
  done
}

host_role_for_check() {
  local host="$1"
  case "$host" in
    *macmini* )
      echo "macmini"
      ;;
    *homedesktop* )
      echo "homedesktop-wsl"
      ;;
    *epyc12* )
      echo "epyc12"
      ;;
    *epyc6* )
      echo "epyc6"
      ;;
    * )
      echo "$CANONICAL_HOST_KEY"
      ;;
  esac
}

get_mcp_tool_health_payload() {
  local payload=""
  if [[ -f "$MCP_TOOLS_SYNC_JSON" ]]; then
    payload="$(cat "$MCP_TOOLS_SYNC_JSON" 2>/dev/null || true)"
  fi
  if [[ -z "$payload" ]] && [[ -x "$SCRIPT_DIR/dx-mcp-tools-sync.sh" ]]; then
    payload="$("$SCRIPT_DIR/dx-mcp-tools-sync.sh" --check --json --state-dir "$STATE_ROOT" 2>/dev/null || true)"
  fi
  printf '%s' "$payload"
}

mcp_tools_sync_status() {
  local payload="$1"
  local status="unknown"
  local severity="medium"
  local details="dx-mcp-tools-sync state unavailable"
  local fail_count
  local warn_count
  local missing

  if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
    fail_count="$(printf '%s' "$payload" | jq -r '.summary.fail // 0' 2>/dev/null || printf '0')"
    warn_count="$(printf '%s' "$payload" | jq -r '.summary.warn // 0' 2>/dev/null || printf '0')"

    if [[ "$fail_count" =~ ^[0-9]+$ ]] && [[ "$fail_count" -gt 0 ]]; then
      status="fail"
      details="$(printf '%s' "$payload" | jq -r '[.files[]? | select(.status != "pass") | .path] | join(", ")' 2>/dev/null | sed 's/^$/missing mcp artifacts/')"
    elif [[ "$warn_count" =~ ^[0-9]+$ ]] && [[ "$warn_count" -gt 0 ]]; then
      status="fail"
      details="$(printf '%s' "$payload" | jq -r '[.files[]? | select(.status != "pass") | .path] | join(", ")' 2>/dev/null | sed 's/^$/missing mcp artifacts/')"
    else
      status="pass"
      severity="low"
      details="MCP tool state synchronized"
    fi
  elif [[ -n "$payload" ]]; then
    status="unknown"
    details="dx-mcp-tools-sync state present but unparsable"
  fi

  printf '%s|%s|%s' "$status" "$severity" "$details"
}

build_missing_rows() {
  local host="$1"
  local reason="$2"
  local status="fail"
  local severity="medium"
  local details
  local -a rows=()
  local pass_count=0
  local warn_count=0
  local fail_count=0
  local unknown_count=0
  local first=1
  local row
  local check_id
  local escaped_reason

  escaped_reason="$(json_escape "$reason")"
  for check_id in "${DAILY_CHECK_IDS[@]}"; do
    details="Fleet Sync snapshot missing for host '$host': $reason"
    row="{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$escaped_reason\"}"
    rows+=("$row")
    fail_count=$((fail_count + 1))
  done

  local rows_json="["
  first=1
  for row in "${rows[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      rows_json+="$row"
      first=0
    else
      rows_json+=",$row"
    fi
  done
  rows_json+="]"

  echo "red|$pass_count|$warn_count|$fail_count|$unknown_count|$rows_json|$host"
}

snapshot_rows_for_host() {
  local source_file="$1"
  local host="$2"

  local -a rows=()
  local -a seen=()
  local pass_count=0
  local warn_count=0
  local fail_count=0
  local unknown_count=0
  local row
  local row_check_id
  local row_status
  local row_severity
  local row_details
  local raw_status
  local raw_id
  local raw_details
  local raw_severity
  local had_rows=0
  local first=1
  local rows_json
  local overall="green"
  local status
  local check_id

  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r raw_id raw_status raw_severity raw_details || [[ -n "${raw_id}" ]]; do
      [[ -z "${raw_id:-}" ]] && continue
      raw_id="${raw_id#fleet.v2.2.}"
      if ! is_member "$raw_id" "${DAILY_CHECK_IDS[@]}"; then
        continue
      fi
      had_rows=1
      row_status="$(normalize_status "$raw_status")"
      row_id="$raw_id"
      row_severity="${raw_severity:-low}"
      row_details="$(json_escape "$raw_details")"
      row="{\"id\":\"$row_id\",\"status\":\"$row_status\",\"severity\":\"$row_severity\",\"details\":\"$row_details\"}"
      rows+=("$row")
      if ! is_member "$raw_id" "${seen[@]}"; then
        seen+=("$raw_id")
      fi

      case "$row_status" in
        pass)
          pass_count=$((pass_count + 1))
          ;;
        warn)
          warn_count=$((warn_count + 1))
          ;;
        fail)
          fail_count=$((fail_count + 1))
          ;;
        *)
          unknown_count=$((unknown_count + 1))
          ;;
      esac
    done < <(jq -r --arg target "$host" '
      .hosts[]?
      | ( .host // "local") as $raw_host
      | (($raw_host | split("@")[-1]) as $host_name | select($host_name == $target))
      | .checks[]? as $check
      | [($check.id // ""), ($check.status // "unknown"), ($check.severity // "low"), (($check.details // "") | gsub("\t"; " ") | gsub("\n"; " "))] | @tsv
    ' "$source_file")
  elif command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r raw_id raw_status raw_severity raw_details || [[ -n "${raw_id}" ]]; do
      [[ -z "${raw_id:-}" ]] && continue
      raw_id="${raw_id#fleet.v2.2.}"
      if ! is_member "$raw_id" "${DAILY_CHECK_IDS[@]}"; then
        continue
      fi
      had_rows=1
      row_status="$(normalize_status "$raw_status")"
      row_id="$raw_id"
      row_severity="${raw_severity:-low}"
      row_details="$(json_escape "$raw_details")"
      row="{\"id\":\"$row_id\",\"status\":\"$row_status\",\"severity\":\"$row_severity\",\"details\":\"$row_details\"}"
      rows+=("$row")
      if ! is_member "$raw_id" "${seen[@]}"; then
        seen+=("$raw_id")
      fi

      case "$row_status" in
        pass)
          pass_count=$((pass_count + 1))
          ;;
        warn)
          warn_count=$((warn_count + 1))
          ;;
        fail)
          fail_count=$((fail_count + 1))
          ;;
        *)
          unknown_count=$((unknown_count + 1))
          ;;
      esac
    done < <(
      python3 - "$source_file" "$host" <<'PY'
import json
import sys

source_file, target_host = sys.argv[1], sys.argv[2]
try:
    with open(source_file, "r", encoding="utf-8", errors="ignore") as fp:
        payload = json.load(fp)
except Exception:
    sys.exit(1)

for host_obj in payload.get("hosts", []):
    raw_host = host_obj.get("host", "local")
    raw_host = str(raw_host)
    normalized = raw_host.split("@")[-1]
    if normalized != target_host:
        continue
    for check in host_obj.get("checks", []):
        raw = [
            str(check.get("id", "")),
            str(check.get("status", "unknown")),
            str(check.get("severity", "low")),
            str(check.get("details", "")),
        ]
        print("\t".join([part.replace("\t", " ").replace("\n", " ") for part in raw]))
PY
    )
  else
    build_missing_rows "$host" "No JSON parser available for remote Fleet Sync state"
    return 0
  fi

  for check_id in "${DAILY_CHECK_IDS[@]}"; do
    if is_member "$check_id" "${seen[@]}"; then
      continue
    fi
    row_status="fail"
    row=("{\"id\":\"$check_id\",\"status\":\"$row_status\",\"severity\":\"medium\",\"details\":\"missing daily check '$check_id' in Fleet Sync snapshot\"}")
    rows+=("${row[@]}")
    seen+=("$check_id")
    fail_count=$((fail_count + 1))
  done

  if [[ "$had_rows" -eq 0 && "${#rows[@]}" -eq 0 ]]; then
    build_missing_rows "$host" "Fleet Sync snapshot for host '$host' has no usable check rows"
    return 0
  fi

  if [[ "$fail_count" -gt 0 ]]; then
    overall="red"
  elif [[ "$warn_count" -gt 0 ]]; then
    overall="yellow"
  fi

  rows_json="["
  first=1
  for row in "${rows[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      rows_json+="$row"
      first=0
    else
      rows_json+=",$row"
    fi
  done
  rows_json+="]"

  echo "$overall|$pass_count|$warn_count|$fail_count|$unknown_count|$rows_json|$host"
}

collect_remote_snapshot_rows() {
  local host="$1"
  local target="$2"
  local -a candidates=()
  local -a home_roots=()
  local candidate
  local snapshot_json=""
  local payload_file
  local parsed
  local target_user

  target_user="${target%%@*}"
  if [[ -z "$target_user" || "$target_user" == "$target" ]]; then
    target_user="${USER:-fengning}"
  fi

  home_roots+=("$HOME")
  home_roots+=("/home/${target_user}")
  home_roots+=("/Users/${target_user}")

  candidates+=("${STATE_ROOT}/tool-health.json")
  candidates+=("${STATE_ROOT_LEGACY1}/tool-health.json")
  candidates+=("${STATE_ROOT_LEGACY2}/tool-health.json")

  local root
  for root in "${home_roots[@]}"; do
    candidates+=("${root}/.dx-state/fleet/tool-health.json")
    candidates+=("${root}/.dx-state/fleet-sync/tool-health.json")
    candidates+=("${root}/.dx-state/fleet_sync/tool-health.json")
  done

  for candidate in "${candidates[@]}"; do
    [[ -z "$candidate" ]] && continue
    local remote_file
    remote_file="$candidate"
    if [[ "$remote_file" == "$HOME"* ]]; then
      remote_file="${remote_file/#$HOME/"~"}"
    fi
    snapshot_json="$(ssh_canonical_vm "$target" "if [ -f $remote_file ]; then cat $remote_file; fi" 2>/dev/null || true)"
    if [[ -n "$snapshot_json" ]]; then
      payload_file="$(mktemp "${STATE_ROOT}/.remote-tool-health-XXXXXX")"
      printf '%s' "$snapshot_json" > "$payload_file"
      parsed="$(snapshot_rows_for_host "$payload_file" "$host")"
      rm -f "$payload_file"
      if [[ -n "$parsed" ]]; then
        printf '%s\n' "$parsed"
        return 0
      fi
    fi
  done
  return 1
}

build_check_rows() {
  local host="$1"
  local role="$2"
  local check_id
  local status severity details
  local pass_count=0
  local warn_count=0
  local fail_count=0
  local unknown_count=0
  local rows=()

  # 1) beads_dolt
  check_id="beads_dolt"
  status="pass"
  severity="low"
  details="Beads runtime data path present and accessible"
  if ! command -v bd >/dev/null 2>&1; then
    status="fail"
    severity="critical"
    details="bd not installed"
  elif [[ -z "${BEADS_DIR:-}" ]]; then
    status="fail"
    severity="high"
    details="BEADS_DIR unset"
  elif [[ ! -d "${BEADS_DIR}" ]]; then
    status="fail"
    severity="high"
    details="BEADS_DIR directory missing (${BEADS_DIR})"
  fi
  rows+=("{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$details")\"}")
  [[ "$status" == pass ]] && pass_count=$((pass_count+1)) || \
  [[ "$status" == warn ]] && warn_count=$((warn_count+1)) || \
  [[ "$status" == fail ]] && fail_count=$((fail_count+1)) || \
  unknown_count=$((unknown_count+1))

  # 2) tool_mcp_health
  check_id="tool_mcp_health"
  details="dx-mcp-tools-sync state unavailable"
  IFS='|' read -r status severity details <<< "$(mcp_tools_sync_status "$(get_mcp_tool_health_payload)")"
  rows+=("{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$details")\"}")
  [[ "$status" == pass ]] && pass_count=$((pass_count+1)) || \
  [[ "$status" == warn ]] && warn_count=$((warn_count+1)) || \
  [[ "$status" == fail ]] && fail_count=$((fail_count+1)) || \
  unknown_count=$((unknown_count+1))

  # 3) required_service_health
  check_id="required_service_health"
  details=""
  status="pass"
  severity="low"
  local missing_service=0
  local tool
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_service=$((missing_service+1))
    fi
  done < <(required_tools_for_host "$role")
  if [[ "$missing_service" -gt 0 ]]; then
    status="fail"
    severity="medium"
    details="required tools missing on host role '$role': $missing_service"
  fi
  rows+=("{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$details")\"}")
  [[ "$status" == pass ]] && pass_count=$((pass_count+1)) || \
  [[ "$status" == warn ]] && warn_count=$((warn_count+1)) || \
  [[ "$status" == fail ]] && fail_count=$((fail_count+1)) || \
  unknown_count=$((unknown_count+1))

  # 4) op_auth_readiness
  check_id="op_auth_readiness"
  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && command -v op >/dev/null 2>&1; then
    status="pass"
    severity="low"
    details="OP service-account token detected"
  elif command -v op >/dev/null 2>&1; then
    status="fail"
    severity="low"
    details="op installed but OP_SERVICE_ACCOUNT_TOKEN not set"
  else
    status="fail"
    severity="low"
    details="op CLI unavailable"
  fi
  rows+=("{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$details")\"}")
  [[ "$status" == pass ]] && pass_count=$((pass_count+1)) || \
  [[ "$status" == warn ]] && warn_count=$((warn_count+1)) || \
  [[ "$status" == fail ]] && fail_count=$((fail_count+1)) || \
  unknown_count=$((unknown_count+1))

  # 5) alerts_transport_readiness
  check_id="alerts_transport_readiness"
  if [[ -n "${SLACK_BOT_TOKEN:-}" ]] || [[ -n "${SLACK_APP_TOKEN:-}" ]] || [[ -n "${SLACK_MCP_XOXB_TOKEN:-}" ]] || [[ -n "${SLACK_MCP_XOXP_TOKEN:-}" ]] || [[ -n "${DX_SLACK_WEBHOOK:-}" ]] || [[ -n "${DX_ALERTS_WEBHOOK:-}" ]]; then
    status="pass"
    severity="low"
    details="deterministic Slack transport configured"
  else
    status="fail"
    severity="low"
    details="Slack transport token/webhook missing"
  fi
  rows+=("{\"id\":\"$check_id\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$details")\"}")
  [[ "$status" == pass ]] && pass_count=$((pass_count+1)) || \
  [[ "$status" == warn ]] && warn_count=$((warn_count+1)) || \
  [[ "$status" == fail ]] && fail_count=$((fail_count+1)) || \
  unknown_count=$((unknown_count+1))

  local rows_json="["
  local first=1
  for row in "${rows[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      rows_json+="$row"
      first=0
    else
      rows_json+=",${row}"
    fi
  done
  rows_json+="]"

  local overall="green"
  if [[ "$fail_count" -gt 0 ]]; then
    overall="red"
  elif [[ "$warn_count" -gt 0 ]]; then
    overall="yellow"
  fi

  echo "$overall|$pass_count|$warn_count|$fail_count|$unknown_count|$rows_json|$host"
}

parse_args "$@"

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
TIMESTAMP_EPOCH="$(date -u +%s)"
LOCAL_HOST="$(fleet_local_host)"
CANONICAL_ROLE="${CANONICAL_HOST_KEY:-$LOCAL_HOST}"

host_records=""
hosts_checked=0
hosts_failed=0
total_pass=0
total_warn=0
total_fail=0
total_unknown=0
first=1
overall="green"

for host in $(collect_hosts "$LOCAL_HOST"); do
  host_role="$(host_role_for_check "$host")"
  row_payload=""
  if [[ "$host" == "$LOCAL_HOST" ]]; then
    row_payload="$(build_check_rows "$host" "$host_role")"
  else
    remote_target="$(canonical_host_to_target "$host")"
    if ! row_payload="$(collect_remote_snapshot_rows "$host" "$remote_target")"; then
      row_payload="$(build_missing_rows "$host" "Unable to read Fleet Sync snapshot from $remote_target")"
    fi
  fi

  hosts_checked=$((hosts_checked + 1))
  IFS='|' read -r host_overall host_pass host_warn host_fail host_unknown host_rows _ <<EOF
$row_payload
EOF

  if [[ "$host_overall" == "red" ]]; then
    hosts_failed=$((hosts_failed + 1))
    overall="red"
  elif [[ "$host_overall" == "yellow" && "$overall" != "red" ]]; then
    overall="yellow"
  fi

  total_pass=$((total_pass + host_pass))
  total_warn=$((total_warn + host_warn))
  total_fail=$((total_fail + host_fail))
  total_unknown=$((total_unknown + host_unknown))

  record="{\"host\":\"$host\",\"overall\":\"$host_overall\",\"checks\":$host_rows}"
  if [[ "$first" -eq 1 ]]; then
    host_records+="$record"
    first=0
  else
    host_records+=",$record"
  fi

  if [[ "$host" == "$LOCAL_HOST" ]]; then
    local_message="local checks completed"
  fi
done

host_records="[${host_records}]"
summary_json="{\"hosts_checked\":$hosts_checked,\"hosts_failed\":$hosts_failed,\"checks\":{\"pass\":$total_pass,\"warn\":$total_warn,\"fail\":$total_fail,\"unknown\":$total_unknown}}"
state_paths_json="{\"tool_health_json\":\"${STATE_JSON}\",\"tool_health_lines\":\"${STATE_LINES}\",\"mcp_tools_sync_json\":\"${MCP_TOOLS_SYNC_JSON}\",\"audit_daily_latest\":\"${STATE_ROOT}/audit/daily/latest.json\",\"audit_weekly_latest\":\"${STATE_ROOT}/audit/weekly/latest.json\",\"legacy_state_roots\":[\"${STATE_ROOT_LEGACY1}\",\"${STATE_ROOT_LEGACY2}\"]}"
result_json="{\"mode\":\"check\",\"generated_at\":\"$TIMESTAMP\",\"generated_at_epoch\":$TIMESTAMP_EPOCH,\"fleet_status\":\"$overall\",\"summary\":$summary_json,\"hosts\":$host_records,\"checks\":[],\"repair_hints\":[],\"reason_codes\":[],\"state_paths\":$state_paths_json}"

text_lines="generated_at=$TIMESTAMP
generated_at_epoch=$TIMESTAMP_EPOCH
fleet_status=$overall
hosts_checked=$hosts_checked
hosts_failed=$hosts_failed
checks_pass=$total_pass
checks_warn=$total_warn
checks_fail=$total_fail
checks_unknown=$total_unknown"

write_atomic "$STATE_JSON" "$result_json"
write_atomic "$STATE_LINES" "$text_lines"

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  echo "$result_json"
else
  echo "🔍 DX Fleet Check"
  echo "-----------------"
  echo "$text_lines"
  echo ""
  if [[ -n "${local_message:-}" ]]; then
    echo "Local checks: $local_message"
  else
    echo "Local checks: skipped"
  fi
fi

if [[ "$overall" == "red" ]]; then
  exit 1
fi
exit 0
