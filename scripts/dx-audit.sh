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
CI_AUDIT_FAILED_LIMIT="${DX_GH_FAILURE_AUDIT_FAILED_LIMIT:-8}"
CI_AUDIT_RECENT_LIMIT="${DX_GH_FAILURE_AUDIT_RECENT_LIMIT:-40}"

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
  local ci_active="$7"
  local ci_repo_errors="$8"
  local ci_top_url="$9"

  local line
  line="🛰️ dx-audit ${MODE}: ${fleet_status}. checks pass=${pass} warn=${warn} fail=${fail} unknown=${unknown} hosts_failed=${hosts_failed}; ci_active=${ci_active} ci_repo_errors=${ci_repo_errors}."
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
  if [[ "${ci_active}" -gt 0 && -n "$ci_top_url" ]]; then
    line+=" | top_ci=${ci_top_url}"
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

status_rank() {
  case "$1" in
    green) echo 0 ;;
    yellow) echo 1 ;;
    red) echo 2 ;;
    *) echo 1 ;;
  esac
}

max_status() {
  local a="$1"
  local b="$2"
  if [[ "$(status_rank "$a")" -ge "$(status_rank "$b")" ]]; then
    echo "$a"
  else
    echo "$b"
  fi
}

collect_ci_failure_groups_json() {
  local stderr_file output rc stderr_trimmed
  stderr_file="$(mktemp)"
  set +e
  output="$("${SCRIPT_DIR}/dx-gh-actions-audit.py" --json --failed-run-limit "$CI_AUDIT_FAILED_LIMIT" --recent-run-limit "$CI_AUDIT_RECENT_LIMIT" 2>"$stderr_file")"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]] && command -v jq >/dev/null 2>&1 && printf '%s' "$output" | jq -e '.summary and .active_groups and .repo_errors' >/dev/null 2>&1; then
    rm -f "$stderr_file"
    printf '%s' "$output"
    return 0
  fi

  stderr_trimmed="$(tr '\n' ' ' < "$stderr_file" | sed 's/[[:space:]]\+/ /g' | sed 's/"/\\"/g' | cut -c1-600)"
  rm -f "$stderr_file"
  cat <<EOF_JSON
{
  "generated_at":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "repos":[],
  "repo_errors":[
    {
      "repo":"all",
      "stage":"collector_invocation",
      "error_code":"collector_failed",
      "message":"dx-gh-actions-audit invocation failed",
      "stderr":"${stderr_trimmed}"
    }
  ],
  "groups":[],
  "active_groups":[],
  "stale_groups":[],
  "summary":{
    "repos_total":0,
    "repos_ok":0,
    "repos_error":1,
    "total_groups":0,
    "active_groups":0,
    "stale_groups":0
  }
}
EOF_JSON
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

  local ci_payload ci_active ci_repo_errors ci_status ci_top_url overall_status
  ci_payload="$(collect_ci_failure_groups_json)"
  ci_active="$(printf '%s' "$ci_payload" | jq -r '.summary.active_groups // 0')"
  ci_repo_errors="$(printf '%s' "$ci_payload" | jq -r '.summary.coverage_repo_errors // .summary.repos_error // 0')"
  ci_top_url="$(printf '%s' "$ci_payload" | jq -r '.active_groups[0].latest_failure.run_url // ""')"
  ci_status="green"
  if [[ "$ci_active" -gt 0 ]]; then
    ci_status="red"
  elif [[ "$ci_repo_errors" -gt 0 ]]; then
    ci_status="yellow"
  fi
  overall_status="$(max_status "$fleet_status" "$ci_status")"

  local slack_message
  slack_message="$(render_slack_text "$overall_status" "$pass" "$warn" "$fail" "$unknown" "$hosts_failed" "$ci_active" "$ci_repo_errors" "$ci_top_url")"

  local payload
  local ci_check_status ci_check_severity ci_check_details
  ci_check_status="pass"
  ci_check_severity="low"
  ci_check_details="active_groups=${ci_active} repo_errors=${ci_repo_errors}"
  if [[ "$ci_active" -gt 0 ]]; then
    ci_check_status="fail"
    ci_check_severity="high"
    ci_check_details="${ci_check_details} top_url=${ci_top_url}"
  elif [[ "$ci_repo_errors" -gt 0 ]]; then
    ci_check_status="warn"
    ci_check_severity="medium"
  fi

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
    --arg overall_status "$overall_status" \
    --arg ci_payload "$(printf '%s' "$ci_payload" | tr -d '\n')" \
    --arg ci_check_status "$ci_check_status" \
    --arg ci_check_severity "$ci_check_severity" \
    --arg ci_check_details "$ci_check_details" \
    --arg ci_top_url "$ci_top_url" \
    '.mode=$mode
     | .summary={pass:$pass,yellow:$warn,red:$fail,unknown:$unknown,hosts_checked:$hosts_checked,hosts_failed:$hosts_failed}
     | .state_paths=($state_paths | fromjson)
     | .fleet_status=$overall_status
     | .github_actions=($ci_payload | fromjson)
     | .summary.github_actions={
         active_groups: ((.github_actions.summary.active_groups // 0) | tonumber),
         stale_groups: ((.github_actions.summary.stale_groups // 0) | tonumber),
         repo_errors: ((.github_actions.summary.coverage_repo_errors // .github_actions.summary.repos_error // 0) | tonumber),
         top_run_url: $ci_top_url
       }
     | .checks=((.checks // []) + [{
         id:"github.actions.cross_repo_failures",
         host:"github",
         status:$ci_check_status,
         severity:$ci_check_severity,
         details:$ci_check_details
       }])
     | .reason_codes=((.reason_codes // []) +
         (if ((.github_actions.summary.active_groups // 0) | tonumber) > 0 then ["github_actions_active_failures"] else [] end) +
         (if ((.github_actions.summary.coverage_repo_errors // .github_actions.summary.repos_error // 0) | tonumber) > 0 then ["github_actions_audit_partial"] else [] end))
     | .slack_channel=$slack_channel
     | .slack_message=$slack_message')"

  payload="$(printf '%s' "$payload" | jq '.')"

  [[ "$STATE_ONLY" -eq 0 ]] && save_artifact "$payload"

  if [[ "$OUTPUT_SLACK" -eq 1 ]]; then
    printf '%s\n' "$slack_message"
  else
    printf '%s\n' "$payload"
  fi

  case "$overall_status" in
    red) exit 2 ;;
    yellow) exit 1 ;;
    *) exit "$check_rc" ;;
  esac
}

main "$@"
