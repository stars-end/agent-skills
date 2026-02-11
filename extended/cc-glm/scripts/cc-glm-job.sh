#!/usr/bin/env bash
set -euo pipefail

# cc-glm-job.sh
#
# Lightweight background job manager for cc-glm headless runs.
# Keeps consistent artifacts under /tmp/cc-glm-jobs:
#   <beads>.pid, <beads>.log, <beads>.meta
#
# Commands:
#   start    --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>]
#   status   [--beads <id>] [--log-dir <dir>]
#   check    --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
#   health   [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>]
#   restart  --beads <id> [--log-dir <dir>]
#   stop     --beads <id> [--log-dir <dir>]
#   watchdog [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>]
#            [--pidfile <path>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADLESS="${SCRIPT_DIR}/cc-glm-headless.sh"

LOG_DIR="/tmp/cc-glm-jobs"
CMD="${1:-}"
shift || true

usage() {
  cat <<'EOF'
cc-glm-job.sh

Usage:
  cc-glm-job.sh start --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>]
  cc-glm-job.sh status [--beads <id>] [--log-dir <dir>]
  cc-glm-job.sh check --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh health [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh restart --beads <id> [--log-dir <dir>]
  cc-glm-job.sh stop --beads <id> [--log-dir <dir>]
  cc-glm-job.sh watchdog [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>] [--pidfile <path>]

Commands:
  start    Launch a cc-glm job in background with nohup.
  status   Show status table of jobs (all or specific).
  check    Check single job health (exit 2 if stalled).
  health   Show detailed health state (healthy/stalled/exited/blocked) for jobs.
  restart  Restart a job (preserves metadata, increments retry count).
  stop     Stop a running job.
  watchdog Run watchdog loop: monitor jobs, restart stalled jobs once, mark blocked on second stall.

Notes:
  - check exits 2 when a running job appears stalled (no log updates past threshold).
  - health classifies jobs: healthy, stalled (>N min no log growth), exited, blocked (retries exhausted).
  - restart preserves existing metadata and increments retries count.
  - watchdog runs in foreground; daemonize via nohup/launchd/systemd for persistent monitoring.
EOF
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

file_mtime_epoch() {
  local f="$1"
  if stat -f "%m" "$f" >/dev/null 2>&1; then
    stat -f "%m" "$f"
    return 0
  fi
  stat -c "%Y" "$f"
}

format_elapsed() {
  local sec="$1"
  if [[ "$sec" -lt 60 ]]; then
    printf "%ss" "$sec"
    return 0
  fi
  local min=$((sec / 60))
  local rem=$((sec % 60))
  if [[ "$min" -lt 60 ]]; then
    printf "%sm%ss" "$min" "$rem"
    return 0
  fi
  local hr=$((min / 60))
  local min_rem=$((min % 60))
  printf "%sh%sm" "$hr" "$min_rem"
}

meta_get() {
  local meta="$1"
  local key="$2"
  awk -F= -v key="$key" '$1==key {print substr($0, length(key)+2); exit}' "$meta" 2>/dev/null || true
}

meta_set() {
  local meta="$1"
  local key="$2"
  local val="$3"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$meta" ]]; then
    awk -F= -v key="$key" '$1!=key {print $0}' "$meta" > "$tmp"
  fi
  printf "%s=%s\n" "$key" "$val" >> "$tmp"
  mv "$tmp" "$meta"
}

job_paths() {
  local beads="$1"
  PID_FILE="${LOG_DIR}/${beads}.pid"
  LOG_FILE="${LOG_DIR}/${beads}.log"
  META_FILE="${LOG_DIR}/${beads}.meta"
}

job_state() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    printf "missing"
    return 0
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    printf "missing"
    return 0
  fi
  if ps -p "$pid" >/dev/null 2>&1; then
    printf "running"
    return 0
  fi
  printf "exited"
}

