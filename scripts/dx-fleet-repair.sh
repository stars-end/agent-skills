#!/usr/bin/env bash
# dx-fleet-repair.sh
# Fleet Sync V2.1 repair entrypoint.
# Repairs drifted tool binaries and IDE MCP configs, then re-checks convergence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_MANIFEST="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
MCP_MANIFEST="${SCRIPT_DIR}/../configs/mcp-tools.yaml"
STATE_DIR="${HOME}/.dx-state/fleet-sync"
JSON_ONLY=0
FORCE_NO_AUTH=0
DRY_RUN=0
TARGETS=()

usage() {
  cat <<'USAGE'
Usage:
  dx-fleet-repair.sh [--manifest PATH] [--mcp-manifest PATH] [--state-dir PATH]
    [--force-no-auth] [--dry-run] [--json]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      FLEET_MANIFEST="${2:-}"
      [[ -n "$FLEET_MANIFEST" ]] || { echo "Missing --manifest value" >&2; exit 2; }
      shift 2
      ;;
    --mcp-manifest)
      MCP_MANIFEST="${2:-}"
      [[ -n "$MCP_MANIFEST" ]] || { echo "Missing --mcp-manifest value" >&2; exit 2; }
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      [[ -n "$STATE_DIR" ]] || { echo "Missing --state-dir value" >&2; exit 2; }
      shift 2
      ;;
    --force-no-auth)
      FORCE_NO_AUTH=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --json)
      JSON_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  CHECK_ARGS=(--check --json)
  CHECK_MODE="check"
else
  CHECK_ARGS=(--apply --json)
  CHECK_MODE="repair"
fi

# Repair = check or apply the install surface and then emit check report.
TMP_CHECK="$(mktemp)"
trap 'rm -f "$TMP_CHECK"' EXIT

"$SCRIPT_DIR/dx-fleet-install.sh" "${CHECK_ARGS[@]}" \
  --manifest "$FLEET_MANIFEST" \
  --mcp-manifest "$MCP_MANIFEST" \
  --state-dir "$STATE_DIR" \
  $([ "$FORCE_NO_AUTH" -eq 1 ] && echo --force-no-auth) > "$TMP_CHECK"

TMP_FINAL="$(mktemp)"
trap 'rm -f "$TMP_CHECK" "$TMP_FINAL"' EXIT

python3 - "$TMP_CHECK" "$FLEET_MANIFEST" "$MCP_MANIFEST" "$STATE_DIR" "$CHECK_MODE" <<'PY'
import json
import os
import sys
import time

check_path, fleet_manifest, mcp_manifest, state_dir, mode = sys.argv[1:6]
with open(check_path, "r", encoding="utf-8") as fp:
    base = json.load(fp)

tools = base.get("tools", {})
configs = base.get("configs", {})
auth = base.get("auth", {})
checks_ok = bool(configs.get("overall_ok", False)) and bool(tools.get("overall_ok", False))
auth_ok = bool((auth.get("op", {}) or {}).get("ready", False)) and bool((auth.get("railway", {}) or {}).get("ready", False))
checks = {
    "applied": bool(mode == "repair"),
    "tool_ok": bool(tools.get("overall_ok", False)),
    "config_ok": bool(configs.get("overall_ok", False)),
    "config_drift_count": int(configs.get("drift_count", 0) or 0),
    "auth_ok": bool(auth_ok),
}
checks_ok = bool(checks_ok and auth_ok)

auth = base.get("auth", {})
payload = {
    "generated_at": base.get("generated_at", ""),
    "generated_at_epoch": int(base.get("generated_at_epoch", 0) or 0),
    "host": base.get("host", ""),
    "mode": mode,
    "overall_ok": bool(checks_ok),
    "manifest": fleet_manifest,
    "mcp_manifest": mcp_manifest,
    "state_dir": state_dir,
    "checks": checks,
    "tools": {
        "overall_ok": bool(tools.get("overall_ok", False)),
        "rows": tools.get("tools", []),
        "dolt_ok": str(tools.get("dolt_ok", "unknown")),
    },
    "configs": {
        "overall_ok": bool(configs.get("overall_ok", False)),
        "count": int(configs.get("count", 0) or 0),
        "drift_count": int(configs.get("drift_count", 0) or 0),
        "entries": configs.get("entries", []),
    },
    "auth": auth,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY > "$TMP_FINAL"

if [[ "$JSON_ONLY" -eq 1 ]]; then
  cat "$TMP_FINAL"
  if [[ "$(python3 -c 'import json,sys;print(\"1\" if json.load(sys.stdin).get(\"overall_ok\") else \"0\")' < "$TMP_FINAL")" != "1" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Fleet repair (dry-run):"
else
  echo "Fleet repair applied:"
fi
python3 - "$TMP_FINAL" <<'PY'
import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)
print(f"generated_at={payload.get('generated_at')}")
print(f"overall_ok={str(payload.get('overall_ok')).lower()}")
print(f"tool_ok={str(payload['tools']['overall_ok']).lower()}")
print(f"config_drift_count={payload['configs']['drift_count']}")
PY

if [[ "$(python3 -c 'import json,sys;print(\"1\" if json.load(sys.stdin).get(\"overall_ok\") else \"0\")' < "$TMP_FINAL")" != "1" ]]; then
  exit 1
fi

exit 0
