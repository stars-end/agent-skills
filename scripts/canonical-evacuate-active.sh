#!/usr/bin/env bash
#
# canonical-evacuate-active.sh - Active-hours canonical enforcer (V8.6)
#
# Purpose
# - Keep canonical working trees from staying dirty/stale during active hours.
# - Preserve work safely (commit-aware evacuation) and then reset canonicals to each repo's upstream branch.
#
# Policy (defaults tuned for deterministic SLO with 15-min cadence)
# - Warn once at >=15m dirty
# - Evacuate at >=45m dirty (worst-case <=60m with */15 cadence)
# - Immediate evacuate if commits exist in canonical (ahead of the repo's upstream branch)
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
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh"
source "$SCRIPT_DIR/lib/canonical-git-remotes.sh"

# Cron cleanup should avoid user-level shims (e.g., mise) to keep git-only
# maintenance deterministic across fresh devices.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

STATE_DIR="$HOME/.dx-state"
STATE_FILE="$STATE_DIR/dirty-incidents.json"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"

LOG_DIR="$HOME/logs/dx"
LOG_FILE="$LOG_DIR/canonical-evacuate.log"
FETCH_ERR_LOG="$LOG_DIR/fetch-errors.log"

CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common" "bd-symphony")

DIRTY_WARN_MINUTES="${DIRTY_WARN_MINUTES:-15}"
DIRTY_EVICT_MINUTES="${DIRTY_EVICT_MINUTES:-45}"
DIVERGED_EVICT_MINUTES="${DIVERGED_EVICT_MINUTES:-0}"

# Active canonical evacuation is allowed to reset after a rescue branch is
# pushed. Set WORKTREE_CLEANUP_ALLOW_WORKING_HOURS=0 for save-only diagnostics.
WORKTREE_CLEANUP_ALLOW_WORKING_HOURS="${WORKTREE_CLEANUP_ALLOW_WORKING_HOURS:-1}"
WORKTREE_CLEANUP_PROTECT_START="${WORKTREE_CLEANUP_PROTECT_START:-8}"
WORKTREE_CLEANUP_PROTECT_END="${WORKTREE_CLEANUP_PROTECT_END:-18}"

SLACK_CHANNEL_ID="${DX_ALERTS_CHANNEL_ID:-}"

mkdir -p "$STATE_DIR" "$LOG_DIR"
touch "$RECOVERY_LOG"
touch "$FETCH_ERR_LOG"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

push_without_hooks() {
  # Rescue durability must not depend on local feature-work hooks.
  git -c core.hooksPath=/dev/null push --no-verify "$@"
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

  if agent_coordination_send_message "$msg" "$SLACK_CHANNEL_ID" >/dev/null 2>&1; then
    return 0
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
  git status --porcelain 2>/dev/null \
    | awk '{line=substr($0,4); sub(/.* -> /,"",line); print line}' \
    | head -n "$n" \
    | python3 -c 'import json, sys; print(json.dumps([line.rstrip("\n") for line in sys.stdin if line.strip()]))'
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
  local status="$2"
  local reason="$3"
  local rescue_branch="${4:-}"
  local details="${5:-}"
  local agent="${6:-}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local host
  host="$(short_host)"
  echo -n "${ts} | script=canonical-evacuate-active | repo=${repo} | host=${host} | status=${status} | reason=${reason}" >>"$RECOVERY_LOG"
  if [[ -n "$rescue_branch" ]]; then
    echo -n " | branch=${rescue_branch}" >>"$RECOVERY_LOG"
  fi
  if [[ -n "$agent" ]]; then
    echo -n " | agent=${agent}" >>"$RECOVERY_LOG"
  fi
  if [[ -n "$details" ]]; then
    echo -n " | ${details}" >>"$RECOVERY_LOG"
  fi
  echo >>"$RECOVERY_LOG"
}

extract_locked_worktree_path() {
  local checkout_err="$1"
  echo "$checkout_err" | sed -nE "s/.*worktree at '([^']+)'.*/\1/p" | head -1
}

is_tmux_attached_to_path() {
  local target_path="$1"
  command -v tmux >/dev/null 2>&1 || return 1

  while IFS=$'\t' read -r attached pane_path; do
    [[ "$attached" == "1" ]] || continue
    [[ "$pane_path" == "$target_path"* ]] && return 0
  done < <(tmux list-panes -a -F '#{session_attached}	#{pane_current_path}' 2>/dev/null || true)

  return 1
}

