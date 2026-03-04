#!/usr/bin/env bash
# dx-fleet-install.sh
# Fleet Sync V2.1 install/check/repair/uninstall surface.
#
# Notes:
# - Local-first execution: tools are installed/validated on each VM.
# - No central MCP gateway is required.
# - Shared state is optional and limited to local hash/tool-health snapshots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FLEET_MANIFEST="${ROOT_DIR}/configs/fleet-sync.manifest.yaml"
MCP_MANIFEST="${ROOT_DIR}/configs/mcp-tools.yaml"
MODE="check"
UNINSTALL=0
JSON_ONLY=0
FORCE_NO_AUTH=0
STATE_DIR="${HOME}/.dx-state/fleet-sync"
STATE_JSON="${STATE_DIR}/ide-config-state.json"

usage() {
  cat <<'USAGE'
Usage:
  dx-fleet-install.sh [--check|--apply|--uninstall]
    [--manifest PATH] [--mcp-manifest PATH]
    [--state-dir PATH] [--json] [--force-no-auth]
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
    --uninstall)
      MODE="apply"
      UNINSTALL=1
      shift
      ;;
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
      STATE_JSON="${STATE_DIR}/ide-config-state.json"
      shift 2
      ;;
    --json)
      JSON_ONLY=1
      shift
      ;;
    --force-no-auth)
      FORCE_NO_AUTH=1
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

