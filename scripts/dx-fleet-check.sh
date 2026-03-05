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
OUTPUT_FORMAT="text"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

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
  else
    echo "local"
  fi
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
  local raw=()
  local host

  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      host="${entry%%:*}"
      raw+=("$host")
    done
  else
    raw=("macmini" "homedesktop-wsl" "epyc6" "epyc12")
  fi

  # deterministic local-first ordering
  echo "$local_host"
  for host in "${raw[@]}"; do
    [[ "$host" == "$local_host" ]] && continue
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
  details=""
  status="pass"
  severity="low"
  local missing=0
  local candidate
  local detail_parts=()
  for candidate in \
    "${HOME}/.claude/settings.json" \
    "${HOME}/.claude.json" \
    "${HOME}/.codex/config.toml" \
    "${HOME}/.opencode/config.json" \
    "${HOME}/.gemini/antigravity/mcp_config.json"; do
    if [[ ! -f "$candidate" ]]; then
      missing=$((missing+1))
      detail_parts+=("${candidate#"${HOME}/"}")
    fi
  done
  if [[ "$missing" -gt 0 ]]; then
    status="fail"
    severity="medium"
    details="canonical IDE artifacts missing: ${missing} (${detail_parts[*]})"
  fi
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
  hosts_checked=$((hosts_checked + 1))
  row_payload="$(build_check_rows "$host" "$host_role")"
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

state_paths_json="{\"tool_health_json\":\"${STATE_JSON}\",\"tool_health_lines\":\"${STATE_LINES}\",\"audit_daily_latest\":\"${STATE_ROOT}/audit/daily/latest.json\",\"audit_weekly_latest\":\"${STATE_ROOT}/audit/weekly/latest.json\",\"legacy_fleet_sync_dir\":[\"${HOME}/.dx-state/fleet-sync/tool-health.json\",\"${HOME}/.dx-state/fleet-sync/tool-health.lines\"]}"
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
