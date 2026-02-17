#!/usr/bin/env bash
set -euo pipefail

# cc-glm-job.sh
#
# Lightweight background job manager for cc-glm headless runs.
# Keeps consistent artifacts under /tmp/cc-glm-jobs:
#   <beads>.pid, <beads>.log, <beads>.meta
#
# Commands:
#   start    --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>] [--pty]
#   status   [--beads <id>] [--log-dir <dir>]
#   check    --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
#   health   [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>]
#   restart  --beads <id> [--log-dir <dir>] [--pty]
#   stop     --beads <id> [--log-dir <dir>]
#   watchdog [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>] [--once]
#            [--pidfile <path>]
#   ssh-start/ssh-status/ssh-check/ssh-health/ssh-restart/ssh-stop/ssh-watchdog
#            [--hosts <h1,h2>] [--host <h>] [--remote-user <u>] [--ssh-cmd tailscale|ssh] [--parallel <n>]
#            [other subcommand args...]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADLESS="${SCRIPT_DIR}/cc-glm-headless.sh"
PTY_RUN="${SCRIPT_DIR}/pty-run.sh"

LOG_DIR="/tmp/cc-glm-jobs"
CMD="${1:-}"
shift || true

usage() {
  cat <<'EOF'
cc-glm-job.sh

Usage:
  cc-glm-job.sh start --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>] [--pty]
  cc-glm-job.sh status [--beads <id>] [--log-dir <dir>]
  cc-glm-job.sh check --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh health [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh restart --beads <id> [--log-dir <dir>] [--pty]
  cc-glm-job.sh stop --beads <id> [--log-dir <dir>]
  cc-glm-job.sh watchdog [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>] [--once] [--pidfile <path>]
  cc-glm-job.sh ssh-start --hosts <h1,h2> --beads <id> --prompt-file <path> [--log-dir <dir>] [--pty]
  cc-glm-job.sh ssh-status [--hosts <h1,h2>] [--beads <id>] [--log-dir <dir>]
  cc-glm-job.sh ssh-check --hosts <h1,h2> --beads <id> [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh ssh-health [--hosts <h1,h2>] [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>]
  cc-glm-job.sh ssh-restart --hosts <h1,h2> --beads <id> [--log-dir <dir>] [--pty]
  cc-glm-job.sh ssh-stop --hosts <h1,h2> --beads <id> [--log-dir <dir>]
  cc-glm-job.sh ssh-watchdog --hosts <h1,h2> [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>] [--once]

Commands:
  start    Launch a cc-glm job in background with nohup (default) or PTY wrapper.
  status   Show status table of jobs (all or specific).
  check    Check single job health (exit 2 if stalled).
  health   Show detailed health state (healthy/stalled/exited/blocked) for jobs.
  restart  Restart a job (preserves metadata, increments retry count).
  stop     Stop a running job.
  watchdog Run watchdog loop: monitor jobs, restart stalled jobs once, mark blocked on second stall.
  ssh-*    Run the same operations on one or more remote hosts over SSH, in parallel.

Options:
  --pty    Use PTY-backed execution for reliable output capture (recommended for detached jobs).
  --once   Run exactly one watchdog iteration, then exit.
  --hosts  Comma-separated host list (e.g. epyc6,epyc12).
  --host   Add one host (repeatable).
  --remote-user Username for hosts that omit user (host -> user@host).
  --ssh-cmd SSH transport: tailscale (default) or ssh.
  --parallel Max concurrent remote hosts for ssh-* commands (default: 4).
  --remote-script Remote path to cc-glm-job.sh (default: current script path).
  --remote-prompt-path Remote prompt path template, supports %HOST% and %BEADS%.
  --no-copy-prompt Disable automatic prompt upload for ssh-start.
  --host-suffix-beads Append host name to remote bead id for ssh-start.

Notes:
  - check exits 2 when a running job appears stalled (no log updates past threshold).
  - health classifies jobs: healthy, stalled (>N min no log growth), exited, blocked (retries exhausted).
  - restart preserves existing metadata and increments retries count.
  - watchdog runs in foreground; daemonize via nohup/launchd/systemd for persistent monitoring.
  - PTY mode uses pty-run.sh wrapper for reliable output capture when nohup produces 0-byte logs.
  - ssh-start uploads the local prompt file to each host via SSH stdin by default.
  - For remote fanout, output lines are prefixed with [host].
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
  WATCHDOG_MAX_RETRIES=1
  WATCHDOG_PIDFILE=""
  WATCHDOG_ONCE=false
  USE_PTY=false
  REMOTE_HOSTS=""
  REMOTE_USER=""
  SSH_CMD="tailscale"
  SSH_PARALLEL=4
  REMOTE_SCRIPT="$SCRIPT_DIR/cc-glm-job.sh"
  REMOTE_PROMPT_PATH=""
  COPY_PROMPT=true
  HOST_SUFFIX_BEADS=false
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
        WATCHDOG_MAX_RETRIES="${2:-1}"
        shift 2
        ;;
      --once)
        WATCHDOG_ONCE=true
        shift
        ;;
      --pidfile)
        WATCHDOG_PIDFILE="${2:-}"
        shift 2
        ;;
      --pty)
        USE_PTY=true
        shift
        ;;
      --hosts)
        REMOTE_HOSTS="${2:-}"
        shift 2
        ;;
      --host)
        if [[ -n "${2:-}" ]]; then
          if [[ -z "$REMOTE_HOSTS" ]]; then
            REMOTE_HOSTS="${2}"
          else
            REMOTE_HOSTS="${REMOTE_HOSTS},${2}"
          fi
        fi
        shift 2
        ;;
      --remote-user)
        REMOTE_USER="${2:-}"
        shift 2
        ;;
      --ssh-cmd)
        SSH_CMD="${2:-tailscale}"
        shift 2
        ;;
      --parallel)
        SSH_PARALLEL="${2:-4}"
        shift 2
        ;;
      --remote-script)
        REMOTE_SCRIPT="${2:-$REMOTE_SCRIPT}"
        shift 2
        ;;
      --remote-prompt-path)
        REMOTE_PROMPT_PATH="${2:-}"
        shift 2
        ;;
      --no-copy-prompt)
        COPY_PROMPT=false
        shift
        ;;
      --host-suffix-beads)
        HOST_SUFFIX_BEADS=true
        shift
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

