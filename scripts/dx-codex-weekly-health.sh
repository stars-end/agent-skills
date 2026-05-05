#!/usr/bin/env bash
#
# dx-codex-weekly-health.sh
#
# Read-only weekly Codex fleet health digest.
# Designed to run from macmini and summarize canonical VM state for Codex.
#
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${DX_CODEX_HEALTH_STATE_DIR:-$HOME/.dx-state/codex-weekly-health}"
STATE_JSON="${STATE_DIR}/last.json"
OUTPUT_FORMAT="text"
HOST_FILTER=""
SSH_TIMEOUT_SECONDS="${DX_CODEX_HEALTH_SSH_TIMEOUT_SECONDS:-15}"
STALE_BROWSER_SECONDS="${DX_CODEX_HEALTH_STALE_BROWSER_SECONDS:-21600}"
APP_SERVER_WARN_SECONDS="${DX_CODEX_HEALTH_APP_SERVER_WARN_SECONDS:-86400}"
REPAIR_REPORT_STALE_SECONDS="${DX_CODEX_HEALTH_REPAIR_REPORT_STALE_SECONDS:-172800}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

usage() {
  cat <<'EOF'
Usage: dx-codex-weekly-health.sh [--json] [--state-dir PATH] [--host HOST]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --state-dir)
        STATE_DIR="$2"
        STATE_JSON="${STATE_DIR}/last.json"
        shift 2
        ;;
      --host)
        HOST_FILTER="$2"
        shift 2
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

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
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
  printf '%s\n' "${USER:-fengning}@${host_key}"
}

fleet_local_host() {
  if [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    case "${CANONICAL_HOST_KEY}" in
      macmini|homedesktop-wsl|epyc6|epyc12)
        echo "${CANONICAL_HOST_KEY}"
        return 0
        ;;
    esac
  fi
  local current_host
  current_host="$(hostname -s 2>/dev/null | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')"
  case "$current_host" in
    *macmini*|fengs-mac-mini-3*) echo "macmini" ;;
    *homedesktop*|windows-r2qk3b1*) echo "homedesktop-wsl" ;;
    *epyc12*|v2202601262171429561*) echo "epyc12" ;;
    *epyc6*|v2202509262171386004*) echo "epyc6" ;;
    *) echo "local" ;;
  esac
}

collect_hosts() {
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

  local out=()
  for host in "${hosts[@]}"; do
    if [[ -n "$HOST_FILTER" && "$host" != "$HOST_FILTER" ]]; then
      continue
    fi
    out+=("$host")
  done
  printf '%s\n' "${out[@]}"
}

probe_script() {
  cat <<'REMOTE'
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

host_name="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
host_user="$(whoami 2>/dev/null || echo unknown)"
codex_version="$(codex --version 2>/dev/null | head -n1 || true)"
if [[ -z "$codex_version" ]]; then
  codex_version="unavailable"
fi

app_fields="$(ps -eo pid=,etimes=,%cpu=,%mem=,args= 2>/dev/null | awk '/codex app-server --listen unix:\/\// && !/awk/ {print $1 "|" $2 "|" $3 "|" $4 "|" substr($0, index($0,$5)); exit}' || true)"
if [[ -n "$app_fields" ]]; then
  app_server_present=1
  IFS='|' read -r app_pid app_age app_cpu app_mem app_cmd <<<"$app_fields"
else
  app_server_present=0
  app_pid=""
  app_age=""
  app_cpu=""
  app_mem=""
  app_cmd=""
fi

stale_agent_browser="$(ps -eo etimes=,tty=,args= 2>/dev/null | awk -v threshold="${STALE_BROWSER_SECONDS}" '$2=="?" && $1>threshold && $0 ~ /(^|[[:space:]])agent-browser([[:space:]]|$)/ {c++} END{print c+0}' || true)"
stale_headless_chrome="$(ps -eo etimes=,tty=,args= 2>/dev/null | awk -v threshold="${STALE_BROWSER_SECONDS}" '$2=="?" && $1>threshold && ($0 ~ /(chrome|chromium|chrome-headless-shell)/) && $0 ~ /--headless/ {c++} END{print c+0}' || true)"

repair_json_path="$HOME/.dx-state/codex-session-repair/last.json"
repair_info="$(python3 - "$repair_json_path" <<'PY'
from __future__ import annotations
import json
import os
import sys
from datetime import datetime, timezone

path = sys.argv[1]
payload = {
    "present": False,
    "age_seconds": None,
    "candidate_files": None,
    "repaired_files": None,
    "skipped_files": None,
    "scanned_files": None,
}
if os.path.exists(path):
    payload["present"] = True
    try:
        st = os.stat(path)
        payload["age_seconds"] = int(datetime.now(timezone.utc).timestamp() - st.st_mtime)
    except Exception:
        payload["age_seconds"] = None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        for key in ("candidate_files", "repaired_files", "skipped_files", "scanned_files"):
            payload[key] = data.get(key)
    except Exception:
        pass
print(json.dumps(payload, separators=(",", ":")))
PY
)"

