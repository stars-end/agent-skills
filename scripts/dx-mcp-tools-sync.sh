#!/usr/bin/env bash
#
# dx-mcp-tools-sync.sh
#
# Read-only status/repair helper for MCP profile artifacts.
# Designed for safe concurrent operation with atomic output writes.
#
set -euo pipefail

STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
MODE="check"
STATE_PATH="${STATE_ROOT}/mcp-tools-sync.json"

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
      --repair)
        MODE="repair"
        shift
        ;;
      --check|--status)
        MODE="check"
        shift
        ;;
      --json|--json-only)
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        STATE_PATH="${STATE_ROOT}/mcp-tools-sync.json"
        shift 2
        ;;
      --help|-h)
        cat <<'EOF'
Usage:
  dx-mcp-tools-sync.sh [--check|--repair] [--state-dir PATH]
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

candidate_files() {
  printf '%s\n' \
    "${HOME}/.claude/settings.json" \
    "${HOME}/.claude.json" \
    "${HOME}/.codex/config.toml" \
    "${HOME}/.opencode/config.json" \
    "${HOME}/.gemini/antigravity/mcp_config.json" \
    "${HOME}/.gemini/GEMINI.md"
}

build_rows() {
  local -a rows=()
  local file
  local status severity detail pass warn fail row
  local pass_count=0
  local warn_count=0
  local fail_count=0
  local repair_missing=0
  local overall_status="green"

  while IFS= read -r file; do
    if [[ -f "$file" ]]; then
      status="pass"
      severity="low"
      detail=""
      pass_count=$((pass_count + 1))
    else
      status="warn"
      severity="medium"
      detail="missing: $file"
      warn_count=$((warn_count + 1))
      repair_missing=$((repair_missing + 1))
    fi

    if [[ "$status" == "warn" && "$MODE" == "repair" ]]; then
      row="{\"path\":\"$(json_escape "$file")\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$detail")\",\"next_action\":\"dx-fleet-repair --json\"}"
    else
      row="{\"path\":\"$(json_escape "$file")\",\"status\":\"$status\",\"severity\":\"$severity\",\"details\":\"$(json_escape "$detail")\"}"
    fi
    rows+=("$row")
  done < <(candidate_files)

  if [[ "$repair_missing" -gt 0 && "$MODE" == "repair" ]]; then
    overall_status="red"
    status="red"
    severity="medium"
    detail="repair requested: create missing IDE MCP artifacts or remove canonical enforcement for non-present lanes"
    fail_count=$repair_missing
    warn_count=0
  else
    overall_status="green"
    status="green"
    severity="low"
    detail="all candidate files present"
  fi

  local rows_json="["
  local first=1
  for row in "${rows[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      rows_json+="$row"
      first=0
    else
      rows_json+=",$row"
    fi
  done
  rows_json+="]"

  local reason_code="ok"
  if [[ "$warn_count" -gt 0 ]]; then
    reason_code="missing_profiles"
  fi

  if [[ "$MODE" == "repair" && "$repair_missing" -gt 0 ]]; then
    reason_code="repair_requested"
  fi

  printf '%s\n' "$overall_status|$status|$severity|$detail|$pass_count|$warn_count|$fail_count|$reason_code|$rows_json"
}

run() {
  local results
  results="$(build_rows)"
  IFS='|' read -r overall status severity details pass_count warn_count fail_count reason_code rows_json <<< "$results"

  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"

  local payload
  payload="$(cat <<EOF
{
  "mode": "mcp-tools-sync",
  "generated_at": "$timestamp",
  "generated_at_epoch": $epoch,
  "mode_action": "$MODE",
  "overall": "$overall",
  "status": "$status",
  "details": "$details",
  "reason_code": "$reason_code",
  "summary": {"pass":$pass_count,"warn":$warn_count,"fail":$fail_count},
  "files": $rows_json,
  "state_paths": {
    "state_dir": "${STATE_ROOT}",
    "file": "${STATE_PATH}"
  }
}
EOF
)"
  write_atomic "$STATE_PATH" "$payload"
  printf '%s\n' "$payload"

  if [[ "$overall" == "red" ]]; then
    return 1
  fi
  if [[ "$MODE" == "check" && "$warn_count" -gt 0 ]]; then
    return 1
  fi
  return 0
}

parse_args "$@"
run
