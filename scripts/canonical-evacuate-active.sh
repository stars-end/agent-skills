#!/usr/bin/env bash
#
# canonical-evacuate-active.sh - Active-hours canonical enforcer (V8.3.x)
#
# Purpose
# - Keep canonical working trees from staying dirty/stale during active hours.
# - Preserve work safely (commit-aware evacuation) and then reset canonicals to origin/master.
#
# Policy (defaults tuned for deterministic SLO with 15-min cadence)
# - Warn once at >=15m dirty
# - Evacuate at >=45m dirty (worst-case <=60m with */15 cadence)
# - Immediate evacuate if commits exist in canonical (ahead of origin/master)
#
# Invariants
# - NEVER reset canonical unless rescue branch push succeeded.
# - ALWAYS respect session locks and git index locks.
#
# Intended to run via cron with:
#   CRON_TZ=America/Los_Angeles
#   */15 5-16 * * * dx-job-wrapper.sh canonical-evacuate -- ~/agent-skills/scripts/canonical-evacuate-active.sh
#   0 17 * * * dx-job-wrapper.sh canonical-evacuate -- ~/agent-skills/scripts/canonical-evacuate-active.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STATE_DIR="$HOME/.dx-state"
STATE_FILE="$STATE_DIR/dirty-incidents.json"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"

LOG_DIR="$HOME/logs/dx"
LOG_FILE="$LOG_DIR/canonical-evacuate.log"
FETCH_ERR_LOG="$LOG_DIR/fetch-errors.log"

CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")

DIRTY_WARN_MINUTES="${DIRTY_WARN_MINUTES:-15}"
DIRTY_EVICT_MINUTES="${DIRTY_EVICT_MINUTES:-45}"
DIVERGED_EVICT_MINUTES="${DIVERGED_EVICT_MINUTES:-0}"

SLACK_CHANNEL_ID="${DX_ALERTS_CHANNEL_ID:-C0ADSSZV9M2}"

mkdir -p "$STATE_DIR" "$LOG_DIR"
touch "$RECOVERY_LOG"
touch "$FETCH_ERR_LOG"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

now_epoch() {
  date +%s
}

short_host() {
  hostname 2>/dev/null | cut -d'.' -f1
}

iso_timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

is_locked() {
  local repo_path="$1"

  [[ -f "$repo_path/.git/index.lock" ]] && return 0

  if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
    if "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$repo_path" >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

slack_send() {
  local msg="$1"

  # Prefer OpenClaw via mise (same pattern as dx-alerts-digest.sh / dx-job-wrapper.sh).
  if [[ -x "$HOME/.local/bin/mise" ]]; then
    if "$HOME/.local/bin/mise" x node@22.21.1 -- openclaw message send \
      --channel slack --target "$SLACK_CHANNEL_ID" --message "$msg" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Fallback: if an openclaw shim is available in PATH.
  if command -v openclaw >/dev/null 2>&1; then
    openclaw message send --channel slack --target "$SLACK_CHANNEL_ID" --message "$msg" >/dev/null 2>&1 && return 0
  fi

  # Last resort: local log only.
  log "ALERT (no slack transport): $msg"
  return 1
}

state_init_if_needed() {
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '{}' >"$STATE_FILE"
  fi
}

state_get_json() {
  local repo="$1"
  state_init_if_needed
  python3 - "$STATE_FILE" "$repo" <<'PY'
import json, os, sys

state_file, repo = sys.argv[1], sys.argv[2]
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}
entry = state.get(repo, {})
print(json.dumps(entry))
PY
}

state_upsert() {
  # Usage: state_upsert repo key=value key=value ...
  local repo="$1"
  shift

  state_init_if_needed
  local now
  now="$(now_epoch)"

  python3 - "$STATE_FILE" "$repo" "$now" "$@" <<'PY'
import json, os, sys
from datetime import datetime, timezone

state_file = sys.argv[1]
repo = sys.argv[2]
now = int(sys.argv[3])
kv = sys.argv[4:]

def parse_iso_z(s):
    try:
        dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return None

def coerce(v: str):
    if v == "true":
        return True
    if v == "false":
        return False
    if v.isdigit():
        return int(v)
    if v.startswith("[") or v.startswith("{"):
        try:
            return json.loads(v)
        except Exception:
            return v
    return v

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}

entry = state.get(repo, {})

# Migration: legacy ISO fields -> epoch
if "first_seen_epoch" not in entry and isinstance(entry.get("first_seen"), str):
    ts = parse_iso_z(entry["first_seen"])
    if ts is not None:
        entry["first_seen_epoch"] = ts