ensure_remote_requirements() {
  if [[ "$SSH_CMD" == "tailscale" ]]; then
    command -v tailscale >/dev/null 2>&1 || {
      echo "tailscale not found; install it or pass --ssh-cmd ssh" >&2
      exit 1
    }
    return 0
  fi
  if [[ "$SSH_CMD" == "ssh" ]]; then
    command -v ssh >/dev/null 2>&1 || {
      echo "ssh not found in PATH" >&2
      exit 1
    }
    return 0
  fi
  echo "unsupported --ssh-cmd '$SSH_CMD' (expected tailscale or ssh)" >&2
  exit 2
}

parse_remote_hosts() {
  REMOTE_HOST_LIST=()
  [[ -n "$REMOTE_HOSTS" ]] || {
    echo "remote command requires --hosts or --host" >&2
    exit 2
  }

  local tokens host
  tokens="${REMOTE_HOSTS//,/ }"
  for host in $tokens; do
    [[ -n "$host" ]] && REMOTE_HOST_LIST+=("$host")
  done
  if [[ "${#REMOTE_HOST_LIST[@]}" -eq 0 ]]; then
    echo "no valid remote hosts provided" >&2
    exit 2
  fi

  if ! [[ "$SSH_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$SSH_PARALLEL" -lt 1 ]]; then
    echo "--parallel must be a positive integer" >&2
    exit 2
  fi
}

