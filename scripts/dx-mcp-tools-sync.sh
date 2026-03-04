#!/usr/bin/env bash
# dx-mcp-tools-sync.sh
# Fleet Sync V2.1 local-first MCP tool convergence helper.
#
# Modes:
#   --check   : health-check only (default)
#   --apply   : install tools then health-check
#   --repair  : alias for --apply
#
# Outputs:
#   --json        -> print tool-health.json
#   --report-lines -> print compact line format (also used by dx-audit cross-host)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_MANIFEST="${ROOT_DIR}/configs/mcp-tools.yaml"
STATE_DIR="${HOME}/.dx-state/fleet-sync"
STATE_JSON="${STATE_DIR}/tool-health.json"
STATE_LINES="${STATE_DIR}/tool-health.lines"

MODE="check"
REPORT_ONLY=0
JSON_ONLY=0
MANIFEST="${DEFAULT_MANIFEST}"

usage() {
  cat <<'USAGE'
Usage:
  dx-mcp-tools-sync.sh [--check|--apply|--repair] [--manifest PATH] [--json] [--report-lines]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      MODE="check"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    --repair)
      MODE="apply"
      shift
      ;;
    --manifest)
      MANIFEST="${2:-}"
      [[ -n "$MANIFEST" ]] || { echo "Missing --manifest value" >&2; exit 2; }
      shift 2
      ;;
    --json)
      JSON_ONLY=1
      shift
      ;;
    --report-lines)
      REPORT_ONLY=1
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

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  if [[ -f "${STATE_LINES}" ]]; then
    cat "${STATE_LINES}"
    exit 0
  fi
  echo "meta|0|unknown|0"
  exit 3
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: ${MANIFEST}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
NOW_EPOCH="$(date -u +%s)"

python3 - "$MANIFEST" "$STATE_JSON" "$STATE_LINES" "$MODE" "$NOW_EPOCH" "$NOW_ISO" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

manifest_path, out_json_path, out_lines_path, mode, now_epoch_s, now_iso = sys.argv[1:7]
now_epoch = int(now_epoch_s)
host = os.uname().nodename


def run_cmd(cmd: str):
    proc = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def parse_version(text: str) -> str:
    if not text:
        return ""
    m = re.search(r"(\d+\.\d+\.\d+)", text)
    if m:
        return m.group(1)
    m = re.search(r"(\d+\.\d+)", text)
    if m:
        return m.group(1)
    return text.strip()[:64]


def prev_state(path: Path):
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as f:
        prev = json.load(f)
    return prev if isinstance(prev, dict) else {}


def check_dolt(prev):
    rc, _, _ = run_cmd("cd \"$HOME\"/bd && bd dolt test --json")
    if rc == 0:
        return "true", now_epoch
    last = int(prev.get("dolt_last_ok_epoch", 0) or 0)
    return "false", last

try:
    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = yaml.safe_load(f) or {}
except Exception as exc:
    print(f"Failed to load manifest: {exc}", file=sys.stderr)
    raise SystemExit(1)

state = prev_state(Path(out_json_path))
prev_rows = {
    str(item.get("name", "")): item
    for item in state.get("tools", [])
    if isinstance(item, dict)
}

rows = []
overall_ok = True

for tool_name in sorted((manifest.get("tools") or {}).keys()):
    cfg = manifest.get("tools", {}).get(tool_name)
    if not isinstance(cfg, dict) or not cfg.get("enabled", False):
        continue

    expected_version = str(cfg.get("version", "")).strip()
    install_cmd = str(cfg.get("install_cmd", "")).strip()
    health_cmd = str(cfg.get("health_cmd", "")).strip()
    prev_item = prev_rows.get(str(tool_name), {})

    detected_version = ""
    error_summary = ""
    healthy = True
    last_ok_epoch = 0
    last_fail_epoch = 0

    if mode == "apply" and install_cmd:
        install_rc, _, _ = run_cmd(install_cmd)
        if install_rc != 0:
            healthy = False
            error_summary = "install_failed"

    if healthy:
        if health_cmd:
            health_rc, out, err = run_cmd(health_cmd)
            if health_rc != 0:
                healthy = False
                error_summary = "health_failed"
            else:
                detected_version = parse_version(f"{out}\n{err}".strip())
                if not detected_version:
                    healthy = False
                    error_summary = "health_empty"
                elif expected_version and detected_version != expected_version:
                    healthy = False
                    error_summary = "version_mismatch"
        else:
            healthy = False
            error_summary = "missing_health_cmd"

    if healthy:
        last_ok_epoch = now_epoch
        last_fail_epoch = 0
    else:
        last_ok_epoch = int(prev_item.get("last_ok_epoch", 0) or 0)
        last_fail_epoch = now_epoch
        overall_ok = False

    if not expected_version:
        detected_version = detected_version or str(prev_item.get("detected_version", ""))

    rows.append(
        {
            "name": str(tool_name),
            "expected_version": expected_version,
            "detected_version": detected_version,
            "healthy": bool(healthy),
            "last_ok_epoch": int(last_ok_epoch),
            "last_fail_epoch": int(last_fail_epoch),
            "error_summary": error_summary,
        }
    )

if not rows:
    overall_ok = False

dolt_ok, dolt_last_ok_epoch = check_dolt(state)
payload = {
    "generated_at": now_iso,
    "generated_at_epoch": now_epoch,
    "host": host,
    "mode": mode,
    "manifest": manifest_path,
    "overall_ok": bool(overall_ok),
    "tools_ok": bool(overall_ok),
    "dolt_ok": dolt_ok,
    "dolt_last_ok_epoch": int(dolt_last_ok_epoch),
    "tools": rows,
}

with open(out_json_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)

with open(out_lines_path, "w", encoding="utf-8") as f:
    f.write(f"meta|{now_epoch}|{dolt_ok}|{dolt_last_ok_epoch}\n")
    for row in rows:
        healthy = "true" if row["healthy"] else "false"
        f.write(
            "tool|{name}|{expected}|{detected}|{healthy}|{ok}|{fail}|{error}\n".format(
                name=row["name"],
                expected=row["expected_version"],
                detected=row["detected_version"],
                healthy=healthy,
                ok=row["last_ok_epoch"],
                fail=row["last_fail_epoch"],
                error=row["error_summary"],
            )
        )

PY

check_status="$(python3 - "$STATE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)
print("ok" if payload.get("overall_ok") else "fail")
PY
)"
if [[ "$check_status" != "ok" ]]; then
  if [[ "$JSON_ONLY" -eq 1 ]]; then
    [[ "$JSON_ONLY" -eq 1 ]] && cat "$STATE_JSON"
    exit 1
  fi
  echo "fail"
  exit 1
fi

if [[ "$JSON_ONLY" -eq 1 ]]; then
  cat "$STATE_JSON"
else
  echo "ok"
fi

exit 0