if "last_seen_epoch" not in entry and isinstance(entry.get("last_seen"), str):
    ts = parse_iso_z(entry["last_seen"])
    if ts is not None:
        entry["last_seen_epoch"] = ts

for item in kv:
    if "=" not in item:
        continue
    k, v = item.split("=", 1)
    entry[k] = coerce(v)

entry["last_seen_epoch"] = now
if "first_seen_epoch" in entry and isinstance(entry["first_seen_epoch"], int):
    entry["age_minutes"] = max(0, (now - entry["first_seen_epoch"]) // 60)

state[repo] = entry

tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)
os.replace(tmp, state_file)
PY
}

state_delete_repo() {
  local repo="$1"
  state_init_if_needed
  python3 - "$STATE_FILE" "$repo" <<'PY'
import json, os, sys
state_file, repo = sys.argv[1], sys.argv[2]
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}
if repo in state:
    del state[repo]
tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2, sort_keys=True)
os.replace(tmp, state_file)
PY
}

get_agent_trailer() {
  local repo_path="$1"
  cd "$repo_path"
  git log -1 --format='%(trailers:key=Agent,valueonly)' 2>/dev/null | tr -d '\n' || true
}

has_precommit_hook() {
  local repo_path="$1"
  [[ -f "$repo_path/.git/hooks/pre-commit" ]] || [[ -f "$repo_path/.githooks/pre-commit" ]]
}

get_dirty_paths_json() {
  local repo_path="$1"
  local n="${2:-10}"
  cd "$repo_path"

  # Extract path portion (char 3 onwards); preserve leading spaces via IFS=.
  local paths=()
  local line path
  local i=0
  while IFS= read -r line; do
    path="${line:3}"
    [[ "$path" == *" -> "* ]] && path="${path##* -> }"
    paths+=("$path")
    i=$((i + 1))
    [[ $i -ge $n ]] && break
  done < <(git status --porcelain 2>/dev/null)

  python3 - "${paths[@]}" <<'PY'
import json, sys
print(json.dumps(sys.argv[1:]))
PY
}

get_untracked_count() {
  local repo_path="$1"
  cd "$repo_path"
  git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' '
}

get_diffstat() {
  local repo_path="$1"
  cd "$repo_path"
  local stat
  stat="$(git diff --stat 2>/dev/null | tail -1 || true)"
  if [[ -z "$stat" ]]; then
    echo "0 files"
  else
    echo "$stat"
  fi
}

log_recovery() {
  local repo="$1"
  local rescue_branch="$2"
  local reason="$3"
  local agent="${4:-}"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") | $repo | $rescue_branch | $reason | agent=$agent" >>"$RECOVERY_LOG"
}

send_event_alert() {
  # Dedupe by fingerprint stored in state: last_alert_fingerprint.
  local repo="$1"
  local event="$2"     # first-seen | warn | evacuated | recovered
  local details="$3"   # freeform

  local entry_json
  entry_json="$(state_get_json "$repo")"

  local fingerprint
  fingerprint="$(python3 - "$entry_json" "$event" <<'PY'
import json, sys
entry = json.loads(sys.argv[1] or "{}")
event = sys.argv[2]
first = entry.get("first_seen_epoch") or ""
status = entry.get("status") or ""
print(f"{event}:{status}:{first}")
PY
)"

  local last_fp
  last_fp="$(python3 - "$entry_json" <<'PY'
import json, sys
entry = json.loads(sys.argv[1] or "{}")
print(entry.get("last_alert_fingerprint",""))
PY
)"

  if [[ -n "$last_fp" && "$last_fp" == "$fingerprint" ]]; then
    return 0
  fi

  # Mark fingerprint before sending to avoid duplicate floods on transient send failures.
  state_upsert "$repo" "last_alert_fingerprint=$fingerprint"

  local msg
  msg="$(python3 - "$entry_json" "$event" "$repo" "$details" <<'PY'
import json, sys
entry = json.loads(sys.argv[1] or "{}")
event, repo, details = sys.argv[2], sys.argv[3], sys.argv[4]
age = entry.get("age_minutes", 0)
status = entry.get("status", "clean")
diffstat = entry.get("diffstat", "")
rescue = entry.get("rescue_branch", "")
agent = entry.get("last_commit_agent", "")
ahead = entry.get("ahead", 0)

prefix = "[DX-ALERT][warn][canonical]"
if event in ("evacuated",):
    prefix = "[DX-ALERT][high][canonical]"
elif event in ("recovered",):
    prefix = "[DX-ALERT][info][canonical]"