[[ -f "$FLEET_MANIFEST" ]] || { echo "Missing manifest: $FLEET_MANIFEST" >&2; exit 1; }
[[ -f "$MCP_MANIFEST" ]] || { echo "Missing MCP manifest: $MCP_MANIFEST" >&2; exit 1; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

if ! python3 - <<'PY'
import importlib
import sys

mods = ["yaml"]
missing = []
for mod in mods:
    try:
        importlib.import_module(mod)
    except ModuleNotFoundError:
        missing.append(mod)

try:
    importlib.import_module("tomllib")
except ModuleNotFoundError:
    try:
        importlib.import_module("tomli")
    except ModuleNotFoundError:
        missing.append("tomllib (or tomli)")

try:
    importlib.import_module("toml")
except ModuleNotFoundError:
    missing.append("toml")

if missing:
    print("Missing Python modules: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
then
  echo "Unable to run Fleet Sync install path: missing required Python modules." >&2
  echo "Install with: pip3 install pyyaml toml tomli" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

if [[ "$UNINSTALL" -eq 1 ]]; then
  AUTH_OP_READY=1
  AUTH_OP_REASON="skipped_for_uninstall"
  AUTH_RAILWAY_READY=1
  AUTH_RAILWAY_REASON="skipped_for_uninstall"
elif [[ "$FORCE_NO_AUTH" -eq 1 ]]; then
  AUTH_OP_READY=1
  AUTH_OP_REASON="skipped"
  AUTH_RAILWAY_READY=1
  AUTH_RAILWAY_REASON="skipped"
else
  AUTH_OP_READY=0
  AUTH_RAILWAY_READY=0
  AUTH_OP_REASON="missing_binary"
  AUTH_RAILWAY_REASON="missing_binary"

  if command -v op >/dev/null 2>&1; then
    if op whoami >/dev/null 2>&1; then
      AUTH_OP_READY=1
      AUTH_OP_REASON="ok"
    else
      AUTH_OP_REASON="not_authenticated"
    fi
  fi

  if command -v railway >/dev/null 2>&1; then
    if railway whoami >/dev/null 2>&1; then
      AUTH_RAILWAY_READY=1
      AUTH_RAILWAY_REASON="ok"
    else
      AUTH_RAILWAY_REASON="not_authenticated"
    fi
  fi
fi

if [[ "$UNINSTALL" -eq 1 ]]; then
  TOOL_CMD=("$SCRIPT_DIR/dx-mcp-tools-sync.sh" --check --json --manifest "$MCP_MANIFEST")
else
  if [[ "$MODE" == "apply" ]]; then
    TOOL_CMD=("$SCRIPT_DIR/dx-mcp-tools-sync.sh" --apply --json --manifest "$MCP_MANIFEST")
  else
    TOOL_CMD=("$SCRIPT_DIR/dx-mcp-tools-sync.sh" --check --json --manifest "$MCP_MANIFEST")
  fi
fi

if ! TOOL_STATE_RAW="$(${TOOL_CMD[@]})"; then
  # Keep a usable placeholder for deterministic downstream parsing.
  TOOL_STATE_RAW='{"overall_ok":false,"tools_ok":false,"dolt_ok":"false","tools":[]}'
fi

printf '%s\n' "$TOOL_STATE_RAW" > "$STATE_JSON"

python3 - "$STATE_DIR" "$ROOT_DIR" "$FLEET_MANIFEST" "$MCP_MANIFEST" "$STATE_JSON" "$UNINSTALL" "$MODE" "$STATE_JSON" "$AUTH_OP_READY" "$AUTH_OP_REASON" "$AUTH_RAILWAY_READY" "$AUTH_RAILWAY_REASON" <<'PY'
import hashlib
import json
import os
import socket
import sys
from copy import deepcopy
from pathlib import Path

import yaml

try:
    import tomllib
except Exception:  # pragma: no cover
    import tomli as tomllib

try:
    import toml
except Exception as exc:  # pragma: no cover
    print(f"toml python package required: {exc}", file=sys.stderr)
    raise SystemExit(1)

state_dir = Path(sys.argv[1])
root_dir = Path(sys.argv[2])
fleet_manifest_path = Path(sys.argv[3])
mcp_manifest_path = Path(sys.argv[4])
out_path = Path(sys.argv[5])
uninstall = sys.argv[6] == "1"
mode = sys.argv[7]
state_path = Path(sys.argv[8])
auth_op_ready = sys.argv[9] == "1"
auth_op_reason = sys.argv[10]
auth_railway_ready = sys.argv[11] == "1"
auth_railway_reason = sys.argv[12]

def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def read_json_or_yaml(path: Path):
    if not path.exists():
        return {}
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return {}
    if path.suffix.lower() == ".toml":
        return tomllib.loads(raw)
    if path.suffix.lower() in (".yml", ".yaml"):
        return yaml.safe_load(raw) or {}

    try:
        return json.loads(raw)
    except Exception:
        try:
            return tomllib.loads(raw)
        except Exception:
            return {}


def read_text_or_default(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def write_atomic(path: Path, contents: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".fleet-sync.tmp")
    tmp.write_text(contents, encoding="utf-8")
    tmp.replace(path)


def dump_payload(path: Path, payload: dict) -> str:
    if path.suffix.lower() == ".toml":
        return toml.dumps(payload)
    return json.dumps(payload, sort_keys=True, indent=2) + "\n"


def normalize_file_type(path: Path) -> str:
    if path.suffix.lower() == ".toml":
        return "toml"
    return "json"


def load_manifest(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fp:
        return yaml.safe_load(fp) or {}


def merge_dict(base: dict, override: dict) -> dict:
    merged = deepcopy(base)
    for key, value in (override or {}).items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_dict(merged[key], value)
        else:
            merged[key] = value
    return merged


def backup_path_for(target: Path) -> Path:
    safe_name = str(target).replace("/", "_")
    return state_dir / "backups" / f"{safe_name}.bak"


def parse_template(path: Path) -> dict:
    if not path.exists():
        return {}
    data = read_json_or_yaml(path)
    return data if isinstance(data, dict) else {}


def normalize_mcp_servers(payload: dict) -> dict:
    if not isinstance(payload, dict):
        return {}
    mcp_servers = payload.get("mcpServers")
    if isinstance(mcp_servers, dict):
        return mcp_servers
    legacy = payload.get("mcp_servers")
    if isinstance(legacy, dict):
        return legacy
    return {}


def write_backed_content(path: Path, payload: dict) -> str:
    dumped = dump_payload(path, payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    return dumped


def render_target(
    target: str,
    managed_tools: dict,
    target_alias: str,
    mode: str,
    uninstall: bool,
    template_candidate: Path,
) -> dict:
    path = Path(target).expanduser()
    file_type = normalize_file_type(path)
    current = read_json_or_yaml(path)
    if not isinstance(current, dict):
        current = {}

    template = parse_template(template_candidate)

    # Patch-merge behavior:
    # - start from template
    # - apply current config to preserve user and environment-specific entries
    # - then enforce managed MCP entries.
    expected = merge_dict(template, current)
    mcp_servers = normalize_mcp_servers(expected)
    if not isinstance(mcp_servers, dict):
        mcp_servers = {}

    managed_keys = sorted(managed_tools.keys())
    for name in managed_keys:
        if uninstall:
            mcp_servers.pop(name, None)
        else:
            mcp_servers[name] = managed_tools[name]

    # Remove legacy mcp key and persist canonical key.
    if "mcp_servers" in expected:
        expected.pop("mcp_servers", None)
    expected["mcpServers"] = mcp_servers

    if not mcp_servers:
        expected.pop("mcpServers", None)

    expected_text = write_backed_content(path, expected)
    expected_hash = sha256_text(expected_text)

    current_text = read_text_or_default(path)
    if not current_text and path.exists() and path.suffix.lower() != ".toml":
        current_text = json.dumps(current, sort_keys=True, indent=2) + "\n"
    elif not current_text and path.exists() and path.suffix.lower() == ".toml":
        current_text = toml.dumps(current)

    current_hash = sha256_text(current_text) if path.exists() else ""
    drift = expected_hash != current_hash
    bak = backup_path_for(path)

    status = "ok"
    write_performed = False

    if uninstall:
        if mode == "apply":
            if bak.exists():
                restore_text = bak.read_text(encoding="utf-8")
                write_atomic(path, restore_text)
                current_hash = sha256_text(restore_text)
                status = "restored"
            else:
                # Conservative uninstall fallback: keep file functional by removing only
                # Fleet-managed MCP entries.
                if path.exists():
                    bak.parent.mkdir(parents=True, exist_ok=True)
                    bak.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
                write_atomic(path, expected_text)
                current_hash = expected_hash
                status = "uninstalled"
            write_performed = True
            drift = False
    elif mode == "apply" and drift:
        bak.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            bak.write_text(current_text, encoding="utf-8")
        write_atomic(path, expected_text)
        current_hash = expected_hash
        drift = False
        write_performed = True
        status = "applied"

    if mode != "apply" and drift:
        status = "drift"

    return {
        "path": str(path),
        "ide": target_alias,
        "managed_count": len(managed_keys),
        "managed_tools": managed_keys,
        "expected_hash": expected_hash,
        "current_hash": current_hash,
        "drift": bool(drift),
        "write_performed": write_performed,
        "backup_path": str(bak),
        "status": status,
    }


def manifest_tools_by_ide(manifest: dict) -> dict:
    managed = {}
    for tool_name, tool_cfg in (manifest.get("tools") or {}).items():
        if not isinstance(tool_cfg, dict) or not tool_cfg.get("enabled", False):
            continue
        target_ides = tool_cfg.get("target_ides") or []
        mcp_cfg = tool_cfg.get("mcp") or {}
        if not isinstance(mcp_cfg, dict):
            continue

        args = mcp_cfg.get("args")
        if not isinstance(args, list):
            args = []

        entry = {
            "command": str(mcp_cfg.get("command", "")).strip(),
            "args": list(args),
            "type": str(mcp_cfg.get("type", "stdio")).strip(),
        }
        env = mcp_cfg.get("env")
        if isinstance(env, dict):
            entry["env"] = dict(env)
        if not entry["command"]:
            continue

        for raw_target in target_ides:
            managed.setdefault(str(raw_target), {})
            managed[str(raw_target)][str(tool_name)] = entry

    return managed


def normalize_target_aliases(manifest: dict) -> dict:
    alias = {
        "codex": "codex-cli",
        "claude": "claude-code",
        "codex-cli": "codex-cli",
        "claude-code": "claude-code",
    }
    out = {}

    render_cfg = manifest.get("render") or {}
    write_paths = render_cfg.get("write_paths") or {}
    templates = render_cfg.get("templates") or {}
    if not isinstance(write_paths, dict) or not write_paths:
        write_paths = (manifest.get("ide_configs") or {}).get("targets") or {}
    if not isinstance(templates, dict):
        templates = {}

    for raw_ide, raw_path in (write_paths or {}).items():
        if raw_ide is None:
            continue
        alias_name = alias.get(str(raw_ide), str(raw_ide))
        out[alias_name] = {
            "path": str(Path(os.path.expanduser(str(raw_path))).resolve()),
            "template": templates.get(alias_name) or templates.get(raw_ide) or "",
        }
    return out



def load_tool_state(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as fp:
            return json.load(fp)
    except Exception:
        return {}

fleet_cfg = load_manifest(fleet_manifest_path)
mcp_cfg = load_manifest(mcp_manifest_path)
targets = normalize_target_aliases(fleet_cfg)
managed_by_ide = manifest_tools_by_ide(mcp_cfg)

backups_base = state_dir / "backups"
entries = []

# Ensure explicit target entries exist for each canonical IDE even if not currently mapped.
fallback_paths = {
    "codex-cli": "~/.codex/config.toml",
    "claude-code": "~/.claude.json",
    "antigravity": "~/.gemini/antigravity/mcp_config.json",
    "opencode": "~/.opencode/config.json",
}
for ide_name, raw_path in fallback_paths.items():
    if ide_name not in targets:
        targets[ide_name] = {
            "path": os.path.expanduser(raw_path),
            "template": f"config-templates/fleet-sync-ide.template.json",
        }

for target_alias, target_info in sorted(targets.items()):
    path = target_info.get("path", "")
    if not path:
        continue
    managed = managed_by_ide.get(target_alias, {})

    template_name = target_info.get("template", "").strip()
    template_path = Path(template_name)
    if template_name and not template_path.is_absolute():
        template_path = root_dir / template_name

    entries.append(
        render_target(
            target=path,
            managed_tools=managed,
            target_alias=target_alias,
            mode=mode,
            uninstall=uninstall,
            template_candidate=template_path,
        )
    )

if mode == "apply" and uninstall:
    config_ok = True
else:
    config_ok = all(not entry.get("drift") for entry in entries)

config_overall_ok = all(entry.get("status") in {"ok", "applied", "restored", "uninstalled", "drift"} for entry in entries)

tool_state = load_tool_state(state_path)

auth = {
    "op": {
        "ready": bool(auth_op_ready),
        "reason": auth_op_reason,
    },
    "railway": {
        "ready": bool(auth_railway_ready),
        "reason": auth_railway_reason,
    },
}

if mode == "check":
    auth_ok = bool(auth_op_ready and auth_railway_ready)
else:
    # Apply mode is bounded by auth unless this is uninstall.
    auth_ok = bool(auth_op_ready and auth_railway_ready)

if not tool_state:
    tool_state = {
        "overall_ok": False,
        "tools_ok": False,
        "tools": [],
        "dolt_ok": "unknown",
        "dolt_last_ok_epoch": 0,
    }

if not isinstance(tool_state, dict):
    tool_state = {}

tool_ok = bool(tool_state.get("overall_ok", False))
if uninstall:
    overall_ok = bool(config_ok)
else:
    overall_ok = bool(config_ok and auth_ok and tool_ok)

payload = {
    "generated_at": __import__("datetime")
    .datetime.now(__import__("datetime").timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z"),
    "generated_at_epoch": int(__import__("time").time()),
    "host": socket.gethostname(),
    "mode": mode,
    "uninstall": uninstall,
    "overall_ok": overall_ok,
    "auth": auth,
    "configs": {
        "overall_ok": bool(config_overall_ok),
        "count": len(entries),
        "drift_count": int(sum(1 for e in entries if e.get("drift"))),
        "entries": entries,
    },
    "tools": tool_state,
}

out_path.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY

if [[ "$JSON_ONLY" -eq 1 ]]; then
  cat "$STATE_JSON"
  if [[ "$(python3 - "$STATE_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)
print('true' if payload.get('overall_ok') else 'false')
PY
)" != "true" ]]; then
    exit 1
  fi
  exit 0
fi

python3 - "$STATE_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)

configs = payload.get("configs", {})
tools = payload.get("tools", {})
auth = payload.get("auth", {})
print(f"Fleet Sync ({payload.get('mode')})")
print(f"Generated: {payload.get('generated_at')}")
print(f"Overall: {'true' if payload.get('overall_ok') else 'false'}")
print(f"Config drift: {configs.get('drift_count', 0)} / {configs.get('count', 0)}")
print(f"Tools overall: {tools.get('overall_ok', False)}")
print(f"Tool rows: {len(tools.get('tools', []) ) if isinstance(tools, dict) else 0}")
print(f"Auth op: {'ok' if auth.get('op', {}).get('ready') else 'bad'} ({auth.get('op', {}).get('reason', '')})")
print(f"Auth railway: {'ok' if auth.get('railway', {}).get('ready') else 'bad'} ({auth.get('railway', {}).get('reason', '')})")
PY

if [[ "$(python3 - "$STATE_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as fp:
    payload = json.load(fp)
print('0' if payload.get('overall_ok') else '1')
PY
)" != "0" ]]; then
  exit 1
fi

exit 0