remote_target_for_host() {
  local host="$1"
  if [[ "$host" == *@* || -z "$REMOTE_USER" ]]; then
    printf "%s" "$host"
  else
    printf "%s@%s" "$REMOTE_USER" "$host"
  fi
}

host_slug() {
  local host="$1"
  local slug
  slug="$(printf "%s" "$host" | tr '@:/ ' '_' | tr -cd '[:alnum:]_.-')"
  printf "%s" "$slug"
}

render_template() {
  local template="$1"
  local host="$2"
  local beads="$3"
  local out
  out="${template//%HOST%/$host}"
  out="${out//%BEADS%/$beads}"
  printf "%s" "$out"
}

join_quoted() {
  local out="" arg
  for arg in "$@"; do
    out+=" $(printf '%q' "$arg")"
  done
  printf "%s" "${out# }"
}

ssh_exec_cmd() {
  local host="$1"
  local remote_cmd="$2"
  local target
  target="$(remote_target_for_host "$host")"
  case "$SSH_CMD" in
    tailscale)
      tailscale ssh "$target" "$remote_cmd"
      ;;
    ssh)
      ssh "$target" "$remote_cmd"
      ;;
    *)
      echo "unsupported ssh transport: $SSH_CMD" >&2
      return 2
      ;;
  esac
}

ssh_exec_cmd_with_stdin() {
  local host="$1"
  local remote_cmd="$2"
  local stdin_file="$3"
  local target
  target="$(remote_target_for_host "$host")"
  case "$SSH_CMD" in
    tailscale)
      tailscale ssh "$target" "$remote_cmd" < "$stdin_file"
      ;;
    ssh)
      ssh "$target" "$remote_cmd" < "$stdin_file"
      ;;
    *)
      echo "unsupported ssh transport: $SSH_CMD" >&2
      return 2
      ;;
  esac
}

remote_exec_cc_glm_job() {
  local host="$1"
  shift
  local cmd_str
  cmd_str="$(join_quoted "$REMOTE_SCRIPT" "$@")"
  ssh_exec_cmd "$host" "$cmd_str"
}

upload_prompt_to_host() {
  local host="$1"
  local local_prompt="$2"
  local remote_prompt="$3"
  local remote_dir q_dir q_prompt
  remote_dir="$(dirname "$remote_prompt")"
  q_dir="$(printf '%q' "$remote_dir")"
  q_prompt="$(printf '%q' "$remote_prompt")"
  ssh_exec_cmd "$host" "mkdir -p $q_dir"
  ssh_exec_cmd_with_stdin "$host" "cat > $q_prompt" "$local_prompt"
}