CODEX_HEALTH_HOST_NAME="$host_name" \
CODEX_HEALTH_HOST_USER="$host_user" \
CODEX_HEALTH_CODEX_VERSION="$codex_version" \
CODEX_HEALTH_APP_SERVER_PRESENT="$app_server_present" \
CODEX_HEALTH_APP_PID="$app_pid" \
CODEX_HEALTH_APP_AGE="$app_age" \
CODEX_HEALTH_APP_CPU="$app_cpu" \
CODEX_HEALTH_APP_MEM="$app_mem" \
CODEX_HEALTH_APP_CMD="$app_cmd" \
CODEX_HEALTH_STALE_AGENT_BROWSER="$stale_agent_browser" \
CODEX_HEALTH_STALE_HEADLESS_CHROME="$stale_headless_chrome" \
CODEX_HEALTH_REPAIR_INFO="$repair_info" \
python3 - <<'PY'
from __future__ import annotations
import json
import os

payload = {
    "host_name": os.environ.get("CODEX_HEALTH_HOST_NAME", "unknown"),
    "host_user": os.environ.get("CODEX_HEALTH_HOST_USER", "unknown"),
    "codex_version": os.environ.get("CODEX_HEALTH_CODEX_VERSION", "unavailable"),
    "app_server": {
        "present": os.environ.get("CODEX_HEALTH_APP_SERVER_PRESENT", "0") == "1",
        "pid": os.environ.get("CODEX_HEALTH_APP_PID") or None,
        "age_seconds": int(os.environ["CODEX_HEALTH_APP_AGE"]) if os.environ.get("CODEX_HEALTH_APP_AGE") else None,
        "cpu_percent": os.environ.get("CODEX_HEALTH_APP_CPU") or None,
        "mem_percent": os.environ.get("CODEX_HEALTH_APP_MEM") or None,
        "command": os.environ.get("CODEX_HEALTH_APP_CMD") or None,
    },
    "stale_agent_browser": int(os.environ.get("CODEX_HEALTH_STALE_AGENT_BROWSER", "0")),
    "stale_headless_chrome": int(os.environ.get("CODEX_HEALTH_STALE_HEADLESS_CHROME", "0")),
    "session_repair": json.loads(os.environ.get("CODEX_HEALTH_REPAIR_INFO", "{}") or "{}"),
}
print(json.dumps(payload, separators=(",", ":")))
PY
REMOTE
}

run_probe() {
  local host="$1"
  local local_host="$2"
  local target
  local script_body
  target="$(canonical_host_to_target "$host")"
  script_body="$(probe_script)"

  if [[ "$host" == "$local_host" ]]; then
    STALE_BROWSER_SECONDS="$STALE_BROWSER_SECONDS" bash -s <<<"$script_body"
    return 0
  fi

  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_TIMEOUT_SECONDS" \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=2 \
    "$target" \
    "STALE_BROWSER_SECONDS='$STALE_BROWSER_SECONDS' bash -s" <<<"$script_body"
}

