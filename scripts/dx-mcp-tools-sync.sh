#!/usr/bin/env bash
#
# dx-mcp-tools-sync.sh
#
# Manifest-driven MCP tool convergence for Fleet Sync.
#
# Modes:
#   --check  : drift detection only (no mutation)
#   --apply  : converge tools + IDE MCP configs from manifest
#   --repair : force converge + re-verify
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_MANIFEST="${REPO_ROOT}/configs/mcp-tools.yaml"
TEMPLATE_ROOT="${REPO_ROOT}/config-templates"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
STATE_PATH="${STATE_ROOT}/mcp-tools-sync.json"
MODE="check"
OUTPUT_JSON=1
REPORT_LINES=0

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/canonical-targets.sh" 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage:
  dx-mcp-tools-sync.sh [--check|--apply|--repair] [--state-dir PATH] [--json] [--report-lines] [--mcp-manifest PATH]

Notes:
  --check       drift detection only
  --apply       install/patch/verify convergence
  --repair      force re-apply convergence and verify
  --report-lines emit tab-separated summary rows for lightweight parsers
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check|--status)
        MODE="check"
        shift
        ;;
      --apply)
        MODE="apply"
        shift
        ;;
      --repair)
        MODE="repair"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        STATE_PATH="${STATE_ROOT}/mcp-tools-sync.json"
        shift 2
        ;;
      --mcp-manifest)
        MCP_MANIFEST="$2"
        shift 2
        ;;
      --json|--json-only)
        OUTPUT_JSON=1
        shift
        ;;
      --report-lines)
        REPORT_LINES=1
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

canonical_paths_tsv() {
  local ide
  for ide in "${CANONICAL_IDES[@]:-}"; do
    local p=""
    if p="$(get_ide_config "$ide" 2>/dev/null || true)"; then
      [[ -n "$p" ]] && printf '%s\t%s\n' "$ide" "$p"
    fi
  done
}

canonical_artifacts_tsv() {
  local ide line
  for ide in "${CANONICAL_IDES[@]:-}"; do
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '%s\t%s\n' "$ide" "$line"
    done < <(get_ide_artifacts "$ide" 2>/dev/null || true)
  done
}