if event == "first-seen":
    body = f"{repo} became {status} (age: {age}m). {details}".strip()
elif event == "warn":
    body = f"{repo} {status} for {age}m (warn@15m, evict@45m). {diffstat}".strip()
elif event == "evacuated":
    if int(ahead) > 0:
        body = f"{repo} EVACUATED (commits in canonical). Agent: {agent}. Rescue: {rescue}".strip()
    else:
        body = f"{repo} EVACUATED ({status} {age}m). Rescue: {rescue}".strip()
elif event == "recovered":
    body = f"{repo} recovered (now clean).".strip()
else:
    body = f"{repo}: {event}".strip()

print(f"{prefix} {body}")
PY
)"

  slack_send "$msg" || true
  log "ALERT: $msg"
}

evacuate_diverged() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  local host timestamp rescue_branch
  host="$(short_host)"
  timestamp="$(iso_timestamp)"
  rescue_branch="rescue-${host}-${repo}-${timestamp}"

  cd "$repo_path"

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "unknown")"
  local agent
  agent="$(get_agent_trailer "$repo_path")"

  log "Evacuating diverged $repo (branch=$current_branch ahead commits present; agent=$agent)"

  git branch -f "$rescue_branch" HEAD >/dev/null 2>&1 || true

  if git push -u origin "$rescue_branch" --quiet >/dev/null 2>&1; then
    log_recovery "$repo" "$rescue_branch" "diverged" "$agent"
    state_upsert "$repo" "rescue_branch=$rescue_branch" "evacuated_at_epoch=$(now_epoch)" "evac_reason=diverged"

    git checkout master -q >/dev/null 2>&1 || true
    git reset --hard origin/master -q
    git clean -fdq
    log "OK: $repo reset to origin/master after diverged evacuation"
    return 0
  fi

  log "ERROR: $repo diverged evacuation push failed; canonical NOT reset"
  return 1
}

evacuate_dirty() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  local host timestamp rescue_branch rescue_dir
  host="$(short_host)"
  timestamp="$(iso_timestamp)"
  rescue_branch="rescue-${host}-${repo}-${timestamp}"
  rescue_dir="/tmp/agents/rescue-${repo}-$$"

  cd "$repo_path"
  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "unknown")"

  log "Evacuating dirty $repo (branch=$current_branch) -> $rescue_branch"

  if ! git worktree add -b "$rescue_branch" "$rescue_dir" origin/master >/dev/null 2>&1; then
    log "ERROR: $repo failed to create rescue worktree"
    rm -rf "$rescue_dir" >/dev/null 2>&1 || true
    return 1
  fi

  # Copy changed files from canonical -> rescue worktree.
  git status --porcelain 2>/dev/null | while IFS= read -r status_line; do
    local xy="${status_line:0:2}"
    local file="${status_line:3}"
    [[ "$file" == *" -> "* ]] && file="${file##* -> }"

    local x="${xy:0:1}"
    local y="${xy:1:1}"
    [[ "$x" == "D" || "$y" == "D" ]] && continue

    [[ -e "$repo_path/$file" ]] || continue

    mkdir -p "$rescue_dir/$(dirname "$file")"
    cp -a "$repo_path/$file" "$rescue_dir/$file" >/dev/null 2>&1 || true
  done

  cd "$rescue_dir"
  git add -A >/dev/null 2>&1 || true
  git commit -m "chore(rescue): evacuate canonical dirty state

Original-Branch: $current_branch
Source: $host
Reason: dirty-timeout
Feature-Key: RESCUE-$host-$repo
Agent: canonical-evacuate-active" --quiet >/dev/null 2>&1 || true

  if git push -u origin "$rescue_branch" --quiet >/dev/null 2>&1; then
    log_recovery "$repo" "$rescue_branch" "dirty" ""
    state_upsert "$repo" "rescue_branch=$rescue_branch" "evacuated_at_epoch=$(now_epoch)" "evac_reason=dirty-timeout"

    cd "$repo_path"
    git checkout master -q >/dev/null 2>&1 || true
    git reset --hard origin/master -q
    git clean -fdq

    git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
    rm -rf "$rescue_dir" >/dev/null 2>&1 || true

    log "OK: $repo reset to origin/master after dirty evacuation"
    return 0
  fi

  log "ERROR: $repo dirty evacuation push failed; canonical NOT reset"
  cd "$repo_path"
  git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
  rm -rf "$rescue_dir" >/dev/null 2>&1 || true
  return 1
}

