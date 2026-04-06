#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
dx-cass-evidence.sh

Safe evidence wrapper for cass-memory pilot retrieval and feedback.

Usage:
  dx-cass-evidence.sh start --client <client> --task "<task>" [--repo <repo>] [--workspace <path>] [--session <path>]
  dx-cass-evidence.sh finish --client <client> [--repo <repo>] [--workspace <path>] [--task "<task>"] [--run-id <id>] --no-effect
  dx-cass-evidence.sh finish --client <client> [--repo <repo>] [--workspace <path>] [--task "<task>"] [--run-id <id>] --bullet-id <id> [--bullet-id <id>] (--helpful | --harmful) [--reason "<text>"] [--session <path>]
  dx-cass-evidence.sh status [--days <n>] [--json]

Notes:
  - `start` runs `cm context "<task>" --json`, logs retrieval metadata, and prints the original cm JSON to stdout unchanged.
  - `finish` records either a structured `no_effect` event or executes `cm mark` for the provided bullet ids before logging feedback metadata.
  - Event log path defaults to: ~/.cass-memory/evidence/events.jsonl
EOF
}

die() {
  echo "dx-cass-evidence: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

json_string() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 2; }
shift || true

EVENT_ROOT="${DX_CASS_EVIDENCE_DIR:-$HOME/.cass-memory/evidence}"
EVENT_LOG="${DX_CASS_EVIDENCE_LOG:-$EVENT_ROOT/events.jsonl}"
RUN_DIR="${DX_CASS_EVIDENCE_RUN_DIR:-$EVENT_ROOT/runs}"
mkdir -p "$RUN_DIR"
touch "$EVENT_LOG"

append_event() {
  local json_line="$1"
  python3 - "$EVENT_LOG" "$json_line" <<'PY'
import json
import os
import sys
from pathlib import Path

log_path = Path(sys.argv[1]).expanduser()
payload = json.loads(sys.argv[2])
log_path.parent.mkdir(parents=True, exist_ok=True)
with log_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, sort_keys=True) + "\n")
PY
}

run_cm_mark() {
  local bullet_id="$1"
  local mark_mode="$2"
  local reason_text="${3:-}"
  local session_path="${4:-}"
  local -a cmd=(cm mark "$bullet_id")

  if [[ "$mark_mode" == "helpful" ]]; then
    cmd+=(--helpful)
  else
    cmd+=(--harmful)
  fi
  [[ -n "$reason_text" ]] && cmd+=(--reason "$reason_text")
  [[ -n "$session_path" ]] && cmd+=(--session "$session_path")

  "${cmd[@]}" >/dev/null
}

build_event_json() {
  python3 - "$@" <<'PY'
import datetime as dt
import hashlib
import json
import sys

args = sys.argv[1:]
payload = {}
it = iter(args)
for key in it:
    value = next(it)
    if value == "__JSON_ARRAY__":
      payload[key] = json.loads(next(it))
    elif value == "__JSON_NULL__":
      payload[key] = None
    else:
      payload[key] = value

task = payload.get("task")
payload["timestamp_utc"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
if task:
    payload["task_sha256"] = hashlib.sha256(task.encode("utf-8")).hexdigest()
print(json.dumps(payload, sort_keys=True))
PY
}

default_repo() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" ]]; then
    basename "$top"
  else
    basename "$PWD"
  fi
}

default_workspace() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

case "$cmd" in
  start)
    require_cmd cm
    require_cmd python3
    client=""
    task=""
    repo="$(default_repo)"
    workspace="$(default_workspace)"
    session=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --client) client="${2:-}"; shift 2 ;;
        --task) task="${2:-}"; shift 2 ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --workspace) workspace="${2:-}"; shift 2 ;;
        --session) session="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown arg for start: $1" ;;
      esac
    done

    [[ -n "$client" ]] || die "start requires --client"
    [[ -n "$task" ]] || die "start requires --task"

    raw_output="$(cm context "$task" --json)"
    analysis="$(
      python3 - "$raw_output" <<'PY'
import json
import sys
import uuid

payload = json.loads(sys.argv[1])
data = payload.get("data") or {}
bullets = data.get("relevantBullets") or []
history = data.get("historySnippets") or []
result = {
    "run_id": str(uuid.uuid4()),
    "bullet_ids": [b.get("id") for b in bullets if b.get("id")],
    "bullet_count": len([b for b in bullets if b.get("id")]),
    "history_snippet_count": len(history),
}
print(json.dumps(result))
PY
    )"

    run_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["run_id"])' "$analysis")"
    bullet_ids_json="$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["bullet_ids"]))' "$analysis")"
    bullet_count="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["bullet_count"])' "$analysis")"
    history_count="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["history_snippet_count"])' "$analysis")"

    event_json="$(build_event_json \
      event retrieval \
      run_id "$run_id" \
      client "$client" \
      repo "$repo" \
      workspace "$workspace" \
      task "$task" \
      session_path "${session:-__JSON_NULL__}" \
      bullet_ids __JSON_ARRAY__ "$bullet_ids_json" \
      bullet_count "$bullet_count" \
      history_snippet_count "$history_count" \
      event_log "$EVENT_LOG")"
    append_event "$event_json"

    cat > "$RUN_DIR/$run_id.json" <<EOF