# bd-kuhj.8: Working hours protection check
is_working_hours() {
  local start_hour="$WORKTREE_CLEANUP_PROTECT_START"
  local end_hour="$WORKTREE_CLEANUP_PROTECT_END"
  local current_hour
  current_hour=$((10#$(date +%H)))
  start_hour=$((10#$start_hour))
  end_hour=$((10#$end_hour))
  
  [[ "$current_hour" -ge "$start_hour" && "$current_hour" -lt "$end_hour" ]]
}

normalize_off_trunk_clean_repo() {
  local repo="$1"
  local repo_path="$2"
  local current_branch="$3"
  local branch="$4"
  local upstream_ref="$5"
  local checkout_err lock_path active=false

  cd "$repo_path"
  if checkout_err="$(git checkout "$branch" -q 2>&1)"; then
    git reset --hard "$upstream_ref" -q
    git clean -fdq
    log "OK: $repo reset from off-trunk clean state (branch=$current_branch) to $upstream_ref"
    echo "normalized||false"
    return 0
  fi

  lock_path="$(extract_locked_worktree_path "$checkout_err")"
  if [[ -n "$lock_path" ]]; then
    if is_tmux_attached_to_path "$lock_path"; then
      active=true
    fi
    log "INFO: $repo $branch checkout blocked by worktree lock (branch=$current_branch lock=$lock_path tmux_attached=$active)"
    echo "branch_locked_by_worktree|$lock_path|$active"
    return 0
  fi

  log "ERROR: $repo failed to checkout $branch from off-trunk clean state: $checkout_err"
  return 1
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
  local branch upstream_ref
  branch="$(canonical_repo_branch "$repo")"
  upstream_ref="origin/$branch"
  local host timestamp rescue_branch
  host="$(short_host)"
  timestamp="$(iso_timestamp)"
  rescue_branch="rescue-${host}-${repo}-${timestamp}"

  cd "$repo_path"

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "unknown")"
  local agent
  agent="$(get_agent_trailer "$repo_path")"
  [[ -z "$agent" ]] && agent="canonical-evacuate-active"

  log "Evacuating diverged $repo (branch=$current_branch ahead commits present; agent=$agent)"

  git branch -f "$rescue_branch" HEAD >/dev/null 2>&1 || true

  local push_output
  if push_output="$(push_without_hooks -u origin "$rescue_branch" --quiet 2>&1)"; then
    log_recovery "$repo" "evacuated" "diverged" "$rescue_branch" "branch=${current_branch}" "$agent"
    state_upsert "$repo" "rescue_branch=$rescue_branch" "evacuated_at_epoch=$(now_epoch)" "evac_reason=diverged"

    git checkout "$branch" -q >/dev/null 2>&1 || true
    git reset --hard "$upstream_ref" -q
    git clean -fdq
    log "OK: $repo reset to $upstream_ref after diverged evacuation"
    return 0
  fi

  log "ERROR: $repo diverged evacuation push failed for $rescue_branch: ${push_output:-no output}; canonical NOT reset"
  return 1
}

evacuate_dirty() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  local branch upstream_ref
  branch="$(canonical_repo_branch "$repo")"
  upstream_ref="origin/$branch"

  local host timestamp rescue_branch rescue_dir
  host="$(short_host)"
  timestamp="$(iso_timestamp)"
  rescue_branch="rescue-${host}-${repo}-${timestamp}"
  rescue_dir="/tmp/agents/rescue-${repo}-$$"

  cd "$repo_path"
  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "unknown")"

  log "Evacuating dirty $repo (branch=$current_branch) -> $rescue_branch"

  if ! git worktree add -b "$rescue_branch" "$rescue_dir" "$upstream_ref" >/dev/null 2>&1; then
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
    if [[ "$x" == "D" || "$y" == "D" ]]; then
      git -C "$rescue_dir" rm -f -- "$file" >/dev/null 2>&1 || true
      continue
    fi

    [[ -e "$repo_path/$file" ]] || continue

    mkdir -p "$rescue_dir/$(dirname "$file")"
    cp -a "$repo_path/$file" "$rescue_dir/$file" >/dev/null 2>&1 || true
  done

  cd "$rescue_dir"
  git add -A >/dev/null 2>&1 || true

  local commit_output
  if ! commit_output="$(git -c core.hooksPath=/dev/null commit --no-verify -m "chore(rescue): evacuate canonical dirty state

Original-Branch: $current_branch
Source: $host
Reason: dirty-timeout
Feature-Key: bd-rescue
Rescue-Key: RESCUE-$host-$repo
Agent: canonical-evacuate-active" --quiet 2>&1)"; then
    if git diff --cached --quiet; then
      log "ERROR: $repo rescue worktree has no staged changes; canonical NOT reset"
    else
      log "ERROR: $repo rescue commit failed: ${commit_output:-no output}; canonical NOT reset"
    fi
    cd "$repo_path"
    git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
    rm -rf "$rescue_dir" >/dev/null 2>&1 || true
    return 1
  fi

  local push_output
  if push_output="$(push_without_hooks -u origin "$rescue_branch" --quiet 2>&1)"; then
    log_recovery "$repo" "evacuated" "dirty_timeout" "$rescue_branch" "branch=${current_branch}" "canonical-evacuate-active"
    state_upsert "$repo" "rescue_branch=$rescue_branch" "evacuated_at_epoch=$(now_epoch)" "evac_reason=dirty-timeout"

    # Rescue first, then decide whether canonical reset is safe.
    if is_working_hours && [[ "$WORKTREE_CLEANUP_ALLOW_WORKING_HOURS" != "1" ]]; then
      log "SKIP: $repo dirty reset blocked after rescue push (working hours opt-out protection)"
      log_recovery "$repo" "skip" "working_hours_protection" "$rescue_branch" "policy=dirty-timeout-evacuation rescue_pushed=true" "canonical-evacuate-active"
      git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
      rm -rf "$rescue_dir" >/dev/null 2>&1 || true
      return 0
    fi

    local found_active_tmux=false
    local worktree_paths
    worktree_paths="$(git -C "$repo_path" worktree list --porcelain 2>/dev/null | grep "^worktree" | cut -d' ' -f2 || true)"
    while IFS= read -r wt_path; do
      [[ -n "$wt_path" ]] || continue
      if is_tmux_attached_to_path "$wt_path"; then
        found_active_tmux=true
        log "SKIP: $repo dirty reset blocked after rescue push (tmux worktree: $wt_path)"
        log_recovery "$repo" "skip" "tmux_attached_worktree" "$rescue_branch" "worktree=$wt_path rescue_pushed=true" "canonical-evacuate-active"
        break
      fi
    done <<< "$worktree_paths"

    if [[ "$found_active_tmux" == "true" ]]; then
      git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
      rm -rf "$rescue_dir" >/dev/null 2>&1 || true
      return 0
    fi

    cd "$repo_path"
    git checkout "$branch" -q >/dev/null 2>&1 || true
    git reset --hard "$upstream_ref" -q
    git clean -fdq

    git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
    rm -rf "$rescue_dir" >/dev/null 2>&1 || true

    log "OK: $repo reset to $upstream_ref after dirty evacuation"
    return 0
  fi

  log "ERROR: $repo dirty evacuation push failed for $rescue_branch: ${push_output:-no output}; canonical NOT reset"
  cd "$repo_path"
  git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
  rm -rf "$rescue_dir" >/dev/null 2>&1 || true
  return 1
}

process_repo() {
  local repo="$1"
  local repo_path="$HOME/$repo"
  local branch upstream_ref
  branch="$(canonical_repo_branch "$repo")"
  upstream_ref="origin/$branch"

  log "Checking $repo..."

  [[ -d "$repo_path/.git" ]] || return 0

  # Keep canonical rescue push non-interactive by ensuring SSH remotes for
  # managed stars-end canonical repos when conversion is safe.
  local remote_status remote_current remote_expected remote_result
  remote_result="$(canonical_ensure_origin_ssh "$repo" "$repo_path" "fix")"
  remote_status="${remote_result%%|*}"
  remote_current="$(echo "$remote_result" | cut -d'|' -f2)"
  remote_expected="$(echo "$remote_result" | cut -d'|' -f3)"
  case "$remote_status" in
    converted)
      log "OK: $repo origin normalized to SSH ($remote_current -> $remote_expected)"
      ;;
    set_failed)
      log "ERROR: $repo failed to normalize origin to SSH ($remote_current -> $remote_expected); push may fail"
      ;;
    unsupported_origin)
      log "WARN: $repo origin is not canonical SSH and was not changed ($remote_current); expected $remote_expected"
      ;;
  esac

  if is_locked "$repo_path"; then
    log "SKIP: $repo (locked)"
    log_recovery "$repo" "skip" "branch_locked_by_script" "" "path=${repo_path}"
    return 0
  fi

  cd "$repo_path"

  # Note: No fetch here. Refs are updated by:
  #   - fetch-* cron jobs (every 20-30 min)
  #   - reconcile cron job (every 2h)
  # The 'behind' count may be slightly stale but evacuation logic is safe:
  #   - 'ahead' count is purely local (doesn't need fetch)
  #   - reset --hard upstream happens AFTER rescue push
  # Removing this fetch also eliminates race condition with reconcile.

  local porcelain
  porcelain="$(git status --porcelain 2>/dev/null || true)"
  local is_dirty=false
  [[ -n "$porcelain" ]] && is_dirty=true

  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || echo "$branch")"
  local is_off_trunk=false
  [[ "$current_branch" != "$branch" ]] && is_off_trunk=true

  local ahead behind
  ahead="$(git rev-list --count "$upstream_ref"..HEAD 2>/dev/null || echo "0")"
  behind="$(git rev-list --count HEAD.."$upstream_ref" 2>/dev/null || echo "0")"
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

  local lock_worktree_path=""
  local lock_worktree_active=false

  if [[ "$is_diverged" == false && "$is_dirty" == false && "$is_off_trunk" == true ]]; then
    local off_trunk_resolution
    if ! off_trunk_resolution="$(normalize_off_trunk_clean_repo "$repo" "$repo_path" "$current_branch" "$branch" "$upstream_ref")"; then
      return 1
    fi

    local resolved_status resolved_path resolved_active
    resolved_status="${off_trunk_resolution%%|*}"
    resolved_path="$(echo "$off_trunk_resolution" | cut -d'|' -f2)"
    resolved_active="$(echo "$off_trunk_resolution" | cut -d'|' -f3)"

    if [[ "$resolved_status" == "normalized" ]]; then
      if [[ "$prev_status" != "clean" ]]; then
        send_event_alert "$repo" "recovered" ""
        log_recovery "$repo" "skip" "off_trunk_clean" "n/a" "branch=${current_branch}" "canonical-evacuate-active"
      fi
      state_delete_repo "$repo"
      return 0
    fi

    status="$resolved_status"
    lock_worktree_path="$resolved_path"
    lock_worktree_active="$resolved_active"
  fi

  # Recovery: became clean
  if [[ "$status" == "clean" ]]; then
    if [[ "$prev_status" != "clean" ]]; then
      send_event_alert "$repo" "recovered" ""
      state_delete_repo "$repo"
      log_recovery "$repo" "skip" "clean" "n/a" "branch=${current_branch}" "canonical-evacuate-active"
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
    "last_commit_agent=$agent" \
    "lock_worktree_path=$lock_worktree_path" \
    "lock_worktree_active=$lock_worktree_active"

  # Immediate diverged evacuation
  if [[ "$is_diverged" == true ]]; then
    send_event_alert "$repo" "first-seen" "diverged (ahead=$ahead)"
    if evacuate_diverged "$repo"; then
      send_event_alert "$repo" "evacuated" "diverged"
      # evacuation success is logged in evacuate_diverged()
    else
      return 1
    fi
    return 0
  fi

  # First-seen transition
  local first_seen_detail="$status"
  if [[ "$status" == "branch_locked_by_worktree" ]]; then
    first_seen_detail="branch_locked_by_worktree lock=$lock_worktree_path tmux_attached=$lock_worktree_active"
    if [[ "$prev_status" != "branch_locked_by_worktree" ]]; then
      log_recovery "$repo" "skip" "branch_locked_by_worktree" "n/a" "path=${lock_worktree_path} tmux_attached=${lock_worktree_active} branch=${current_branch}"
    fi
  fi
  if [[ "$prev_status" == "clean" ]]; then
    send_event_alert "$repo" "first-seen" "$first_seen_detail"
  fi

  # Warn threshold
  if [[ "$age_minutes" -ge "$DIRTY_WARN_MINUTES" && -z "$warned_at" ]]; then
    state_upsert "$repo" "warned_at_epoch=$now"
    send_event_alert "$repo" "warn" ""
  fi

  # Evict threshold (dirty only)
  if [[ "$status" == "dirty" && "$age_minutes" -ge "$DIRTY_EVICT_MINUTES" ]]; then
    if evacuate_dirty "$repo"; then
      send_event_alert "$repo" "evacuated" "dirty"
      log_recovery "$repo" "evacuated" "dirty_timeout" "n/a" "branch=${current_branch}" "canonical-evacuate-active"
    else
      return 1
    fi
  fi
}

main() {
  log "=== Canonical Enforcer (Active Hours) ==="
  local fail_count=0
  for repo in "${CANONICAL_REPOS[@]}"; do
    if ! process_repo "$repo"; then
      fail_count=$((fail_count + 1))
    fi
  done
  if [[ "$fail_count" -gt 0 ]]; then
    log "=== Complete (errors=$fail_count) ==="
    return 1
  fi
  log "=== Complete ==="
}

main "$@"
