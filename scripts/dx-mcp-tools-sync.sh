#!/usr/bin/env bash
# dx-mcp-tools-sync.sh
# Fleet Sync V2.1 local-first MCP tool convergence helper.
#
# Modes:
#   --check       : run health checks only (default)
#   --apply       : install/update then health check
#   --repair      : same as --apply (force repair path)
#   --report-lines: print compact machine-readable report lines
#
# State output:
#   ~/.dx-state/fleet-sync/tool-health.json
#   ~/.dx-state/fleet-sync/tool-health.lines

set -euo pipefail

MODE="check"
REPORT_ONLY=0
MANIFEST_DEFAULT="$HOME/agent-skills/configs/mcp-tools.yaml"
MANIFEST="$MANIFEST_DEFAULT"
STATE_DIR="$HOME/.dx-state/fleet-sync"
STATE_JSON="$STATE_DIR/tool-health.json"
STATE_LINES="$STATE_DIR/tool-health.lines"

usage() {
  cat <<USAGE
Usage: $0 [--check|--apply|--repair] [--manifest PATH] [--report-lines]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    --repair) MODE="repair"; shift ;;
    --report-lines) REPORT_ONLY=1; shift ;;
    --manifest)
      MANIFEST="${2:-}"
      [[ -n "$MANIFEST" ]] || { echo "Missing value for --manifest" >&2; exit 2; }
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  if [[ -f "$STATE_LINES" ]]; then
    cat "$STATE_LINES"
    exit 0
  fi
  echo "meta|0|unknown|0"
  exit 3
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse YAML manifest" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
NOW_ISO="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
NOW_EPOCH="$(date -u +%s)"

# Build tool records from YAML: name|version|install_cmd|health_cmd
TOOL_ROWS="$(ruby -ryaml -e '
manifest = YAML.load_file(ARGV[0]) || {}
tools = manifest["tools"] || {}
tools.each do |name, cfg|
  next unless cfg.is_a?(Hash)
  next unless cfg["enabled"]
  version = cfg["version"].to_s
  install = cfg["install_cmd"].to_s
  health = cfg["health_cmd"].to_s
  puts [name, version, install, health].join("\t")
end
' "$MANIFEST")"

# Dolt connectivity check (best effort)
DOLT_OK="unknown"
DOLT_LAST_OK_EPOCH=0
if command -v bd >/dev/null 2>&1; then
  if bd dolt test --json >/dev/null 2>&1; then
    DOLT_OK="true"
    DOLT_LAST_OK_EPOCH="$NOW_EPOCH"
  else
    DOLT_OK="false"
    if [[ -f "$STATE_JSON" ]]; then
      DOLT_LAST_OK_EPOCH="$(python3 - <<'PY' "$STATE_JSON"
import json,sys
p=sys.argv[1]
try:
  d=json.load(open(p))
  print(int(d.get("dolt_last_ok_epoch",0)))
except Exception:
  print(0)
PY
)"
    fi
  fi
fi

TMP_LINES="$(mktemp)"
TMP_JSON="$(mktemp)"

# shellcheck disable=SC2312
{
  echo "meta|${NOW_EPOCH}|${DOLT_OK}|${DOLT_LAST_OK_EPOCH}"
} > "$TMP_LINES"

OVERALL_OK=1

if [[ -n "$TOOL_ROWS" ]]; then
  while IFS=$'\t' read -r tool_name expected_version install_cmd health_cmd; do
    [[ -z "$tool_name" ]] && continue

    detected_version="$expected_version"
    healthy="true"
    last_ok_epoch="$NOW_EPOCH"
    last_fail_epoch="0"
    error_summary=""

    if [[ "$MODE" == "apply" || "$MODE" == "repair" ]]; then
      if [[ -n "$install_cmd" ]]; then
        if ! bash -lc "$install_cmd" >/dev/null 2>&1; then
          healthy="false"
          last_ok_epoch="0"
          last_fail_epoch="$NOW_EPOCH"
          error_summary="install_failed"
          OVERALL_OK=0
        fi
      fi
    fi

    if [[ "$healthy" == "true" && -n "$health_cmd" ]]; then
      health_out=""
      health_rc=0
      health_out="$(bash -lc "$health_cmd" 2>&1)" || health_rc=$?
      if [[ "$health_rc" -ne 0 ]]; then
        healthy="false"
        last_ok_epoch="0"
        last_fail_epoch="$NOW_EPOCH"
        error_summary="health_failed"
        OVERALL_OK=0
      elif [[ -z "$health_out" ]]; then
        healthy="false"
        last_ok_epoch="0"
        last_fail_epoch="$NOW_EPOCH"
        error_summary="health_empty"
        OVERALL_OK=0
      else
        if [[ "$health_out" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
          detected_version="${BASH_REMATCH[1]}"
        elif [[ "$health_out" =~ ([0-9]+\.[0-9]+) ]]; then
          detected_version="${BASH_REMATCH[1]}"
        fi
      fi
    elif [[ "$healthy" == "true" && -z "$health_cmd" ]]; then
      healthy="false"
      last_ok_epoch="0"
      last_fail_epoch="$NOW_EPOCH"
      error_summary="missing_health_cmd"
      OVERALL_OK=0
    fi

    echo "tool|${tool_name}|${expected_version}|${detected_version}|${healthy}|${last_ok_epoch}|${last_fail_epoch}|${error_summary}" >> "$TMP_LINES"
  done <<< "$TOOL_ROWS"
fi

python3 - <<'PY' "$TMP_LINES" "$TMP_JSON" "$NOW_ISO" "$HOSTNAME_SHORT" "$MODE" "$MANIFEST" "$OVERALL_OK"
import json
import sys

lines_path, out_path, now_iso, host, mode, manifest, overall_ok = sys.argv[1:8]
rows = []
meta = {
    "generated_at_epoch": 0,
    "dolt_ok": "unknown",
    "dolt_last_ok_epoch": 0,
}

with open(lines_path, "r", encoding="utf-8") as f:
    for raw in f:
        raw = raw.strip()
        if not raw:
            continue
        parts = raw.split("|")
        kind = parts[0]
        if kind == "meta":
            meta["generated_at_epoch"] = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
            meta["dolt_ok"] = parts[2] if len(parts) > 2 else "unknown"
            meta["dolt_last_ok_epoch"] = int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 0
            continue
        if kind != "tool":
            continue
        while len(parts) < 8:
            parts.append("")
        rows.append(
            {
                "name": parts[1],
                "expected_version": parts[2],
                "detected_version": parts[3],
                "healthy": parts[4] == "true",
                "last_ok_epoch": int(parts[5]) if parts[5].isdigit() else 0,
                "last_fail_epoch": int(parts[6]) if parts[6].isdigit() else 0,
                "error_summary": parts[7],
            }
        )

payload = {
    "generated_at": now_iso,
    "host": host,
    "mode": mode,
    "manifest": manifest,
    "overall_ok": overall_ok == "1",
    "dolt_ok": meta["dolt_ok"],
    "dolt_last_ok_epoch": meta["dolt_last_ok_epoch"],
    "tools": rows,
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY

mv "$TMP_JSON" "$STATE_JSON"
mv "$TMP_LINES" "$STATE_LINES"

if [[ "$MODE" == "check" ]]; then
  exit 0
fi

exit 0