$event_json
EOF

    echo "dx-cass-evidence run_id=$run_id bullet_count=$bullet_count log=$EVENT_LOG" >&2
    printf '%s\n' "$raw_output"
    ;;

  finish)
    require_cmd python3
    client=""
    repo="$(default_repo)"
    workspace="$(default_workspace)"
    task=""
    run_id=""
    session=""
    reason=""
    mode=""
    declare -a bullet_ids=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --client) client="${2:-}"; shift 2 ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --workspace) workspace="${2:-}"; shift 2 ;;
        --task) task="${2:-}"; shift 2 ;;
        --run-id) run_id="${2:-}"; shift 2 ;;
        --session) session="${2:-}"; shift 2 ;;
        --reason) reason="${2:-}"; shift 2 ;;
        --bullet-id) bullet_ids+=("${2:-}"); shift 2 ;;
        --helpful) mode="helpful"; shift ;;
        --harmful) mode="harmful"; shift ;;
        --no-effect) mode="no_effect"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown arg for finish: $1" ;;
      esac
    done

    [[ -n "$client" ]] || die "finish requires --client"
    [[ -n "$mode" ]] || die "finish requires one of --helpful, --harmful, or --no-effect"

    if [[ "$mode" == "no_effect" ]]; then
      [[ "${#bullet_ids[@]}" -eq 0 ]] || die "--no-effect cannot be combined with --bullet-id"
    else
      require_cmd cm
      [[ "${#bullet_ids[@]}" -gt 0 ]] || die "$mode requires at least one --bullet-id"
      for bullet_id in "${bullet_ids[@]}"; do
        run_cm_mark "$bullet_id" "$mode" "$reason" "$session"
      done
    fi

    bullet_ids_json="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${bullet_ids[@]}")"
    event_type="feedback"
    [[ "$mode" == "no_effect" ]] && event_type="no_effect"
    event_json="$(build_event_json \
      event "$event_type" \
      feedback_type "$mode" \
      run_id "${run_id:-__JSON_NULL__}" \
      client "$client" \
      repo "$repo" \
      workspace "$workspace" \
      task "${task:-__JSON_NULL__}" \
      session_path "${session:-__JSON_NULL__}" \
      reason "${reason:-__JSON_NULL__}" \
      bullet_ids __JSON_ARRAY__ "$bullet_ids_json" \
      bullet_count "${#bullet_ids[@]}" \
      event_log "$EVENT_LOG")"
    append_event "$event_json"

    python3 - "$mode" "$event_json" <<'PY'
import json
import sys
print(json.dumps({
    "success": True,
    "command": "dx-cass-evidence-finish",
    "data": {
        "feedbackType": sys.argv[1],
        "event": json.loads(sys.argv[2]),
    },
}, sort_keys=True))
PY
    ;;

  status)
    require_cmd python3
    days="30"
    as_json=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --days) days="${2:-}"; shift 2 ;;
        --json) as_json=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown arg for status: $1" ;;
      esac
    done

    python3 - "$EVENT_LOG" "$days" "$as_json" <<'PY'
import datetime as dt
import json
import sys
from collections import Counter
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
days = int(sys.argv[2])
as_json = sys.argv[3] == "1"
cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
events = []
if path.exists():
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = item.get("timestamp_utc")
            try:
                when = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except Exception:
                continue
            if when >= cutoff:
                events.append(item)

by_event = Counter(e.get("event", "unknown") for e in events)
by_feedback = Counter(e.get("feedback_type", "none") for e in events if e.get("event") in {"feedback", "no_effect"})
by_client = Counter(e.get("client", "unknown") for e in events)
summary = {
    "success": True,
    "command": "dx-cass-evidence-status",
    "data": {
        "days": days,
        "eventLog": str(path),
        "totalEvents": len(events),
        "byEvent": dict(sorted(by_event.items())),
        "byFeedbackType": dict(sorted(by_feedback.items())),
        "byClient": dict(sorted(by_client.items())),
    },
}
if as_json:
    print(json.dumps(summary, sort_keys=True))
else:
    print(f"event_log={path}")
    print(f"days={days} total_events={len(events)}")
    print(f"by_event={dict(sorted(by_event.items()))}")
    print(f"by_feedback_type={dict(sorted(by_feedback.items()))}")
    print(f"by_client={dict(sorted(by_client.items()))}")
PY
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    usage
    exit 2
    ;;
esac
