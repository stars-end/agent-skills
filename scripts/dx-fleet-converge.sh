#!/usr/bin/env bash
#
# dx-fleet-converge.sh
#
# Fleet-wide converge command for apply/check/repair across all canonical VMs.
# Returns non-zero if any host is red.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
OUTPUT_FORMAT="text"
ACTION="check"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

usage() {
  cat <<'EOF'
Usage:
  dx-fleet-converge.sh [--apply|--check|--repair] [--json] [--state-dir DIR]

Fleet-wide converge command for apply/check/repair across all canonical VMs.
Returns non-zero if any host is red.

Options:
  --apply    Converge tools + IDE configs from manifest
  --check    Drift detection only (default)
  --repair   Force re-apply convergence and verify
  --json     Output in JSON format
  --state-dir DIR   State directory (default: ~/.dx-state/fleet)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        ACTION="apply"
        shift
        ;;
      --check)
        ACTION="check"
        shift
        ;;
      --repair)
        ACTION="repair"
        shift
        ;;
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown flag: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

get_local_host() {
  if [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    echo "${CANONICAL_HOST_KEY}"
    return 0
  fi
  local current_host
  current_host="$(hostname -s 2>/dev/null | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')"
  if [[ "$current_host" =~ macmini ]]; then
    echo "macmini"
  elif [[ "$current_host" =~ homedesktop ]]; then
    echo "homedesktop-wsl"
  elif [[ "$current_host" =~ epyc12 ]]; then
    echo "epyc12"
  elif [[ "$current_host" =~ epyc6 ]]; then
    echo "epyc6"
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
  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      if [[ "$(normalize_host_key "$entry")" == "$host_key" ]]; then
        printf '%s\n' "${entry%%:*}"
        return 0
      fi
    done
  fi
  echo "${USER:-fengning}@${host_key}"
}

collect_hosts() {
  local local_host="$1"
  local -a hosts=()
  local entry host
  
  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      host="$(normalize_host_key "$entry")"
      [[ -n "$host" ]] && hosts+=("$host")
    done
  else
    hosts=(macmini homedesktop-wsl epyc6 epyc12)
  fi

  # Local host first
  echo "$local_host"
  local seen="$local_host"
  for host in "${hosts[@]}"; do
    [[ "$host" == "$local_host" ]] && continue
    if [[ " $seen " == *" $host "* ]]; then
      continue
    fi
    seen+=" $host"
    echo "$host"
  done
}

run_converge_local() {
  local action="$1"
  local script="$SCRIPT_DIR/dx-mcp-tools-sync.sh"
  
  if [[ ! -x "$script" ]]; then
    echo "ERROR: $script not found or not executable" >&2
    return 1
  fi
  
  "$script" --"$action" --json --state-dir "$STATE_ROOT" 2>&1
}

run_converge_remote() {
  local host="$1"
  local action="$2"
  local target
  target="$(canonical_host_to_target "$host")"
  
  local remote_script="~/agent-skills/scripts/dx-mcp-tools-sync.sh"
  local state_dir="\$HOME/.dx-state/fleet"
  
  local cmd="DX_FLEET_STATE_ROOT=\"$state_dir\" \"$remote_script\" --$action --json --state-dir \"$state_dir\" 2>&1"
  
  ssh_canonical_vm "$target" "$cmd" 2>&1 || echo "ERROR: SSH connection failed"
}

parse_result() {
  local output="$1"
  local host="$2"
  
  if ! command -v jq >/dev/null 2>&1; then
    echo "{\"host\":\"$host\",\"status\":\"error\",\"details\":\"jq not available\"}"
    return 1
  fi
  
  local status overall reason_code
  status="$(printf '%s' "$output" | jq -r '.status // .overall // "unknown"' 2>/dev/null || echo "unknown")"
  overall="$(printf '%s' "$output" | jq -r '.overall // .status // "unknown"' 2>/dev/null || echo "unknown")"
  reason_code="$(printf '%s' "$output" | jq -r '.reason_code // .reason_codes[0] // "unknown"' 2>/dev/null || echo "unknown")"
  
  if [[ "$status" == "error" || "$overall" == "red" ]]; then
    printf '{"host":"%s","status":"fail","overall":"%s","reason_code":"%s","details":"%s"}\n' \
      "$host" "$overall" "$reason_code" "$(json_escape "$output" | head -c 200)"
    return 1
  elif [[ "$status" == "warn" || "$overall" == "yellow" ]]; then
    printf '{"host":"%s","status":"warn","overall":"%s","reason_code":"%s"}\n' \
      "$host" "$overall" "$reason_code"
    return 0
  else
    printf '{"host":"%s","status":"pass","overall":"%s","reason_code":"%s"}\n' \
      "$host" "$overall" "$reason_code"
    return 0
  fi
}

main() {
  parse_args "$@"
  
  mkdir -p "$STATE_ROOT"
  
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  
  local local_host
  local_host="$(get_local_host)"
  
  local -a results=()
  local hosts_failed=0
  local hosts_warned=0
  local hosts_passed=0
  local failed_hosts=""
  
  local host
  for host in $(collect_hosts "$local_host"); do
    local output result
    
    if [[ "$host" == "$local_host" ]]; then
      output="$(run_converge_local "$ACTION")" || output="ERROR: Local converge failed"
    else
      output="$(run_converge_remote "$host" "$ACTION")" || output="ERROR: Remote converge failed"
    fi
    
    result="$(parse_result "$output" "$host")"
    results+=("$result")
    
    local status
    status="$(printf '%s' "$result" | jq -r '.status' 2>/dev/null || echo "unknown")"
    
    case "$status" in
      fail)
        hosts_failed=$((hosts_failed + 1))
        failed_hosts+="$host,"
        ;;
      warn)
        hosts_warned=$((hosts_warned + 1))
        ;;
      pass)
        hosts_passed=$((hosts_passed + 1))
        ;;
    esac
  done
  
  local overall_status="green"
  if [[ "$hosts_failed" -gt 0 ]]; then
    overall_status="red"
  elif [[ "$hosts_warned" -gt 0 ]]; then
    overall_status="yellow"
  fi
  
  local result_json
  result_json=$(cat <<JSON
{
  "mode": "fleet-converge",
  "action": "$ACTION",
  "generated_at": "$timestamp",
  "overall": "$overall_status",
  "hosts_checked": ${#results[@]},
  "hosts_passed": $hosts_passed,
  "hosts_warned": $hosts_warned,
  "hosts_failed": $hosts_failed,
  "failed_hosts": "$(echo "$failed_hosts" | sed 's/,$//')",
  "results": [$(IFS=,; echo "${results[*]}")],
  "state_paths": {"state_dir": "$STATE_ROOT"}
}
JSON
)
  
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '%s\n' "$result_json"
  else
    echo "🔍 Fleet Converge ($ACTION)"
    echo "overall: $overall_status"
    echo "hosts_checked: ${#results[@]}"
    echo "hosts_passed: $hosts_passed"
    echo "hosts_warned: $hosts_warned"
    echo "hosts_failed: $hosts_failed"
    if [[ -n "$failed_hosts" ]]; then
      echo "failed_hosts: $(echo "$failed_hosts" | sed 's/,$//')"
    fi
  fi
  
  if [[ "$overall_status" == "red" ]]; then
    exit 1
  elif [[ "$overall_status" == "yellow" ]]; then
    exit 2
  fi
  exit 0
}

main "$@"
