#!/usr/bin/env bash
#
# dx-audit.sh
#
# Fleet audit wrapper over dx-fleet-check for daily/weekly modes.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
STATE_ROOT_LEGACY1="${HOME}/.dx-state/fleet-sync"
STATE_ROOT_LEGACY2="${HOME}/.dx-state/fleet_sync"

MODE="weekly"
OUTPUT_SLACK=0
STATE_ONLY=0
SLACK_CHANNEL="#fleet-events"
SLACK_POST_ON_GREEN=true

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

usage() {
  cat <<'USAGE'
Usage:
  dx-audit.sh --daily|--weekly [--state-dir PATH] [--json] [--slack] [--state-only]
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --daily)
        MODE="daily"
        shift
        ;;
      --weekly)
        MODE="weekly"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        shift 2
        ;;
      --json|--json-only)
        shift
        ;;
      --slack)
        OUTPUT_SLACK=1
        shift
        ;;
      --state-only)
        STATE_ONLY=1
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

load_manifest() {
  [[ -f "$MANIFEST_PATH" ]] || return 0
  local vals
  vals="$(python3 - <<'PY' "$MANIFEST_PATH" 2>/dev/null || true
import sys, yaml
p=sys.argv[1]
try:
    data=yaml.safe_load(open(p, 'r', encoding='utf-8')) or {}
except Exception:
    raise SystemExit(0)
a=(data.get('audit') or {})
sl=(a.get('slack') or {})
print(sl.get('channel',''))
print(str(sl.get('post_on_green', True)).lower())
legacy=data.get('legacy_state_roots') or []
print(legacy[0] if len(legacy)>0 else '')
print(legacy[1] if len(legacy)>1 else '')
PY
)"
  if [[ -n "$vals" ]]; then
    local i=0 line
    while IFS= read -r line; do
      case "$i" in
        0)
          [[ -n "$line" ]] && SLACK_CHANNEL="$line"
          ;;
        1)
          [[ "$line" == "false" ]] && SLACK_POST_ON_GREEN=false
          ;;
        2)
          [[ -n "$line" ]] && STATE_ROOT_LEGACY1="${line/#\~\//$HOME/}"
          ;;
        3)
          [[ -n "$line" ]] && STATE_ROOT_LEGACY2="${line/#\~\//$HOME/}"
          ;;
      esac
      i=$((i + 1))
    done <<<"$vals"
  fi
}

render_slack_text() {
  local fleet_status="$1"
  local pass="$2"
  local warn="$3"
  local fail="$4"
  local unknown="$5"
  local hosts_failed="$6"

  local line
  line="🛰️ dx-audit ${MODE}: ${fleet_status}. checks pass=${pass} warn=${warn} fail=${fail} unknown=${unknown} hosts_failed=${hosts_failed}."
  if [[ "$fleet_status" == "green" ]]; then
    if [[ "$SLACK_POST_ON_GREEN" == "true" ]]; then
      line+=" ✅ no action needed"
    else
      line+=" no action needed"
    fi
  elif [[ "$fleet_status" == "yellow" ]]; then
    line+=" ⚠️ run: dx-fleet repair --json"
  else
    line+=" ❗ remediation required: dx-fleet repair --json"
  fi
  printf '%s' "$line"
}

artifact_paths_json() {
  local latest history
  if [[ "$MODE" == "weekly" ]]; then
    latest="${STATE_ROOT}/audit/weekly/latest.json"
    history="${STATE_ROOT}/audit/weekly/history"
  else
    latest="${STATE_ROOT}/audit/daily/latest.json"
    history="${STATE_ROOT}/audit/daily/history"
  fi
  cat <<EOF_JSON
{
  "audit_root":"${STATE_ROOT}",
  "tool_health_json":"${STATE_ROOT}/tool-health.json",
  "tool_health_lines":"${STATE_ROOT}/tool-health.lines",
  "audit_latest":"${latest}",
  "audit_history":"${history}",
  "legacy_state_roots":["${STATE_ROOT_LEGACY1}","${STATE_ROOT_LEGACY2}"]
}
EOF_JSON
}

save_artifact() {
  local payload="$1"
  local latest history_dir history_file
  if [[ "$MODE" == "weekly" ]]; then
    latest="${STATE_ROOT}/audit/weekly/latest.json"
    history_dir="${STATE_ROOT}/audit/weekly/history"
    history_file="${history_dir}/$(date -u +%G-%V).json"
  else
    latest="${STATE_ROOT}/audit/daily/latest.json"
    history_dir="${STATE_ROOT}/audit/daily/history"
    history_file="${history_dir}/$(date -u +%Y-%m-%d).json"
  fi
  mkdir -p "$history_dir"
  write_atomic "$latest" "$payload"
  write_atomic "$history_file" "$payload"
}