host_status_from_json() {
  local host_json="$1"
  APP_SERVER_WARN_SECONDS="$APP_SERVER_WARN_SECONDS" \
  REPAIR_REPORT_STALE_SECONDS="$REPAIR_REPORT_STALE_SECONDS" \
  python3 - <<'PY' "$host_json"
from __future__ import annotations
import json
import os
import sys

payload = json.loads(sys.argv[1])
warn_app_server = int(os.environ.get("APP_SERVER_WARN_SECONDS", "86400"))
warn_repair = int(os.environ.get("REPAIR_REPORT_STALE_SECONDS", "172800"))

status = "ok"
reasons: list[str] = []

if not payload.get("reachable", True):
    status = "fail"
    reasons.append("unreachable")
elif payload.get("codex_version") in (None, "", "unavailable"):
    status = "fail"
    reasons.append("codex unavailable")

app = payload.get("app_server") or {}
repair = payload.get("session_repair") or {}

if status != "fail":
    if (payload.get("stale_agent_browser") or 0) > 0:
        status = "warn"
        reasons.append("stale agent-browser")
    if (payload.get("stale_headless_chrome") or 0) > 0:
        status = "warn"
        reasons.append("stale headless chrome")
    if app.get("present") and isinstance(app.get("age_seconds"), int) and app["age_seconds"] > warn_app_server:
        status = "warn"
        reasons.append("old app-server")
    if not repair.get("present", False):
        status = "warn"
        reasons.append("missing repair report")
    elif isinstance(repair.get("age_seconds"), int) and repair["age_seconds"] > warn_repair:
        status = "warn"
        reasons.append("stale repair report")

print(json.dumps({"status": status, "reasons": reasons}, separators=(",", ":")))
PY
}

build_host_json() {
  local host="$1"
  local local_host="$2"
  local probe_output probe_rc target
  target="$(canonical_host_to_target "$host")"
  set +e
  probe_output="$(run_probe "$host" "$local_host" 2>&1)"
  probe_rc=$?
  set -e

  if [[ "$probe_rc" -ne 0 ]]; then
    printf '{"host":"%s","ssh_target":"%s","reachable":false,"error":"%s","codex_version":"unavailable","app_server":{"present":false},"stale_agent_browser":0,"stale_headless_chrome":0,"session_repair":{"present":false}}\n' \
      "$(json_escape "$host")" \
      "$(json_escape "$target")" \
      "$(json_escape "$probe_output")"
    return 0
  fi

  python3 - <<'PY' "$host" "$target" "$probe_output"
from __future__ import annotations
import json
import sys

host, target, raw = sys.argv[1], sys.argv[2], sys.argv[3]
lines = [line for line in raw.splitlines() if line.strip()]
payload = lines[-1] if lines else raw
data = json.loads(payload)
data["host"] = host
data["ssh_target"] = target
data["reachable"] = True
print(json.dumps(data, separators=(",", ":")))
PY
}

