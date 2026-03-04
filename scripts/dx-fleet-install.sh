#!/usr/bin/env bash
#
# dx-fleet-install.sh
#
# Fleet Sync bootstrap + uninstall routine.
# Uninstall path is best-effort and must not require optional Python packages.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
MANIFEST_PATH="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
MODE="install"

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

json_list() {
  local -n source=$1
  local out="["
  local first=1
  local entry
  for entry in "${source[@]}"; do
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

state_paths_json() {
  printf '{'
  printf '"state_dir":"%s",' "$STATE_ROOT"
  printf '"tool_health_json":"%s",' "${STATE_ROOT}/tool-health.json"
  printf '"tool_health_lines":"%s"' "${STATE_ROOT}/tool-health.lines"
  printf '}'
}

usage() {
  cat <<'EOF'
Usage:
  dx-fleet-install.sh [--state-dir PATH]
  dx-fleet-install.sh --uninstall [--state-dir PATH]
  dx-fleet-install.sh --uninstall --json

Defaults install (no-op placeholder) and writes install metadata.
Uninstall runs best-effort teardown without Python dependency requirements.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

collect_manifest_info() {
  if [[ -f "$MANIFEST_PATH" ]]; then
    printf true
  else
    printf false
  fi
}

build_uninstall_report() {
  local -a targets=(
    "${STATE_ROOT}"
    "${HOME}/.config/fleet-sync"
    "${HOME}/.cache/fleet-sync"
    "${HOME}/.dx-state/fleet-link"
  )
  local -a actions=()
  local -a failures=()
  local overall_ok=true

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      actions+=("missing_ok:$target")
      continue
    fi

    if rm -rf "$target" >/dev/null 2>&1; then
      actions+=("removed:$target")
    else
      actions+=("failed_remove:$target")
      failures+=("failed_remove:$target")
      overall_ok=false
    fi
  done

  local reason_code="ok"
  local next_action="noop"
  if [[ "$overall_ok" == "false" ]]; then
    reason_code="partial_failure"
    next_action="retry"
  fi

  local warnings=()
  if [[ "$overall_ok" == "false" ]]; then
    warnings+=("partial uninstall completed with failures; retry elevated where needed")
  else
    warnings+=("no warnings")
  fi

  if [[ "${#actions[@]}" -eq 0 ]]; then
    actions+=("noop")
  fi

  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"
  local manifest_present
  manifest_present="$(collect_manifest_info)"
  cat <<EOF
{
  "mode": "uninstall",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "overall_ok": $overall_ok,
  "reason_code": "$reason_code",
  "next_action": "$next_action",
  "summary": {
    "actions_attempted": ${#actions[@]},
    "errors": ${#failures[@]},
    "manifest_present": $manifest_present
  },
  "actions": $(json_list actions),
  "warnings": $(json_list warnings),
  "failures": $(json_list failures),
  "state_paths": $(state_paths_json),
  "remediation_hints": [
    "Run dx-fleet-install.sh --uninstall again on missing-permission paths"
  ]
}
EOF
}

uninstall() {
  local out
  out="$(build_uninstall_report)"
  printf '%s\n' "$out"
  if [[ "$out" == *'"overall_ok": false'* ]]; then
    return 2
  fi
  return 0
}

install() {
  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"
  local manifest_present
  manifest_present="$(collect_manifest_info)"
  mkdir -p "$STATE_ROOT"
  local out
  out="$(cat <<EOF
{
  "mode": "install",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "overall_ok": true,
  "reason_code": "ok",
  "next_action": "noop",
  "manifest_present": $manifest_present,
  "state_paths": $(state_paths_json)
}
EOF
)"
  write_atomic "${STATE_ROOT}/install.json" "$out"
  printf '%s\n' "$out"
}

parse_args "$@"

if [[ "$MODE" == "uninstall" ]]; then
  uninstall
  exit $?
fi

install
exit 0