main() {
  parse_args "$@"
  load_manifest

  local check_payload="" check_rc=0
  if check_payload="$(${SCRIPT_DIR}/dx-fleet-check.sh --mode "$MODE" --json --state-dir "$STATE_ROOT" 2>/dev/null)"; then
    check_rc=0
  else
    check_rc=$?
  fi

  if [[ -z "$check_payload" ]] || ! command -v jq >/dev/null 2>&1 || ! printf '%s' "$check_payload" | jq -e '.mode and .fleet_status and .summary and .hosts and .checks and .state_paths' >/dev/null 2>&1; then
    local fail_payload
    fail_payload="$(cat <<EOF_JSON
{
  "mode":"$MODE",
  "generated_at":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "generated_at_epoch":$(date -u +%s),
  "fleet_status":"red",
  "summary":{"pass":0,"yellow":0,"red":1,"unknown":0,"hosts_checked":0,"hosts_failed":1},
  "hosts":[],
  "checks":[{"id":"fleet.v2.2.audit_payload","host":"local","status":"fail","severity":"high","details":"invalid dx-fleet-check payload"}],
  "repair_hints":[{"host":"local","check_id":"fleet.v2.2.audit_payload","command":"dx-fleet check --mode $MODE --json"}],
  "reason_codes":["audit_payload_invalid"],
  "state_paths":$(artifact_paths_json),
  "slack_channel":"$(json_escape "$SLACK_CHANNEL")",
  "slack_message":"$(json_escape "🛰️ dx-audit ${MODE}: red. checks pass=0 warn=0 fail=1 unknown=0 hosts_failed=1. ❗ remediation required: dx-fleet repair --json")"
}
EOF_JSON
)"
    [[ "$STATE_ONLY" -eq 0 ]] && save_artifact "$fail_payload"
    if [[ "$OUTPUT_SLACK" -eq 1 ]]; then
      printf '%s\n' "$(printf '%s' "$fail_payload" | jq -r '.slack_message')"
    else
      printf '%s\n' "$fail_payload"
    fi
    exit 2
  fi

  local pass warn fail unknown hosts_checked hosts_failed fleet_status
  pass="$(printf '%s' "$check_payload" | jq -r '.summary.checks.pass // 0')"
  warn="$(printf '%s' "$check_payload" | jq -r '.summary.checks.warn // 0')"
  fail="$(printf '%s' "$check_payload" | jq -r '.summary.checks.fail // 0')"
  unknown="$(printf '%s' "$check_payload" | jq -r '.summary.checks.unknown // 0')"
  hosts_checked="$(printf '%s' "$check_payload" | jq -r '.summary.hosts_checked // 0')"
  hosts_failed="$(printf '%s' "$check_payload" | jq -r '.summary.hosts_failed // 0')"
  fleet_status="$(printf '%s' "$check_payload" | jq -r '.fleet_status // "unknown"')"

  local slack_message
  slack_message="$(render_slack_text "$fleet_status" "$pass" "$warn" "$fail" "$unknown" "$hosts_failed")"

  local payload
  payload="$(printf '%s' "$check_payload" | jq -c \
    --arg mode "$MODE" \
    --argjson pass "$pass" \
    --argjson warn "$warn" \
    --argjson fail "$fail" \
    --argjson unknown "$unknown" \
    --argjson hosts_checked "$hosts_checked" \
    --argjson hosts_failed "$hosts_failed" \
    --arg state_paths "$(artifact_paths_json | tr -d '\n')" \
    --arg slack_channel "$SLACK_CHANNEL" \
    --arg slack_message "$slack_message" \
    '.mode=$mode
     | .summary={pass:$pass,yellow:$warn,red:$fail,unknown:$unknown,hosts_checked:$hosts_checked,hosts_failed:$hosts_failed}
     | .state_paths=($state_paths | fromjson)
     | .slack_channel=$slack_channel
     | .slack_message=$slack_message')"

  payload="$(printf '%s' "$payload" | jq '.')"

  [[ "$STATE_ONLY" -eq 0 ]] && save_artifact "$payload"

  if [[ "$OUTPUT_SLACK" -eq 1 ]]; then
    printf '%s\n' "$slack_message"
  else
    printf '%s\n' "$payload"
  fi

  case "$fleet_status" in
    red) exit 2 ;;
    yellow) exit 1 ;;
    *) exit "$check_rc" ;;
  esac
}

main "$@"