process_repo() {
  local repo="$1"
  local repo_path="$HOME/$repo"

  log "Checking $repo..."

  [[ -d "$repo_path/.git" ]] || return 0

  if is_locked "$repo_path"; then
    log "SKIP: $repo (locked)"
    return 0
  fi

  cd "$repo_path"

  if ! git fetch origin master --quiet 2>>"$FETCH_ERR_LOG"; then
    log "WARNING: $repo fetch failed; continuing with possibly stale refs"
  fi

  local porcelain
  porcelain="$(git status --porcelain 2>/dev/null || true)"
  local is_dirty=false
  [[ -n "$porcelain" ]] && is_dirty=true

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "master")"
  local is_off_trunk=false
  [[ "$current_branch" != "master" ]] && is_off_trunk=true

  local ahead behind
  ahead="$(git rev-list --count origin/master..HEAD 2>/dev/null || echo "0")"
  behind="$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")"
  local is_diverged=false
  [[ "$ahead" -gt 0 ]] && is_diverged=true

  local status="clean"
  $is_diverged && status="diverged"
  $is_off_trunk && [[ "$status" == "clean" ]] && status="off_trunk"
  $is_dirty && [[ "$status" == "clean" ]] && status="dirty"

  local prev_json prev_status first_seen warned_at
  prev_json="$(state_get_json "$repo")"
  prev_status="$(python3 - "$prev_json" <<'PY'
import json, sys
entry=json.loads(sys.argv[1] or "{}")
print(entry.get("status","clean"))
PY
)"
  first_seen="$(python3 - "$prev_json" <<'PY'
import json, sys
entry=json.loads(sys.argv[1] or "{}")
v=entry.get("first_seen_epoch","")
print(v if isinstance(v,int) else "")
PY
)"
  warned_at="$(python3 - "$prev_json" <<'PY'
import json, sys
entry=json.loads(sys.argv[1] or "{}")
v=entry.get("warned_at_epoch","")
print(v if isinstance(v,int) else "")
PY
)"

  local now
  now="$(now_epoch)"

  # Recovery: became clean
  if [[ "$status" == "clean" ]]; then
    if [[ "$prev_status" != "clean" ]]; then
      send_event_alert "$repo" "recovered" ""
      state_delete_repo "$repo"
      log "$repo recovered -> clean"
    fi
    return 0
  fi

  # Determine first_seen_epoch (preserve if already set)
  if [[ -z "$first_seen" ]]; then
    first_seen="$now"
  fi

  local age_minutes
  age_minutes=$(( (now - first_seen) / 60 ))
  [[ "$age_minutes" -lt 0 ]] && age_minutes=0

  # Instrumentation
  local dirty_paths_json untracked_count diffstat hook agent
  dirty_paths_json="$(get_dirty_paths_json "$repo_path" 10)"
  untracked_count="$(get_untracked_count "$repo_path")"
  diffstat="$(get_diffstat "$repo_path")"
  hook="$(has_precommit_hook "$repo_path" && echo true || echo false)"
  agent=""
  [[ "$is_diverged" == true ]] && agent="$(get_agent_trailer "$repo_path")"

  state_upsert "$repo" \
    "status=$status" \
    "first_seen_epoch=$first_seen" \
    "branch=$current_branch" \
    "ahead=$ahead" \
    "behind=$behind" \
    "dirty_paths_top=$dirty_paths_json" \
    "untracked_count=$untracked_count" \
    "diffstat=$diffstat" \
    "has_precommit_hook=$hook" \
    "last_commit_agent=$agent"

  # Immediate diverged evacuation
  if [[ "$is_diverged" == true ]]; then
    send_event_alert "$repo" "first-seen" "diverged (ahead=$ahead)"
    if evacuate_diverged "$repo"; then
      send_event_alert "$repo" "evacuated" "diverged"
    fi
    return 0
  fi

  # First-seen transition
  if [[ "$prev_status" == "clean" ]]; then
    send_event_alert "$repo" "first-seen" "$status"
  fi

  # Warn threshold
  if [[ "$age_minutes" -ge "$DIRTY_WARN_MINUTES" && -z "$warned_at" ]]; then
    state_upsert "$repo" "warned_at_epoch=$now"
    send_event_alert "$repo" "warn" ""
  fi

  # Evict threshold
  if [[ "$age_minutes" -ge "$DIRTY_EVICT_MINUTES" ]]; then
    if evacuate_dirty "$repo"; then
      send_event_alert "$repo" "evacuated" "dirty"
    fi
  fi
}

main() {
  log "=== Canonical Enforcer (Active Hours) ==="
  for repo in "${CANONICAL_REPOS[@]}"; do
    process_repo "$repo" || true
  done
  log "=== Complete ==="
}

main "$@"