run_python() {
  local paths_tsv artifacts_tsv
  paths_tsv="$(canonical_paths_tsv || true)"
  artifacts_tsv="$(canonical_artifacts_tsv || true)"

  MODE="$MODE" \
  MCP_MANIFEST="$MCP_MANIFEST" \
  TEMPLATE_ROOT="$TEMPLATE_ROOT" \
  STATE_ROOT="$STATE_ROOT" \
  STATE_PATH="$STATE_PATH" \
  CANONICAL_PATHS_TSV="$paths_tsv" \
  CANONICAL_ARTIFACTS_TSV="$artifacts_tsv" \
  python3 - <<'PY'
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(json.dumps({
        "mode": "mcp-tools-sync",
        "status": "red",
        "reason_code": "python_yaml_missing",
        "details": f"PyYAML import failed: {exc}",
    }))
    sys.exit(2)

mode = os.environ.get("MODE", "check")
manifest_path = Path(os.environ["MCP_MANIFEST"]).expanduser()
template_root = Path(os.environ.get("TEMPLATE_ROOT", "")).expanduser()
state_root = Path(os.environ["STATE_ROOT"]).expanduser()
state_path = Path(os.environ["STATE_PATH"]).expanduser()

state_root.mkdir(parents=True, exist_ok=True)

def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def run_cmd(command: str):
    proc = subprocess.run(command, shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode, (proc.stdout or "").strip()

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", delete=False, dir=str(path.parent), encoding="utf-8") as tmp:
        tmp.write(content)
        tmp_name = tmp.name
    Path(tmp_name).replace(path)

def canonical_paths() -> dict:
    out = {}
    raw = os.environ.get("CANONICAL_PATHS_TSV", "")
    for line in raw.splitlines():
        if "\t" not in line:
            continue
        ide, p = line.split("\t", 1)
        out[ide.strip()] = str(Path(p.strip()).expanduser())
    return out

def canonical_artifacts() -> dict:
    out = {}
    raw = os.environ.get("CANONICAL_ARTIFACTS_TSV", "")
    for line in raw.splitlines():
        if "\t" not in line:
            continue
        ide, p = line.split("\t", 1)
        ide = ide.strip()
        p = str(Path(p.strip()).expanduser())
        out.setdefault(ide, [])
        if p not in out[ide]:
            out[ide].append(p)
    return out

def load_manifest() -> dict:
    if not manifest_path.exists():
        raise RuntimeError(f"manifest missing: {manifest_path}")
    with manifest_path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise RuntimeError("manifest is not a mapping")
    return data

def render_json(path: Path, servers: dict, ide: str):
    key = "mcp" if ide == "opencode" else "mcpServers"
    payload = {}
    if path.exists():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(payload, dict):
                payload = {}
        except Exception:
            payload = {}
    mcp = payload.get(key, {})
    if not isinstance(mcp, dict):
        mcp = {}
    for name, entry in servers.items():
        if ide == "opencode":
            cmd = entry.get("command", "")
            args = entry.get("args", [])
            entry = {"type": "local", "command": ([cmd] if isinstance(cmd, str) else cmd) + args}
        mcp[name] = entry
    atomic_write(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")

def render_toml(path: Path, servers: dict):
    managed_begin = "# BEGIN FLEET_SYNC_MCP_MANAGED"
    managed_end = "# END FLEET_SYNC_MCP_MANAGED"
    base = ""
    if path.exists():
        base = path.read_text(encoding="utf-8", errors="ignore")
        pattern = re.compile(re.escape(managed_begin) + r".*?" + re.escape(managed_end), re.DOTALL)
        base = re.sub(pattern, "", base).rstrip() + "\n"
    lines = [managed_begin]
    for name, entry in sorted(servers.items()):
        lines.append(f"[mcpServers.{json.dumps(name)}]")
        lines.append(f"type = {json.dumps(entry.get('type', 'stdio'))}")
        lines.append(f"command = {json.dumps(entry.get('command', ''))}")
        args = entry.get("args", [])
        args_toml = "[" + ", ".join(json.dumps(a) for a in args) + "]"
        lines.append(f"args = {args_toml}")
        lines.append("")
    lines.append(managed_end)
    managed = "\n".join(lines) + "\n"
    atomic_write(path, base + managed)

def render_markdown(path: Path, ide: str, tool_names: list):
    managed_begin = "<!-- BEGIN FLEET_SYNC_MCP_MANAGED -->"
    managed_end = "<!-- END FLEET_SYNC_MCP_MANAGED -->"
    base = ""
    if path.exists():
        base = path.read_text(encoding="utf-8", errors="ignore")
        pattern = re.compile(re.escape(managed_begin) + r".*?" + re.escape(managed_end), re.DOTALL)
        base = re.sub(pattern, "", base).rstrip() + "\n"
    section = [
        managed_begin,
        "# Fleet Sync Canonical Constraints",
        "",
        "This file is managed by `dx-mcp-tools-sync.sh`.",
        "",
        f"IDE lane: `{ide}`",
        "Managed tools:",
    ]
    for t in sorted(tool_names):
        section.append(f"- `{t}`")
    section += ["", managed_end, ""]
    atomic_write(path, base + "\n".join(section))

def template_for_ide(ide: str, target_path: Path):
    mapping = {
        "antigravity": "fleet-sync-antigravity.template.json",
        "claude-code": "fleet-sync-claude-code.template.json",
        "codex-cli": "fleet-sync-codex-cli.template.toml",
        "opencode": "fleet-sync-opencode.template.json",
        "gemini-cli": "fleet-sync-antigravity.template.json",
    }
    name = mapping.get(ide)
    if not name:
        return None
    path = template_root / name
    if not path.exists():
        return None
    ext = target_path.suffix.lower()
    if ext == ".json" and path.suffix.lower() != ".json":
        return None
    if ext == ".toml" and path.suffix.lower() != ".toml":
        return None
    if ext == ".md" and path.suffix.lower() != ".md":
        return None
    return path

def check_json_has_servers(path: Path, names: list, ide: str):
    if not path.exists():
        return False, "missing file"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        key = "mcp" if ide == "opencode" else "mcpServers"
        servers = payload.get(key, {})
        if not isinstance(servers, dict):
            return False, f"{key} missing"
        missing = [n for n in names if n not in servers]
        if missing:
            return False, f"missing server entries: {', '.join(missing)}"
        return True, "ok"
    except Exception as exc:
        return False, f"invalid json: {exc}"

def check_toml_has_servers(path: Path, names: list):
    if not path.exists():
        return False, "missing file"
    text = path.read_text(encoding="utf-8", errors="ignore")
    for n in names:
        if f"[mcpServers.{json.dumps(n)}]" not in text:
            return False, f"missing section for {n}"
    return True, "ok"

def check_markdown_managed(path: Path):
    if not path.exists():
        return False, "missing file"
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "<!-- BEGIN FLEET_SYNC_MCP_MANAGED -->" not in text:
        return False, "missing managed block"
    return True, "ok"

try:
    manifest = load_manifest()
except Exception as exc:
    payload = {
        "mode": "mcp-tools-sync",
        "generated_at": now_iso(),
        "generated_at_epoch": int(dt.datetime.now(dt.timezone.utc).timestamp()),
        "mode_action": mode,
        "overall": "red",
        "status": "red",
        "details": str(exc),
        "reason_code": "manifest_load_failed",
        "summary": {"pass": 0, "warn": 0, "fail": 1},
        "tools": [],
        "files": [],
        "state_paths": {"state_dir": str(state_root), "file": str(state_path)},
    }
    text = json.dumps(payload, indent=2)
    atomic_write(state_path, text + "\n")
    print(text)
    sys.exit(1)

tools = manifest.get("tools", {})
render = manifest.get("render", {})
write_paths_manifest = render.get("write_paths", {}) if isinstance(render, dict) else {}

canon_paths = canonical_paths()
canon_artifacts = canonical_artifacts()

write_paths = dict(write_paths_manifest or {})
for ide, cpath in canon_paths.items():
    write_paths[ide] = cpath

enabled_tools = []
for name, spec in (tools or {}).items():
    if not isinstance(spec, dict):
        continue
    if spec.get("enabled", True):
        enabled_tools.append((name, spec))

servers_by_ide = {}
tool_rows = []
reason_codes = []

for name, spec in enabled_tools:
    install_cmd = str(spec.get("install_cmd", "")).strip()
    health_cmd = str(spec.get("health_cmd", "")).strip()

    # Determine integration mode: 'mcp' (IDE-rendered) or 'cli' (standalone)
    integration_mode = str(spec.get("integration_mode", "mcp")).lower()

    # Only MCP tools need target_ides and mcp config blocks
    target_ides = [str(i) for i in spec.get("target_ides", [])] if integration_mode == "mcp" else []
    mcp = spec.get("mcp", {}) if isinstance(spec.get("mcp", {}), dict) and integration_mode == "mcp" else {}
    entry = {
        "type": str(mcp.get("type", "stdio")),
        "command": str(mcp.get("command", "")),
        "args": [str(a) for a in mcp.get("args", [])],
    }

    install_rc = 0
    install_out = ""
    if mode in ("apply", "repair") and install_cmd:
        install_rc, install_out = run_cmd(install_cmd)

    health_rc = 0
    health_out = ""
    if health_cmd:
        health_rc, health_out = run_cmd(health_cmd)

    status = "pass"
    severity = "low"
    details = "healthy"
    if install_rc != 0:
        status = "fail"
        severity = "high"
        details = f"install failed rc={install_rc}"
        reason_codes.append("tool_install_failed")
    elif health_rc != 0:
        status = "fail"
        severity = "high"
        details = f"health failed rc={health_rc}"
        reason_codes.append("tool_health_failed")

    tool_rows.append(
        {
            "tool": name,
            "version": str(spec.get("version", "")),
            "integration_mode": integration_mode,
            "status": status,
            "severity": severity,
            "details": details,
            "install_rc": install_rc,
            "health_rc": health_rc,
            "install_output": install_out[:500],
            "health_output": health_out[:500],
        }
    )

    # Only render MCP tools to IDE configs
    if integration_mode == "mcp":
        for ide in target_ides:
            servers_by_ide.setdefault(ide, {})
            servers_by_ide[ide][name] = entry

file_rows = []
for ide, path_raw in sorted(write_paths.items()):
    path = Path(path_raw).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    expected = servers_by_ide.get(ide, {})
    expected_names = sorted(expected.keys())

    status = "pass"
    severity = "low"
    details = "in sync"

    if mode in ("apply", "repair"):
        try:
            if not path.exists():
                tpl = template_for_ide(ide, path)
                if tpl is not None:
                    atomic_write(path, tpl.read_text(encoding="utf-8"))
            if path.suffix.lower() in (".json", ".jsonc"):
                render_json(path, expected, ide)
            elif path.suffix.lower() == ".toml":
                render_toml(path, expected)
            elif path.suffix.lower() == ".md":
                render_markdown(path, ide, expected_names)
            else:
                status = "warn"
                severity = "medium"
                details = f"unsupported render extension: {path.suffix}"
                reason_codes.append("unsupported_render_extension")
        except Exception as exc:
            status = "fail"
            severity = "high"
            details = f"render failed: {exc}"
            reason_codes.append("ide_render_failed")

    try:
        ok = False
        msg = ""
        if path.suffix.lower() in (".json", ".jsonc"):
            ok, msg = check_json_has_servers(path, expected_names, ide)
        elif path.suffix.lower() == ".toml":
            ok, msg = check_toml_has_servers(path, expected_names)
        elif path.suffix.lower() == ".md":
            ok, msg = check_markdown_managed(path)
        else:
            ok = path.exists()
            msg = "ok" if ok else "missing file"

        if not ok:
            status = "fail"
            severity = "high"
            details = msg
            reason_codes.append("ide_config_drift")
    except Exception as exc:
        status = "fail"
        severity = "high"
        details = f"validation failed: {exc}"
        reason_codes.append("ide_validation_failed")

    row = {
        "ide": ide,
        "path": str(path),
        "status": status,
        "severity": severity,
        "details": details,
        "managed_tools": expected_names,
        "hash": sha256_file(path) if path.exists() else "",
    }
    file_rows.append(row)

for ide, artifacts in sorted(canon_artifacts.items()):
    for ap in artifacts:
        if any(r.get("path") == ap and r.get("ide") == ide for r in file_rows):
            continue
        p = Path(ap)
        status = "pass" if p.exists() else "fail"
        if status == "fail":
            reason_codes.append("missing_canonical_artifact")
        file_rows.append(
            {
                "ide": ide,
                "path": str(p),
                "status": status,
                "severity": "medium" if status == "fail" else "low",
                "details": "present" if status == "pass" else "missing canonical artifact",
                "managed_tools": [],
                "hash": sha256_file(p) if p.exists() else "",
            }
        )

# FAIL-OPEN BUG FIX: Count tools separately (must include tool health in overall)
tools_pass = sum(1 for r in tool_rows if r["status"] == "pass")
tools_warn = sum(1 for r in tool_rows if r["status"] == "warn")
tools_fail = sum(1 for r in tool_rows if r["status"] == "fail")

# Count files separately
files_pass = sum(1 for r in file_rows if r["status"] == "pass")
files_warn = sum(1 for r in file_rows if r["status"] == "warn")
files_fail = sum(1 for r in file_rows if r["status"] == "fail")

# Aggregate counts for summary
pass_count = tools_pass + files_pass
warn_count = tools_warn + files_warn
fail_count = tools_fail + files_fail

# Overall status MUST include tool failures (fail-closed, not fail-open)
overall = "green"
if tools_fail > 0 or files_fail > 0:
    overall = "red"
elif tools_warn > 0 or files_warn > 0:
    overall = "yellow"

if not reason_codes:
    reason_codes.append("ok")

payload = {
    "mode": "mcp-tools-sync",
    "generated_at": now_iso(),
    "generated_at_epoch": int(dt.datetime.now(dt.timezone.utc).timestamp()),
    "mode_action": mode,
    "overall": overall,
    "status": overall,
    "details": "converged" if overall == "green" else "drift or tool failure detected",
    "reason_code": reason_codes[0],
    "summary": {
        "pass": pass_count,
        "warn": warn_count,
        "fail": fail_count,
        "tools_pass": tools_pass,
        "tools_warn": tools_warn,
        "tools_fail": tools_fail,
        "files_pass": files_pass,
        "files_warn": files_warn,
        "files_fail": files_fail,
        "tools_total": len(tool_rows),
        "files_total": len(file_rows),
    },
    "reason_codes": sorted(set(reason_codes)),
    "tools": tool_rows,
    "files": file_rows,
    "state_paths": {"state_dir": str(state_root), "file": str(state_path)},
}

payload_text = json.dumps(payload, indent=2, sort_keys=False)
atomic_write(state_path, payload_text + "\n")
print(payload_text)

report_lines = []
for row in file_rows:
    report_lines.append(
        "\t".join(
            [
                str(row.get("ide", "")),
                str(row.get("path", "")),
                str(row.get("status", "unknown")),
                str(row.get("details", "")),
            ]
        )
    )
if report_lines:
    lines_path = state_root / "mcp-tools-sync.lines"
    atomic_write(lines_path, "\n".join(report_lines) + "\n")

if overall != "green":
    sys.exit(1)
PY
}

main() {
  parse_args "$@"
  local payload
  if payload="$(run_python)"; then
    if [[ "$OUTPUT_JSON" -eq 1 ]]; then
      printf '%s\n' "$payload"
    fi
    if [[ "$REPORT_LINES" -eq 1 ]]; then
      local lines_file="${STATE_ROOT}/mcp-tools-sync.lines"
      [[ -f "$lines_file" ]] && cat "$lines_file"
    fi
    return 0
  fi

  if [[ "$OUTPUT_JSON" -eq 1 && -f "$STATE_PATH" ]]; then
    cat "$STATE_PATH"
  fi
  if [[ "$REPORT_LINES" -eq 1 ]]; then
    local lines_file="${STATE_ROOT}/mcp-tools-sync.lines"
    [[ -f "$lines_file" ]] && cat "$lines_file"
  fi
  return 1
}

main "$@"
