#!/usr/bin/env bash
set -euo pipefail

# cc-glm-job.sh
#
# Lightweight background job manager for cc-glm headless runs.
# Keeps consistent artifacts under /tmp/cc-glm-jobs:
#   <beads>.pid, <beads>.log, <beads>.meta
#
# Commands:
#   start   --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>]
#   status  [--beads <id>] [--log-dir <dir>]
#   check   --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
#   stop    --beads <id> [--log-dir <dir>]

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
  cc-glm-job.sh stop --beads <id> [--log-dir <dir>]

Notes:
  - start launches detached with nohup and writes pid/log/meta files.
  - check exits 2 when a running job appears stalled (no log updates past threshold).
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

case "$CMD" in
  start) start_cmd "$@" ;;
  status) status_cmd "$@" ;;
  check) check_cmd "$@" ;;
  stop) stop_cmd "$@" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage
    exit 2
    ;;
esac