render_summary() {
  local report_json="$1"
  python3 - <<'PY' "$report_json"
from __future__ import annotations
import json
import os
import sys
from datetime import datetime, timezone

report = json.loads(sys.argv[1])

def human_hours(seconds):
    if seconds is None:
        return "n/a"
    hours = round(float(seconds) / 3600.0, 1)
    return f"{hours}h"

lines = [f"[DX-ALERT][low][codex] Weekly Codex VM health - {report['generated_at']}", ""]
for host in report["hosts"]:
    status = host["status"].upper()
    icon = {"OK": "OK", "WARN": "WARN", "FAIL": "FAIL"}.get(status, status)
    line = f"- {host['host']}: {icon} | codex={host.get('codex_version','unavailable')}"
    app = host.get("app_server") or {}
    if app.get("present"):
        line += f" | app={human_hours(app.get('age_seconds'))}"
    else:
        line += " | app=none"
    line += f" | stale-ab={host.get('stale_agent_browser',0)}"
    line += f" | stale-headless={host.get('stale_headless_chrome',0)}"
    repair = host.get("session_repair") or {}
    if repair.get("present"):
        line += " | repair="
        line += f"cand:{repair.get('candidate_files','?')}"
        line += f"/rep:{repair.get('repaired_files','?')}"
        line += f"/skip:{repair.get('skipped_files','?')}"
    else:
        line += " | repair=missing"
    if host.get("reasons"):
        line += " | " + ", ".join(host["reasons"])
    lines.append(line)

lines.append("")
lines.append(
    f"Summary: ok={report['ok_hosts']} warn={report['warn_hosts']} fail={report['fail_hosts']} "
    f"stale-agent-browser={report['stale_agent_browser_total']} stale-headless={report['stale_headless_total']}"
)
print("\n".join(lines))
PY
}

main() {
  parse_args "$@"
  mkdir -p "$STATE_DIR"

  local local_host
  local_host="$(fleet_local_host)"

  local host rows_json
  local -a rows=()
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    rows+=("$(build_host_json "$host" "$local_host")")
  done < <(collect_hosts)

  rows_json="$(printf '%s\n' "${rows[@]}" | jq -s '.')"

  local enriched_json
  enriched_json="$(
    python3 - <<'PY' "$rows_json"
from __future__ import annotations
import json
import os
import sys
from datetime import datetime, timezone

rows = json.loads(sys.argv[1])
ok_hosts = 0
warn_hosts = 0
fail_hosts = 0
stale_agent_browser_total = 0
stale_headless_total = 0

for row in rows:
    stale_agent_browser_total += int(row.get("stale_agent_browser") or 0)
    stale_headless_total += int(row.get("stale_headless_chrome") or 0)

report = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "channel": os.environ.get("DX_CODEX_HEALTH_SLACK_CHANNEL", "#dx-alerts"),
    "hosts": rows,
    "ok_hosts": ok_hosts,
    "warn_hosts": warn_hosts,
    "fail_hosts": fail_hosts,
    "stale_agent_browser_total": stale_agent_browser_total,
    "stale_headless_total": stale_headless_total,
}
print(json.dumps(report, separators=(",", ":")))
PY
)"

  local tmp_json status_json status reasons
  tmp_json="$enriched_json"
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    status_json="$(host_status_from_json "$(printf '%s' "$tmp_json" | jq -c --arg host "$host" '.hosts[] | select(.host == $host)')")"
    status="$(printf '%s' "$status_json" | jq -r '.status')"
    reasons="$(printf '%s' "$status_json" | jq -c '.reasons')"
    tmp_json="$(printf '%s' "$tmp_json" | jq -c --arg host "$host" --arg status "$status" --argjson reasons "$reasons" '
      .hosts |= map(if .host == $host then . + {status:$status,reasons:$reasons} else . end)
    ')"
  done < <(collect_hosts)

  tmp_json="$(printf '%s' "$tmp_json" | jq -c '
    .ok_hosts = ([.hosts[] | select(.status == "ok")] | length)
    | .warn_hosts = ([.hosts[] | select(.status == "warn")] | length)
    | .fail_hosts = ([.hosts[] | select(.status == "fail")] | length)
  ')"

  local summary_text final_json
  summary_text="$(render_summary "$tmp_json")"
  final_json="$(printf '%s' "$tmp_json" | jq -c --arg summary "$summary_text" '. + {summary_text:$summary}')"

  printf '%s\n' "$final_json" > "$STATE_JSON"

  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '%s\n' "$final_json"
  else
    printf '%s\n' "$summary_text"
  fi
}

main "$@"