run_remote_hosts_parallel() {
  local handler="$1"
  shift
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local i=0
  local host
  local pids=()
  local hosts=()
  local failures=0

  for host in "${REMOTE_HOST_LIST[@]}"; do
    while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$SSH_PARALLEL" ]]; do
      sleep 0.2
    done

    (
      "$handler" "$host" "$@"
    ) > "${tmp_dir}/${i}.out" 2> "${tmp_dir}/${i}.err" &
    pids+=("$!")
    hosts+=("$host")
    i=$((i + 1))
  done

  local idx pid rc
  for idx in "${!pids[@]}"; do
    pid="${pids[$idx]}"
    rc=0
    if ! wait "$pid"; then
      rc=$?
      failures=1
    fi
    host="${hosts[$idx]}"

    if [[ -s "${tmp_dir}/${idx}.out" ]]; then
      sed "s/^/[${host}] /" "${tmp_dir}/${idx}.out"
    fi
    if [[ -s "${tmp_dir}/${idx}.err" ]]; then
      sed "s/^/[${host}] /" "${tmp_dir}/${idx}.err" >&2
    fi
    if [[ "$rc" -ne 0 ]]; then
      echo "[${host}] rc=${rc}" >&2
    fi
  done

  rm -rf "$tmp_dir"
  return "$failures"
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
use_pty=$USE_PTY
EOF
  meta_set "$META_FILE" "launch_marker_at" "$(now_utc)"
  meta_set "$META_FILE" "launch_state" "starting"

  # Detached run; stdout/stderr go to per-job log.
  if [[ "$USE_PTY" == "true" ]]; then
    # PTY-backed execution for reliable output capture
    [[ -x "$PTY_RUN" ]] || { echo "PTY wrapper not executable: $PTY_RUN" >&2; exit 1; }
    nohup "$PTY_RUN" --output "$LOG_FILE" -- "$HEADLESS" --prompt-file "$PROMPT_FILE" >> "$LOG_FILE" 2>&1 &
    meta_set "$META_FILE" "execution_mode" "pty"
  else
    # Standard nohup execution (may produce 0-byte logs in some environments)
    nohup "$HEADLESS" --prompt-file "$PROMPT_FILE" >> "$LOG_FILE" 2>&1 &
    meta_set "$META_FILE" "execution_mode" "nohup"
  fi
  local pid=$!
  echo "$pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$pid"
  meta_set "$META_FILE" "launch_state" "running"

  echo "started beads=$BEADS pid=$pid log=$LOG_FILE pty=$USE_PTY"
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

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "job $BEADS has no log file: $LOG_FILE"
    exit 1
  fi

  local state
  state="$(job_state "$PID_FILE")"
  # Check for zero-byte log first so exited+empty is still classified stalled.
  local log_bytes
  log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if [[ "$state" != "running" ]]; then
    if [[ "$state" == "exited" && "$log_bytes" -eq 0 ]]; then
      echo "job $BEADS appears stalled: process exited with zero-byte log"
      exit 2
    fi
    echo "job $BEADS state=$state"
    exit 1
  fi

  # Running but no output captured yet: allow a grace window before declaring stalled.
  if [[ "$log_bytes" -eq 0 ]]; then
    local pid_age threshold
    pid_age=0
    if [[ -f "$PID_FILE" ]]; then
      local pid_mtime
      pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
      if [[ -n "$pid_mtime" ]]; then
        pid_age=$(( $(date +%s) - pid_mtime ))
      fi
    fi
    threshold=$((STALL_MINUTES * 60))
    if [[ "$pid_age" -gt "$threshold" ]]; then
      echo "job $BEADS appears stalled: zero-byte log after ${STALL_MINUTES}m (age=${pid_age}s)"
      exit 2
    fi
    echo "job $BEADS healthy: running within no-output grace window (${pid_age}s)"
    exit 0
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

  echo "job $BEADS healthy: running with recent log activity (${age}s, ${log_bytes} bytes)"
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
    # Exited with an empty log is treated as a stalled failed launch so watchdog can retry.
    local exited_bytes=0
    if [[ -f "$LOG_FILE" ]]; then
      exited_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    fi
    if [[ "$exited_bytes" -eq 0 ]]; then
      printf "stalled"
      return 0
    fi
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

  # Check log file existence
  if [[ ! -f "$LOG_FILE" ]]; then
    printf "stalled"
    return 0
  fi

  # Check for zero output while running.
  local log_bytes
  log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if [[ "$log_bytes" -eq 0 ]]; then
    # Allow startup/no-output grace window for long-running calls.
    local pid_age=0
    if [[ -f "$PID_FILE" ]]; then
      local pid_mtime
      pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
      if [[ -n "$pid_mtime" ]]; then
        pid_age=$(( $(date +%s) - pid_mtime ))
      fi
    fi
    if [[ "$pid_age" -gt "$stall_threshold" ]]; then
      printf "stalled"
      return 0
    fi
    printf "healthy"
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
  local retries prompt_file repo worktree meta_use_pty effective_use_pty
  retries="$(meta_get "$META_FILE" "retries")"
  retries="${retries:-0}"
  prompt_file="$(meta_get "$META_FILE" "prompt_file")"
  repo="$(meta_get "$META_FILE" "repo")"
  worktree="$(meta_get "$META_FILE" "worktree")"
  meta_use_pty="$(meta_get "$META_FILE" "use_pty")"
  effective_use_pty="$USE_PTY"

  # Preserve previous mode unless caller explicitly passes --pty.
  if [[ "$effective_use_pty" != "true" && "$meta_use_pty" == "true" ]]; then
    effective_use_pty="true"
  fi

  # Automatic fallback: if previous attempt produced zero output, restart with PTY.
  if [[ "$effective_use_pty" != "true" && -f "$LOG_FILE" ]]; then
    local log_bytes
    log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    if [[ "$log_bytes" -eq 0 ]]; then
      effective_use_pty="true"
    fi
  fi

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
  meta_set "$META_FILE" "launch_marker_at" "$(now_utc)"
  meta_set "$META_FILE" "launch_state" "restarting"

  # Reset log file
  : > "$LOG_FILE"

  # Start new job
  [[ -x "$HEADLESS" ]] || { echo "headless wrapper not executable: $HEADLESS" >&2; exit 1; }
  if [[ "$effective_use_pty" == "true" ]]; then
    [[ -x "$PTY_RUN" ]] || { echo "PTY wrapper not executable: $PTY_RUN" >&2; exit 1; }
    nohup "$PTY_RUN" --output "$LOG_FILE" -- "$HEADLESS" --prompt-file "$prompt_file" >> "$LOG_FILE" 2>&1 &
    meta_set "$META_FILE" "execution_mode" "pty"
    meta_set "$META_FILE" "use_pty" "true"
  else
    nohup "$HEADLESS" --prompt-file "$prompt_file" >> "$LOG_FILE" 2>&1 &
    meta_set "$META_FILE" "execution_mode" "nohup"
    meta_set "$META_FILE" "use_pty" "false"
  fi
  local new_pid=$!
  echo "$new_pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$new_pid"
  meta_set "$META_FILE" "launch_state" "running"

  echo "restarted beads=$BEADS pid=$new_pid retries=$new_retries log=$LOG_FILE pty=$effective_use_pty"
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

  echo "watchdog started: interval=${WATCHDOG_INTERVAL}s stall=${STALL_MINUTES}m max-retries=${WATCHDOG_MAX_RETRIES} once=${WATCHDOG_ONCE} beads=${BEADS:-all}"
  echo "press Ctrl+C to stop"

  local iteration=0
  while true; do
    iteration=$((iteration + 1))
    echo "=== watchdog iteration $iteration at $(now_utc) ==="

    shopt -s nullglob
    local found=0
    local watch_targets=()
    if [[ -n "$BEADS" ]]; then
      watch_targets=("$BEADS")
    else
      local pidf
      for pidf in "$LOG_DIR"/*.pid; do
        watch_targets+=("$(basename "$pidf" .pid)")
      done
    fi
    for beads in "${watch_targets[@]}"; do
      found=1
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
            if ( restart_cmd --beads "$beads" --log-dir "$LOG_DIR" 2>&1 ); then
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

    if [[ "$WATCHDOG_ONCE" == "true" ]]; then
      echo "watchdog completed single iteration (--once)"
      break
    fi

    sleep "$WATCHDOG_INTERVAL"
  done
}

remote_start_host() {
  local host="$1"
  local remote_beads="$BEADS"
  local slug remote_prompt template

  slug="$(host_slug "$host")"
  if [[ "$HOST_SUFFIX_BEADS" == "true" ]]; then
    remote_beads="${BEADS}-${slug}"
  fi

  if [[ -n "$REMOTE_PROMPT_PATH" ]]; then
    template="$REMOTE_PROMPT_PATH"
  else
    template="/tmp/cc-glm-prompts/%BEADS%.prompt.txt"
  fi
  remote_prompt="$(render_template "$template" "$slug" "$remote_beads")"

  if [[ "$COPY_PROMPT" == "true" ]]; then
    upload_prompt_to_host "$host" "$PROMPT_FILE" "$remote_prompt"
  fi

  local args=(start --beads "$remote_beads" --prompt-file "$remote_prompt" --log-dir "$LOG_DIR")
  [[ -n "$REPO" ]] && args+=(--repo "$REPO")
  [[ -n "$WORKTREE" ]] && args+=(--worktree "$WORKTREE")
  [[ "$USE_PTY" == "true" ]] && args+=(--pty)

  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_status_host() {
  local host="$1"
  local args=(status --log-dir "$LOG_DIR")
  [[ -n "$BEADS" ]] && args+=(--beads "$BEADS")
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_check_host() {
  local host="$1"
  local args=(check --beads "$BEADS" --log-dir "$LOG_DIR" --stall-minutes "$STALL_MINUTES")
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_health_host() {
  local host="$1"
  local args=(health --log-dir "$LOG_DIR" --stall-minutes "$STALL_MINUTES")
  [[ -n "$BEADS" ]] && args+=(--beads "$BEADS")
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_restart_host() {
  local host="$1"
  local args=(restart --beads "$BEADS" --log-dir "$LOG_DIR")
  [[ "$USE_PTY" == "true" ]] && args+=(--pty)
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_stop_host() {
  local host="$1"
  local args=(stop --beads "$BEADS" --log-dir "$LOG_DIR")
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

remote_watchdog_host() {
  local host="$1"
  local args=(
    watchdog
    --log-dir "$LOG_DIR"
    --interval "$WATCHDOG_INTERVAL"
    --stall-minutes "$STALL_MINUTES"
    --max-retries "$WATCHDOG_MAX_RETRIES"
  )
  [[ -n "$BEADS" ]] && args+=(--beads "$BEADS")
  [[ "$WATCHDOG_ONCE" == "true" ]] && args+=(--once)
  [[ -n "$WATCHDOG_PIDFILE" ]] && args+=(--pidfile "$WATCHDOG_PIDFILE")
  remote_exec_cc_glm_job "$host" "${args[@]}"
}

ssh_start_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "ssh-start requires --beads" >&2; exit 2; }
  [[ -n "$PROMPT_FILE" ]] || { echo "ssh-start requires --prompt-file" >&2; exit 2; }
  [[ -f "$PROMPT_FILE" ]] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  ensure_remote_requirements
  parse_remote_hosts

  echo "ssh-start hosts=${REMOTE_HOSTS} beads=${BEADS} pty=${USE_PTY} parallel=${SSH_PARALLEL} copy_prompt=${COPY_PROMPT}"
  run_remote_hosts_parallel remote_start_host
}

ssh_status_cmd() {
  parse_common_args "$@"
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_status_host
}

ssh_check_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "ssh-check requires --beads" >&2; exit 2; }
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_check_host
}

ssh_health_cmd() {
  parse_common_args "$@"
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_health_host
}

ssh_restart_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "ssh-restart requires --beads" >&2; exit 2; }
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_restart_host
}

ssh_stop_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "ssh-stop requires --beads" >&2; exit 2; }
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_stop_host
}

ssh_watchdog_cmd() {
  parse_common_args "$@"
  ensure_remote_requirements
  parse_remote_hosts
  run_remote_hosts_parallel remote_watchdog_host
}

case "$CMD" in
  start) start_cmd "$@" ;;
  status) status_cmd "$@" ;;
  check) check_cmd "$@" ;;
  health) health_cmd "$@" ;;
  restart) restart_cmd "$@" ;;
  stop) stop_cmd "$@" ;;
  watchdog) watchdog_cmd "$@" ;;
  ssh-start) ssh_start_cmd "$@" ;;
  ssh-status) ssh_status_cmd "$@" ;;
  ssh-check) ssh_check_cmd "$@" ;;
  ssh-health) ssh_health_cmd "$@" ;;
  ssh-restart) ssh_restart_cmd "$@" ;;
  ssh-stop) ssh_stop_cmd "$@" ;;
  ssh-watchdog) ssh_watchdog_cmd "$@" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage
    exit 2
    ;;
esac
