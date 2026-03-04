#!/usr/bin/env bash
# dx-fleet-check.sh
# Fleet Sync V2.1 convergence check surface.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_MANIFEST="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
MCP_MANIFEST="${SCRIPT_DIR}/../configs/mcp-tools.yaml"
STATE_DIR="${HOME}/.dx-state/fleet-sync"
OUTPUT_JSON=0
RED_ONLY=0
MODE="check"
JSON=0

usage() {
  cat <<'USAGE'
Usage:
  dx-fleet-check.sh [--json] [--red-only] [--manifest PATH] [--mcp-manifest PATH] [--state-dir PATH]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    --red-only)
      RED_ONLY=1
      shift
      ;;
    --manifest)
      FLEET_MANIFEST="${2:-}"
      [[ -n "$FLEET_MANIFEST" ]] || { echo "Missing value for --manifest" >&2; exit 2; }
      shift 2
      ;;
    --mcp-manifest)
      MCP_MANIFEST="${2:-}"
      [[ -n "$MCP_MANIFEST" ]] || { echo "Missing value for --mcp-manifest" >&2; exit 2; }
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      [[ -n "$STATE_DIR" ]] || { echo "Missing value for --state-dir" >&2; exit 2; }
      shift 2
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

TMP_JSON="$(mktemp)"
CHECK_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$CHECK_JSON"' EXIT

if ! "$SCRIPT_DIR/dx-fleet-install.sh" \
  --check --json --manifest "$FLEET_MANIFEST" --mcp-manifest "$MCP_MANIFEST" --state-dir "$STATE_DIR" > "$TMP_JSON"; then
  echo "Fleet check: install preflight returned non-zero" >&2
fi

python3 - "$TMP_JSON" "$CHECK_JSON" <<'PY'
import json
import os
import re
import time
import sys

raw_path = sys.argv[1]
with open(raw_path, "r", encoding="utf-8") as fp:
    payload = json.load(fp)

configs = payload.get("configs", {}) or {}
configs_entries = configs.get("entries", []) if isinstance(configs, dict) else []
configs_overall = bool(configs.get("overall_ok", False)) if isinstance(configs, dict) else False
config_drift = int(configs.get("drift_count", 0) or 0) if isinstance(configs, dict) else 0
config_count = int(configs.get("count", 0) or 0) if isinstance(configs, dict) else len(configs_entries)

tools = payload.get("tools", {}) or {}
if not isinstance(tools, dict):
    tools = {}
tool_rows = tools.get("tools", []) if isinstance(tools, dict) else []
if not isinstance(tool_rows, list):
    tool_rows = []

now = int(time.time())
tool_stale_default = 24 * 3600
dolt_stale_default = 60 * 60


def read_env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "")
    if not raw:
        return int(default)
    match = re.fullmatch(r"\s*([0-9]+)\s*", raw)
    if not match:
        return int(default)
    return int(match.group(1))


max_tool_stale_seconds = read_env_int("DX_FLEET_TOOL_STALE_SECONDS", tool_stale_default)
max_dolt_stale_seconds = read_env_int("DX_FLEET_DOLT_STALE_MINUTES", 60) * 60

version_mismatch = 0
stale_tools = 0
failing_tools = 0
for row in tool_rows:
    if not isinstance(row, dict):
        continue
    if str(row.get("healthy", "")).lower() not in ("true", "1", "yes"):
        failing_tools += 1
        continue

    expected_version = (row.get("expected_version") or "").strip()
    detected_version = (row.get("detected_version") or "").strip()
    if expected_version and detected_version and expected_version != detected_version:
        version_mismatch += 1

    last_ok = row.get("last_ok_epoch")
    if isinstance(last_ok, (int, float)) and last_ok:
        if now - int(last_ok) > max_tool_stale_seconds:
            stale_tools += 1
    else:
        stale_tools += 1

dolt_ok = str(tools.get("dolt_ok", "unknown")).lower() == "true"
last_dolt_ok_epoch = int(tools.get("dolt_last_ok_epoch", 0) or 0)
if not dolt_ok:
    dolt_stale = 1
elif last_dolt_ok_epoch > 0 and now - last_dolt_ok_epoch > max_dolt_stale_seconds:
    dolt_stale = 1
else:
    dolt_stale = 0

auth = payload.get("auth", {}) if isinstance(payload, dict) else {}
auth_ok = bool((auth.get("op", {}) or {}).get("ready", False) and (auth.get("railway", {}) or {}).get("ready", False))

checks = {
    "tool_stale_seconds": max_tool_stale_seconds,
    "dolt_stale_seconds": max_dolt_stale_seconds,
    "tool_version_mismatch": int(version_mismatch),
    "tool_health_failing": int(failing_tools),
    "tool_health_stale": int(stale_tools),
    "dolt_stale": int(dolt_stale),
    "config_drift": int(config_drift),
}

overall_ok = bool(
    configs_overall
    and not bool(version_mismatch)
    and not bool(failing_tools)
    and not bool(stale_tools)
    and not dolt_stale
    and auth_ok
    and bool(tools.get("overall_ok", False))
)

if not isinstance(payload, dict):
    payload = {}

summary = {
    "generated_at": payload.get("generated_at", ""),
    "generated_at_epoch": int(payload.get("generated_at_epoch", 0) or 0),
    "host": payload.get("host", ""),
    "mode": "check",
    "overall_ok": bool(overall_ok),
    "checks": checks,
    "configs": {
        "overall_ok": bool(configs_overall),
        "count": int(config_count),
        "drift_count": int(config_drift),
        "entries": configs_entries,
    },
    "tools": {
        "overall_ok": bool(tools.get("overall_ok", False)),
        "dolt_ok": str(tools.get("dolt_ok", "unknown")),
        "dolt_last_ok_epoch": int(last_dolt_ok_epoch),
        "rows": tool_rows,
    },
    "auth": {
        "op": auth.get("op", {}),
        "railway": auth.get("railway", {}),
    },
}

with open(sys.argv[2], "w", encoding="utf-8") as out:
    json.dump(summary, out, indent=2, sort_keys=True)
    out.write("\n")
PY

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  cat "$CHECK_JSON"
else
  python3 - "$CHECK_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    p = json.load(fp)

if p.get("overall_ok"):
  print("Fleet check: OK")
  print(f"tools_ok={p['tools']['overall_ok']} config_drift={p['checks']['config_drift']} v_mismatch={p['checks']['tool_version_mismatch']} stale_tools={p['checks']['tool_health_stale']} dolt_stale={p['checks']['dolt_stale']}")
  print(f"auth_op={str(bool(p['auth']['op'].get('ready'))).lower()} auth_railway={str(bool(p['auth']['railway'].get('ready'))).lower()}")
else:
  print("Fleet check: RED")
  print(f"tools_ok={p['tools']['overall_ok']} config_drift={p['checks']['config_drift']} v_mismatch={p['checks']['tool_version_mismatch']} stale_tools={p['checks']['tool_health_stale']} dolt_stale={p['checks']['dolt_stale']}")
  if not p['auth']['op'].get('ready'):
    print(f"auth_op={p['auth']['op'].get('reason', 'unknown')}")
  if not p['auth']['railway'].get('ready'):
    print(f"auth_railway={p['auth']['railway'].get('reason', 'unknown')}")
PY
fi

overall=$(python3 - "$CHECK_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fp:
    p = json.load(fp)
print('1' if p.get('overall_ok') else '0')
PY
)

if [[ "$RED_ONLY" -eq 1 && "$overall" != "1" ]]; then
  exit 1
fi

if [[ "$overall" != "1" ]]; then
  exit 1
fi

exit 0
