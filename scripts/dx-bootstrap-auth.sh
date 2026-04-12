#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="${SCRIPT_DIR}/dx-op-auth-status.sh"
SYNC_SCRIPT="${SCRIPT_DIR}/dx-sync-op-caches.sh"

usage() {
  cat <<'EOF'
Usage:
  dx-bootstrap-auth.sh [--json] [--no-sync]

Verifies and repairs agent-safe 1Password cache auth.

Policy:
  - macOS GUI-backed op/op signin is human-only.
  - Agents, cron, and fleet jobs should use synced cache or service-account auth.
  - Consumer hosts repair by syncing cache artifacts from epyc12.
EOF
}

json=0
sync_enabled=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json=1
      shift
      ;;
    --no-sync)
      sync_enabled=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

status_json() {
  "$STATUS_SCRIPT" --json 2>/dev/null || true
}

json_field() {
  local payload="${1:-}"
  local field="${2:-}"
  python3 - "$payload" "$field" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    data = {}
value = data.get(sys.argv[2], "")
print(value if isinstance(value, str) else "")
PY
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

emit_json() {
  local overall="$1" reason="$2" initial="$3" final="$4" sync_attempted="$5" sync_rc="$6" sync_output="$7"
  [[ -n "$initial" ]] || initial="{}"
  [[ -n "$final" ]] || final="{}"
  printf '{"status":%s,"reason_code":%s,"initial":%s,"final":%s,"sync_attempted":%s,"sync_rc":%s,"sync_output":%s}\n' \
    "$(json_escape "$overall")" \
    "$(json_escape "$reason")" \
    "$initial" \
    "$final" \
    "$sync_attempted" \
    "$sync_rc" \
    "$(json_escape "$sync_output")"
}

agent_ready() {
  case "${1:-}" in
    agent_ready_cache|agent_ready_service_account)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

initial="$(status_json)"
initial_mode="$(json_field "$initial" mode)"

if agent_ready "$initial_mode"; then
  if [[ "$json" == "1" ]]; then
    emit_json "green" "already_ready" "$initial" "$initial" "false" "0" ""
  else
    echo "agent auth ready: ${initial_mode}"
    echo "$initial"
  fi
  exit 0
fi

sync_attempted=false
sync_rc=0
sync_output=""

if [[ "$sync_enabled" == "1" ]]; then
  sync_attempted=true
  if sync_output="$("$SYNC_SCRIPT" 2>&1)"; then
    sync_rc=0
  else
    sync_rc=$?
  fi
fi

final="$(status_json)"
final_mode="$(json_field "$final" mode)"

if agent_ready "$final_mode"; then
  if [[ "$json" == "1" ]]; then
    emit_json "green" "synced_or_ready" "$initial" "$final" "$sync_attempted" "$sync_rc" "$sync_output"
  else
    [[ -n "$sync_output" ]] && printf '%s\n' "$sync_output"
    echo "agent auth ready: ${final_mode}"
    echo "$final"
  fi
  exit 0
fi

if [[ "$json" == "1" ]]; then
  emit_json "red" "missing_agent_auth_cache" "$initial" "$final" "$sync_attempted" "$sync_rc" "$sync_output"
else
  [[ -n "$sync_output" ]] && printf '%s\n' "$sync_output"
  cat >&2 <<'EOF'
BLOCKED: missing_agent_auth_cache
NEEDS: Tailscale SSH access to epyc12 and source cache files from dx-refresh-op-caches.sh, or a configured service-account credential.
HUMAN_MACOS_NOTE: op signin only helps manual op commands; it does not satisfy agent auth.
EOF
  echo "$final" >&2
fi

exit 1