parse_common_args() {
  BEADS=""
  PROMPT_FILE=""
  REPO=""
  WORKTREE=""
  STALL_MINUTES=20
  WATCHDOG_INTERVAL=60
  WATCHDOG_MAX_RETRIES=2
  WATCHDOG_PIDFILE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --beads)
        BEADS="${2:-}"
        shift 2
        ;;
      --prompt-file)
        PROMPT_FILE="${2:-}"
        shift 2
        ;;
      --repo)
        REPO="${2:-}"
        shift 2
        ;;
      --worktree)
        WORKTREE="${2:-}"
        shift 2
        ;;
      --log-dir)
        LOG_DIR="${2:-}"
        shift 2
        ;;
      --stall-minutes)
        STALL_MINUTES="${2:-20}"
        shift 2
        ;;
      --interval)
        WATCHDOG_INTERVAL="${2:-60}"
        shift 2
        ;;
      --max-retries)
        WATCHDOG_MAX_RETRIES="${2:-2}"
        shift 2
        ;;
      --pidfile)
        WATCHDOG_PIDFILE="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage
        exit 2
        ;;
    esac
  done
}

start_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "start requires --beads" >&2; exit 2; }
  [[ -n "$PROMPT_FILE" ]] || { echo "start requires --prompt-file" >&2; exit 2; }
  [[ -f "$PROMPT_FILE" ]] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  [[ -x "$HEADLESS" ]] || { echo "headless wrapper not executable: $HEADLESS" >&2; exit 1; }

  mkdir -p "$LOG_DIR"
  job_paths "$BEADS"

  local state
  state="$(job_state "$PID_FILE")"
  if [[ "$state" == "running" ]]; then
    echo "job $BEADS already running (pid=$(cat "$PID_FILE"))" >&2
    exit 1
  fi

  : > "$LOG_FILE"
  cat > "$META_FILE" <<EOF
beads=$BEADS
repo=$REPO
worktree=$WORKTREE
prompt_file=$PROMPT_FILE
started_at=$(now_utc)
retries=0
EOF

  # Detached run; stdout/stderr go to per-job log.
  nohup "$HEADLESS" --prompt-file "$PROMPT_FILE" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$pid"

  echo "started beads=$BEADS pid=$pid log=$LOG_FILE"
}

status_line() {
  local beads="$1"
  job_paths "$beads"
  local pid="" state="missing" log_bytes="0" last_update="-" retries="0" elapsed="-"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  state="$(job_state "$PID_FILE")"

  if [[ -f "$LOG_FILE" ]]; then
    log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    local mtime
    mtime="$(file_mtime_epoch "$LOG_FILE" 2>/dev/null || echo "")"
    if [[ -n "$mtime" ]]; then
      local now
      now="$(date +%s)"
      local age=$((now - mtime))
      last_update="$(format_elapsed "$age") ago"
    fi
  fi

  if [[ -f "$META_FILE" ]]; then
    retries="$(meta_get "$META_FILE" "retries")"
    [[ -n "$retries" ]] || retries="0"
  fi

  # Elapsed is best-effort from PID file age (portable across macOS/Linux).
  if [[ -f "$PID_FILE" ]]; then
    local pid_mtime now
    pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
    if [[ -n "$pid_mtime" ]]; then
      now="$(date +%s)"
      elapsed="$(format_elapsed "$((now - pid_mtime))")"
    fi
  fi

  printf "%-14s %-8s %-7s %-9s %-9s %-16s %s\n" \
    "$beads" "${pid:--}" "$state" "$elapsed" "$log_bytes" "$last_update" "$retries"
}

status_cmd() {
  parse_common_args "$@"
  printf "%-14s %-8s %-7s %-9s %-9s %-16s %s\n" \
    "bead" "pid" "state" "elapsed" "bytes" "last_update" "retries"
  if [[ -n "$BEADS" ]]; then
    status_line "$BEADS"
    return 0
  fi
  shopt -s nullglob
  local found=0
  for pidf in "$LOG_DIR"/*.pid; do
    found=1
    local beads
    beads="$(basename "$pidf" .pid)"
    status_line "$beads"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "(no jobs found in $LOG_DIR)"
  fi
}

check_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "check requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  local state
  state="$(job_state "$PID_FILE")"
  if [[ "$state" != "running" ]]; then
    echo "job $BEADS state=$state"
    exit 1
  fi

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "job $BEADS has no log file: $LOG_FILE"
    exit 1
  fi

  local now mtime age threshold
  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$LOG_FILE")"
  age=$((now - mtime))
  threshold=$((STALL_MINUTES * 60))
  if [[ "$age" -gt "$threshold" ]]; then
    echo "job $BEADS appears stalled: no log updates for ${STALL_MINUTES}m (age=${age}s)"
    exit 2
  fi

  echo "job $BEADS healthy: running with recent log activity (${age}s)"
}

stop_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "stop requires --beads" >&2; exit 2; }
  job_paths "$BEADS"
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    echo "no pid file for $BEADS"
    exit 1
  fi
  if ps -p "$pid" >/dev/null 2>&1; then
    kill "$pid" || true
    echo "stopped $BEADS (pid=$pid)"
  else
    echo "job $BEADS already not running (pid=$pid)"
  fi
}

# Health classification for a single job
job_health() {
  local beads="$1"
  job_paths "$beads"
  local stall_threshold="${2:-$((STALL_MINUTES * 60))}"

  if [[ ! -f "$PID_FILE" ]]; then
    printf "missing"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    printf "missing"
    return 0
  fi

  if ! ps -p "$pid" >/dev/null 2>&1; then
    printf "exited"
    return 0
  fi

  # Check for blocked state (retries exhausted)
  if [[ -f "$META_FILE" ]]; then
    local retries blocked
    retries="$(meta_get "$META_FILE" "retries")"
    retries="${retries:-0}"
    blocked="$(meta_get "$META_FILE" "blocked")"
    if [[ "$blocked" == "true" ]]; then
      printf "blocked"
      return 0
    fi
  fi

  # Check log growth
  if [[ ! -f "$LOG_FILE" ]]; then
    printf "stalled"
    return 0
  fi

  local now mtime age
  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$LOG_FILE")"
  age=$((now - mtime))

  if [[ "$age" -gt "$stall_threshold" ]]; then
    printf "stalled"
    return 0
  fi

  printf "healthy"
}

health_cmd() {
  parse_common_args "$@"
  local stall_seconds=$((STALL_MINUTES * 60))
  printf "%-14s %-8s %-10s %-16s %s\n" \
    "bead" "pid" "health" "last_update" "retries"
  if [[ -n "$BEADS" ]]; then
    health_line "$BEADS" "$stall_seconds"
    return 0
  fi
  shopt -s nullglob
  local found=0
  for pidf in "$LOG_DIR"/*.pid; do
    found=1
    local beads
    beads="$(basename "$pidf" .pid)"
    health_line "$beads" "$stall_seconds"
  done
  if [[ "$found" -eq 0 ]]; then
    echo "(no jobs found in $LOG_DIR)"
  fi
}

health_line() {
  local beads="$1"
  local stall_threshold="$2"
  job_paths "$beads"
  local pid="" health="missing" last_update="-" retries="0"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  health="$(job_health "$beads" "$stall_threshold")"

  if [[ -f "$LOG_FILE" ]]; then
    local mtime
    mtime="$(file_mtime_epoch "$LOG_FILE" 2>/dev/null || echo "")"
    if [[ -n "$mtime" ]]; then
      local now age
      now="$(date +%s)"
      age=$((now - mtime))
      last_update="$(format_elapsed "$age") ago"
    fi
  fi

  if [[ -f "$META_FILE" ]]; then
    retries="$(meta_get "$META_FILE" "retries")"
    [[ -n "$retries" ]] || retries="0"
  fi

  printf "%-14s %-8s %-10s %-16s %s\n" \
    "$beads" "${pid:--}" "$health" "$last_update" "$retries"
}

restart_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "restart requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  if [[ ! -f "$META_FILE" ]]; then
    echo "no metadata file for $BEADS: $META_FILE" >&2
    exit 1
  fi

  # Get current retries and prompt file
  local retries prompt_file repo worktree
  retries="$(meta_get "$META_FILE" "retries")"
  retries="${retries:-0}"
  prompt_file="$(meta_get "$META_FILE" "prompt_file")"
  repo="$(meta_get "$META_FILE" "repo")"
  worktree="$(meta_get "$META_FILE" "worktree")"

  if [[ -z "$prompt_file" || ! -f "$prompt_file" ]]; then
    echo "invalid or missing prompt_file in metadata: $prompt_file" >&2
    exit 1
  fi

  # Stop existing job if running
  local pid
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
      kill "$pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  # Increment retries
  local new_retries=$((retries + 1))
  meta_set "$META_FILE" "retries" "$new_retries"
  meta_set "$META_FILE" "restarted_at" "$(now_utc)"

  # Reset log file
  : > "$LOG_FILE"

  # Start new job
  [[ -x "$HEADLESS" ]] || { echo "headless wrapper not executable: $HEADLESS" >&2; exit 1; }
  nohup "$HEADLESS" --prompt-file "$prompt_file" >> "$LOG_FILE" 2>&1 &
  local new_pid=$!
  echo "$new_pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$new_pid"

  echo "restarted beads=$BEADS pid=$new_pid retries=$new_retries log=$LOG_FILE"
}

watchdog_cmd() {
  parse_common_args "$@"
  local stall_seconds=$((STALL_MINUTES * 60))

  # Write watchdog pidfile if requested
  if [[ -n "$WATCHDOG_PIDFILE" ]]; then
    mkdir -p "$(dirname "$WATCHDOG_PIDFILE")"
    echo $$ > "$WATCHDOG_PIDFILE"
    echo "watchdog pid=$$ written to $WATCHDOG_PIDFILE"
  fi

  echo "watchdog started: interval=${WATCHDOG_INTERVAL}s stall=${STALL_MINUTES}m max-retries=${WATCHDOG_MAX_RETRIES}"
  echo "press Ctrl+C to stop"

  local iteration=0
  while true; do
    iteration=$((iteration + 1))
    echo "=== watchdog iteration $iteration at $(now_utc) ==="

    shopt -s nullglob
    local found=0
    for pidf in "$LOG_DIR"/*.pid; do
      found=1
      local beads
      beads="$(basename "$pidf" .pid)"
      job_paths "$beads"

      # Skip if no meta file (incomplete job state)
      if [[ ! -f "$META_FILE" ]]; then
        echo "[$beads] SKIP: no metadata file"
        continue
      fi

      local health
      health="$(job_health "$beads" "$stall_seconds")"
      echo "[$beads] health=$health"

      case "$health" in
        healthy)
          # Nothing to do
          ;;
        stalled)
          # Check retry count
          local retries
          retries="$(meta_get "$META_FILE" "retries")"
          retries="${retries:-0}"
          echo "[$beads] stalled, retries=$retries/$WATCHDOG_MAX_RETRIES"

          if [[ "$retries" -ge "$WATCHDOG_MAX_RETRIES" ]]; then
            # Mark as blocked
            meta_set "$META_FILE" "blocked" "true"
            meta_set "$META_FILE" "blocked_at" "$(now_utc)"
            echo "[$beads] BLOCKED: max retries ($WATCHDOG_MAX_RETRIES) exhausted"
          else
            # Attempt restart
            echo "[$beads] restarting..."
            if restart_cmd --beads "$beads" --log-dir "$LOG_DIR" 2>&1; then
              echo "[$beads] restart succeeded"
            else
              echo "[$beads] restart FAILED: $?" >&2
            fi
          fi
          ;;
        exited)
          echo "[$beads] exited: job finished or crashed"
          ;;
        blocked)
          echo "[$beads] BLOCKED: manual intervention required"
          ;;
        missing)
          echo "[$beads] missing: incomplete job state"
          ;;
      esac
    done

    if [[ "$found" -eq 0 ]]; then
      echo "(no jobs found in $LOG_DIR)"
    fi

    sleep "$WATCHDOG_INTERVAL"
  done
}

case "$CMD" in
  start) start_cmd "$@" ;;
  status) status_cmd "$@" ;;
  check) check_cmd "$@" ;;
  health) health_cmd "$@" ;;
  restart) restart_cmd "$@" ;;
  stop) stop_cmd "$@" ;;
  watchdog) watchdog_cmd "$@" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage
    exit 2
    ;;
esac
