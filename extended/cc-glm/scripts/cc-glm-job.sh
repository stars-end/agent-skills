#!/usr/bin/env bash
set -euo pipefail

# cc-glm-job.sh (V3.3 - Mutation Detection + Preflight)
#
# Lightweight background job manager for cc-glm headless runs.
# Keeps consistent artifacts under /tmp/cc-glm-jobs:
#   <beads>.pid, <beads>.log, <beads>.meta, <beads>.outcome, <beads>.contract
#   <beads>.log.<n> (rotated logs)
#   <beads>.outcome.<n> (rotated outcomes - V3.1)
#   <beads>.mutation (mutation marker - V3.3)
#
# Commands:
#   start        --beads <id> --prompt-file <path> [--repo <name>] [--worktree <path>] [--log-dir <dir>] [--pty]
#   status       [--beads <id>] [--log-dir <dir>] [--no-ansi] [--mutations]
#   check        --beads <id> [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi]
#   health       [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi]
#   restart      --beads <id> [--log-dir <dir>] [--pty] [--preserve-contract]
#   stop         --beads <id> [--log-dir <dir>]
#   tail         --beads <id> [--log-dir <dir>] [--lines <n>] [--no-ansi]
#   set-override --beads <id> [--no-auto-restart <true|false>] [--log-dir <dir>]
#   preflight    [--beads <id>] [--log-dir <dir>]  (V3.3)
#   mutations    --beads <id> [--log-dir <dir>]    (V3.3)
#   watchdog     [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>]
#                [--once] [--observe-only] [--no-auto-restart] [--pidfile <path>]
#
# V3.3 Changes:
#   - Mutation detection: tracks worktree file changes even when log is empty
#   - Preflight command: verifies auth/model/backend before job start
#   - Mutations command: shows worktree change summary for a job
#   - Status --mutations flag: shows mutation count in status output
#
# V3.2 Features (preserved):
#   - Watchdog modes: observe-only (monitor only, never restart), no-auto-restart (disable restarts)
#   - Per-bead override control: set-override command for fine-grained control
#   - Mode/override state surfaced in status/health output
#
# V3.1 Features (preserved):
#   - Forensic log retention: outcome rotation instead of deletion
#   - Enhanced outcome metadata: run_id, duration_sec, retries
#   - Status/health now show duration for completed jobs
#
# V3.0 Features (preserved):
#   - Progress-aware health: process liveness is primary signal, log growth is secondary
#   - Restart env contract integrity: preserves auth source/mode/model/base-url
#   - Log rotation on restart (no truncation)
#   - Operator guardrails: ANSI stripping

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADLESS="${SCRIPT_DIR}/cc-glm-headless.sh"
PTY_RUN="${SCRIPT_DIR}/pty-run.sh"

# Version for debugging
CC_GLM_JOB_VERSION="3.3.0"

LOG_DIR="/tmp/cc-glm-jobs"
CMD="${1:-}"
shift || true

usage() {
  cat <<'EOF'
cc-glm-job.sh (V3.3 - Mutation Detection + Preflight)

Usage:
  cc-glm-job.sh start --beads <id> --prompt-file <path> [options]
  cc-glm-job.sh status [--beads <id>] [--log-dir <dir>] [--no-ansi] [--mutations]
  cc-glm-job.sh check --beads <id> [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi]
  cc-glm-job.sh health [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi]
  cc-glm-job.sh restart --beads <id> [--log-dir <dir>] [--pty] [--preserve-contract]
  cc-glm-job.sh stop --beads <id> [--log-dir <dir>]
  cc-glm-job.sh tail --beads <id> [--log-dir <dir>] [--lines <n>] [--no-ansi]
  cc-glm-job.sh set-override --beads <id> [--no-auto-restart <true|false>]
  cc-glm-job.sh preflight [--beads <id>] [--log-dir <dir>]
  cc-glm-job.sh mutations --beads <id> [--log-dir <dir>]
  cc-glm-job.sh watchdog [--beads <id>] [options]

Commands:
  start        Launch a cc-glm job in background with nohup (default) or PTY wrapper.
  status       Show status table of jobs (all or specific).
  check        Check single job health (exit 2 if stalled, 3 if completed with error).
  health       Show detailed health state for jobs.
  restart      Restart a job (preserves metadata, rotates logs, increments retry count).
  stop         Stop a running job and record outcome.
  tail         Show last N lines of job log with optional ANSI stripping.
  set-override Set per-bead override flags for watchdog behavior.
  preflight    Verify job prerequisites (auth, model, backend) before start (V3.3).
  mutations    Show worktree file changes for a job (V3.3).
  watchdog     Run watchdog loop: monitor jobs, restart stalled jobs.

Options:
  --pty               Use PTY-backed execution for reliable output capture.
  --no-ansi           Strip ANSI codes from output.
  --mutations         Show mutation count in status output (V3.3).
  --observe-only      Watchdog monitors but never restarts (observe-only mode).
  --no-auto-restart   Disable auto-restart for specific beads in watchdog.
  --preserve-contract On restart, abort if env contract cannot be preserved.
  --once              Run exactly one watchdog iteration, then exit.
  --lines N           Number of lines for tail command (default: 20).

V3.3 Features:
  - Mutation detection: tracks worktree file changes even when log is empty
  - Preflight check: verifies auth/model/backend before job start
  - Use --mutations flag with status to see file change counts

Watchdog Modes (V3.2):
  normal            - Default: restart stalled jobs up to max-retries, then block.
  observe-only      - Monitor jobs but never restart (useful for manual supervision).
  no-auto-restart   - Disable restarts globally or per-bead (sets blocked flag).

Per-Bead Overrides (V3.2):
  Use set-override to control watchdog behavior for individual beads:
    cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart true
    cc-glm-job.sh set-override --beads bd-xxx --no-auto-restart false

  When no-auto-restart is true, watchdog will mark job as blocked instead of
  restarting. This is useful when an operator wants to manually supervise.

Health States (V3.2):
  healthy      - Process running with recent activity
  starting     - Process running but within grace window
  stalled      - Process alive but no progress for N minutes
  exited_ok    - Process exited with code 0 (completed successfully)
  exited_err   - Process exited with non-zero code (crashed/failed)
  blocked      - Max retries exhausted OR no-auto-restart set
  missing      - No metadata found for job

Exit Codes:
  0  - Success (or healthy)
  1  - General error
  2  - Job stalled
  3  - Job exited with error
  10 - Auth resolution failed
  11 - Token file error

Job Artifacts:
  <beads>.pid         - Process ID file
  <beads>.log         - Current output log
  <beads>.log.<n>     - Rotated logs (preserved on restart)
  <beads>.meta        - Job metadata (repo, worktree, retries, no_auto_restart, etc.)
  <beads>.outcome     - Final outcome (run_id, exit_code, state, duration_sec)
  <beads>.outcome.<n> - Rotated outcomes (V3.1 forensic history)
  <beads>.contract    - Runtime contract (auth_source, model, base_url)
  <beads>.mutation    - Mutation marker (mutation_count, checked_at) (V3.3)

Outcome Metadata Fields (V3.2):
  beads        - Beads ID
  run_id       - Unique run identifier (timestamp-based)
  exit_code    - Process exit code
  state        - success/failed/killed
  completed_at - ISO 8601 completion timestamp
  duration_sec - Total run duration in seconds
  retries      - Number of restarts before completion

Notes:
  - Log rotation: old logs preserved as <beads>.log.<n> on restart
  - Outcome rotation: old outcomes preserved as <beads>.outcome.<n> (V3.1)
  - Contract file ensures restart consistency (no env drift)
  - status/health show outcome with duration for completed jobs
  - Per-bead no-auto-restart is stored in meta file and persists across restarts
  - Use 'preflight' before dispatching to catch auth/config issues early
  - Use 'mutations --beads <id>' to inspect worktree changes for stalled jobs
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

# Strip ANSI escape sequences
strip_ansi() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || cat
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
  OUTCOME_FILE="${LOG_DIR}/${beads}.outcome"
  CONTRACT_FILE="${LOG_DIR}/${beads}.contract"
  MUTATION_FILE="${LOG_DIR}/${beads}.mutation"
}

# V3.3: Mutation detection
# Checks worktree for file changes and writes mutation marker
# Returns: number of changed files (0 if none or no worktree)
check_mutations() {
  local beads="$1"
  job_paths "$beads"

  local worktree
  worktree="$(meta_get "$META_FILE" "worktree" 2>/dev/null || true)"

  if [[ -z "$worktree" || ! -d "$worktree" ]]; then
    echo 0
    return 0
  fi

  local changed=0
  if [[ -d "$worktree/.git" ]]; then
    # Git worktree - use git status
    changed="$(cd "$worktree" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  else
    # Non-git worktree - use find for recent modifications
    local threshold_epoch
    threshold_epoch="$(date -d "$(meta_get "$META_FILE" "started_at" 2>/dev/null || date -u -Iseconds)" +%s 2>/dev/null || date +%s)"
    # Find files modified since job start
    changed="$(find "$worktree" -type f -newer "$META_FILE" 2>/dev/null | wc -l | tr -d ' ')"
  fi

  echo "${changed:-0}"
}

# Write mutation marker file
write_mutation_marker() {
  local beads="$1"
  local count="$2"
  job_paths "$beads"

  cat > "$MUTATION_FILE" <<EOF
beads=$beads
mutation_count=$count
checked_at=$(now_utc)
EOF
}

# Preflight check for job prerequisites (V3.3)
# Verifies: auth token resolvable, backend reachable, worktree accessible
# Exit codes: 0=ok, 1=error, 10=auth issue, 11=token file issue
preflight_check() {
  local beads="${1:-}"
  local errors=0

  echo "=== Preflight Check ==="
  echo "timestamp: $(now_utc)"
  [[ -n "$beads" ]] && echo "beads: $beads"

  # Check 1: Claude binary
  echo -n "claude binary: "
  if command -v claude >/dev/null 2>&1; then
    echo "OK ($(command -v claude))"
  else
    echo "MISSING"
    echo "  ERROR: claude CLI not found"
    errors=$((errors + 1))
  fi

  # Check 2: Auth token resolvable
  echo -n "auth resolution: "
  local auth_ok=false
  local auth_source=""

  if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
    auth_ok=true
    auth_source="CC_GLM_AUTH_TOKEN"
  elif [[ -n "${CC_GLM_TOKEN_FILE:-}" ]]; then
    if [[ -f "${CC_GLM_TOKEN_FILE}" ]]; then
      auth_ok=true
      auth_source="CC_GLM_TOKEN_FILE"
    else
      echo "TOKEN_FILE_MISSING"
      echo "  ERROR: CC_GLM_TOKEN_FILE=${CC_GLM_TOKEN_FILE} not found"
      errors=$((errors + 1))
    fi
  elif [[ -n "${ZAI_API_KEY:-}" ]]; then
    if [[ "$ZAI_API_KEY" == op://* ]]; then
      # op:// reference - check op CLI and try to resolve
      if command -v op >/dev/null 2>&1; then
        auth_source="ZAI_API_KEY (op://)"
        # Try resolution (may fail if op not authenticated)
        if op read "$ZAI_API_KEY" >/dev/null 2>&1; then
          auth_ok=true
        else
          echo "OP_RESOLUTION_FAILED"
          echo "  ERROR: Cannot resolve op:// reference - op not authenticated or token expired"
          errors=$((errors + 1))
        fi
      else
        echo "OP_CLI_MISSING"
        echo "  ERROR: ZAI_API_KEY is op:// reference but op CLI not found"
        errors=$((errors + 1))
      fi
    else
      auth_ok=true
      auth_source="ZAI_API_KEY"
    fi
  elif [[ -n "${CC_GLM_OP_URI:-}" ]]; then
    auth_source="CC_GLM_OP_URI"
    if command -v op >/dev/null 2>&1; then
      if op read "$CC_GLM_OP_URI" >/dev/null 2>&1; then
        auth_ok=true
      else
        echo "OP_RESOLUTION_FAILED"
        echo "  ERROR: Cannot resolve CC_GLM_OP_URI"
        errors=$((errors + 1))
      fi
    else
      echo "OP_CLI_MISSING"
      echo "  ERROR: CC_GLM_OP_URI requires op CLI"
      errors=$((errors + 1))
    fi
  else
    # Try default op:// path
    if command -v op >/dev/null 2>&1; then
      auth_source="default op://"
      if op read "op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY" >/dev/null 2>&1; then
        auth_ok=true
      else
        echo "NO_AUTH_SOURCE"
        echo "  ERROR: No auth source configured and default op:// resolution failed"
        echo "  Set CC_GLM_AUTH_TOKEN, ZAI_API_KEY, or CC_GLM_OP_URI"
        errors=$((errors + 1))
      fi
    else
      echo "NO_AUTH_SOURCE"
      echo "  ERROR: No auth source configured"
      errors=$((errors + 1))
    fi
  fi

  if [[ "$auth_ok" == "true" ]]; then
    echo "OK ($auth_source)"
  fi

  # Check 3: Model configuration
  echo -n "model config: "
  local model="${CC_GLM_MODEL:-glm-5}"
  echo "OK ($model)"

  # Check 4: Base URL / backend
  echo -n "backend URL: "
  local base_url="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}"
  echo "$base_url"
  # Note: We don't actually ping the backend to avoid latency/auth exposure

  # Check 5: Worktree (if beads specified)
  if [[ -n "$beads" ]]; then
    job_paths "$beads"
    echo -n "worktree: "
    if [[ -f "$META_FILE" ]]; then
      local worktree
      worktree="$(meta_get "$META_FILE" "worktree" 2>/dev/null || true)"
      if [[ -n "$worktree" && -d "$worktree" ]]; then
        echo "OK ($worktree)"
      elif [[ -n "$worktree" ]]; then
        echo "MISSING ($worktree)"
        errors=$((errors + 1))
      else
        echo "NOT_CONFIGURED"
      fi
    else
      echo "NO_META_FILE"
    fi
  fi

  echo ""
  if [[ $errors -eq 0 ]]; then
    echo "=== Preflight PASSED ==="
    return 0
  else
    echo "=== Preflight FAILED ($errors error(s)) ==="
    return 1
  fi
}

# Process state (no file dependency)
process_state() {
  local pid="$1"
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

job_state() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    printf "missing"
    return 0
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  process_state "$pid"
}

# Get process CPU time (for progress detection)
# Returns user+system seconds, or 0 if unavailable
parse_decimal_component() {
  local raw="$1"
  local normalized="${raw%.*}"
  if [[ -z "$normalized" ]]; then
    echo 0
    return 0
  fi
  # Force base-10 to avoid octal parsing on leading zeros (08, 09).
  if [[ "$normalized" =~ ^[0-9]+$ ]]; then
    echo $((10#$normalized))
    return 0
  fi
  echo 0
}

process_cpu_time() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    echo 0
    return 0
  fi
  # macOS: ps -o time= -p PID gives "MM:SS.ss" or "H:MM:SS.ss"
  # Linux: ps -o time= -p PID gives "MM:SS" or "H:MM:SS"
  local time_str
  time_str="$(ps -o time= -p "$pid" 2>/dev/null | tr -d ' ')" || { echo 0; return 0; }
  if [[ -z "$time_str" ]]; then
    echo 0
    return 0
  fi
  # Parse time format
  local parts seconds
  IFS=':' read -ra parts <<< "$time_str"
  case "${#parts[@]}" in
    2)
      # MM:SS or MM:SS.ss
      seconds=$(( $(parse_decimal_component "${parts[0]}") * 60 + $(parse_decimal_component "${parts[1]}") ))
      ;;
    3)
      # H:MM:SS or H:MM:SS.ss
      seconds=$(( $(parse_decimal_component "${parts[0]}") * 3600 + $(parse_decimal_component "${parts[1]}") * 60 + $(parse_decimal_component "${parts[2]}") ))
      ;;
    *)
      seconds=0
      ;;
  esac
  echo "$seconds"
}

# Persist runtime contract (non-secret metadata for restart integrity)
persist_contract() {
  local beads="$1"
  local contract_file="$2"
  local auth_source auth_mode execution_mode

  auth_source="$(meta_get "$META_FILE" "auth_source")"
  [[ -n "$auth_source" ]] || auth_source="${CC_GLM_AUTH_SOURCE:-unknown}"

  auth_mode="$(meta_get "$META_FILE" "auth_mode")"
  [[ -n "$auth_mode" ]] || auth_mode="$([[ "${CC_GLM_STRICT_AUTH:-1}" == "0" ]] && echo "non_strict" || echo "strict")"

  # execution_mode: prefer meta file, then env var (with safe default under set -u)
  execution_mode="$(meta_get "$META_FILE" "execution_mode")"
  if [[ -z "$execution_mode" ]]; then
    # Use environment variable if set, otherwise default to nohup
    execution_mode="${EXECUTION_MODE:+$EXECUTION_MODE}"
    execution_mode="${execution_mode:-nohup}"
  fi

  cat > "$contract_file" <<EOF
# Runtime contract for $beads (generated $(now_utc))
# DO NOT store secrets here
auth_source=${auth_source}
auth_mode=${auth_mode}
model=${CC_GLM_MODEL:-glm-5}
base_url=${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}
timeout_ms=${CC_GLM_TIMEOUT_MS:-3000000}
execution_mode=${execution_mode}
EOF
}

# Verify contract can be preserved on restart
verify_contract() {
  local contract_file="$1"
  if [[ ! -f "$contract_file" ]]; then
    return 0  # No contract = first run, ok to proceed
  fi

  local saved_model saved_base saved_timeout saved_auth_source saved_auth_mode saved_exec_mode
  local current_model current_base current_timeout current_auth_source current_auth_mode current_exec_mode

  saved_model="$(meta_get "$contract_file" "model")"
  saved_base="$(meta_get "$contract_file" "base_url")"
  saved_timeout="$(meta_get "$contract_file" "timeout_ms")"
  saved_auth_source="$(meta_get "$contract_file" "auth_source")"
  saved_auth_mode="$(meta_get "$contract_file" "auth_mode")"
  saved_exec_mode="$(meta_get "$contract_file" "execution_mode")"

  current_model="${CC_GLM_MODEL:-glm-5}"
  current_base="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}"
  current_timeout="${CC_GLM_TIMEOUT_MS:-3000000}"
  current_auth_source="$(meta_get "$META_FILE" "auth_source")"
  [[ -n "$current_auth_source" ]] || current_auth_source="${CC_GLM_AUTH_SOURCE:-unknown}"
  current_auth_mode="$(meta_get "$META_FILE" "auth_mode")"
  [[ -n "$current_auth_mode" ]] || current_auth_mode="$([[ "${CC_GLM_STRICT_AUTH:-1}" == "0" ]] && echo "non_strict" || echo "strict")"
  current_exec_mode="$(meta_get "$META_FILE" "execution_mode")"
  [[ -n "$current_exec_mode" ]] || current_exec_mode="nohup"

  # Backward compatibility: if a key is absent in legacy contracts, skip that comparison.
  if [[ -n "$saved_model" && "$saved_model" != "$current_model" ]]; then
    return 1
  fi
  if [[ -n "$saved_base" && "$saved_base" != "$current_base" ]]; then
    return 1
  fi
  if [[ -n "$saved_timeout" && "$saved_timeout" != "$current_timeout" ]]; then
    return 1
  fi
  if [[ -n "$saved_auth_source" && "$saved_auth_source" != "$current_auth_source" ]]; then
    return 1
  fi
  if [[ -n "$saved_auth_mode" && "$saved_auth_mode" != "$current_auth_mode" ]]; then
    return 1
  fi
  if [[ -n "$saved_exec_mode" && "$saved_exec_mode" != "$current_exec_mode" ]]; then
    return 1  # Contract mismatch
  fi
  return 0
}

# Rotate log file (preserve history, no truncation)
rotate_log() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    return 0
  fi

  local log_bytes
  log_bytes="$(wc -c < "$log_file" | tr -d ' ')"
  if [[ "$log_bytes" -eq 0 ]]; then
    # Empty log, just remove it
    rm -f "$log_file"
    return 0
  fi

  # Find next rotation number
  local base_dir base_name n=1
  base_dir="$(dirname "$log_file")"
  base_name="$(basename "$log_file" .log)"
  while [[ -f "${base_dir}/${base_name}.log.${n}" ]]; do
    n=$((n + 1))
  done

  # Rotate
  mv "$log_file" "${base_dir}/${base_name}.log.${n}"
}

# Rotate outcome file (preserve forensic history)
# Renames outcome -> outcome.1, outcome.1 -> outcome.2, etc.
rotate_outcome() {
  local outcome_file="$1"
  if [[ ! -f "$outcome_file" ]]; then
    return 0
  fi

  local base_dir base_name n=1
  base_dir="$(dirname "$outcome_file")"
  base_name="$(basename "$outcome_file" .outcome)"

  # Find next rotation number
  while [[ -f "${base_dir}/${base_name}.outcome.${n}" ]]; do
    n=$((n + 1))
  done

  # Rotate
  mv "$outcome_file" "${base_dir}/${base_name}.outcome.${n}"
}

# Persist outcome metadata (V3.1: enhanced with run_id, duration, retries)
persist_outcome() {
  local beads="$1"
  local exit_code="$2"
  local outcome_file="$3"
  local meta_file="$4"

  local state="failed"
  if [[ "$exit_code" -eq 0 ]]; then
    state="success"
  elif [[ "$exit_code" -eq 137 ]]; then
    state="killed"
  fi

  # Calculate duration if we have start time
  local duration_sec="-"
  local started_at=""
  if [[ -f "$meta_file" ]]; then
    started_at="$(meta_get "$meta_file" "started_at")"
    if [[ -n "$started_at" ]]; then
      local now_epoch start_epoch
      now_epoch="$(date +%s)"
      # Parse ISO 8601 timestamp (assumes UTC)
      start_epoch="$(date -d "${started_at}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${started_at}" +%s 2>/dev/null || echo "")"
      if [[ -n "$start_epoch" ]]; then
        duration_sec=$((now_epoch - start_epoch))
      fi
    fi
  fi

  # Get final retry count
  local final_retries="0"
  if [[ -f "$meta_file" ]]; then
    final_retries="$(meta_get "$meta_file" "retries")"
    final_retries="${final_retries:-0}"
  fi

  # Generate run_id (timestamp-based for uniqueness)
  local run_id
  run_id="$(date +%Y%m%d%H%M%S)"

  cat > "$outcome_file" <<EOF
beads=$beads
run_id=$run_id
exit_code=$exit_code
state=$state
completed_at=$(now_utc)
duration_sec=$duration_sec
retries=$final_retries
EOF
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
  WATCHDOG_OBSERVE_ONLY=false
  WATCHDOG_NO_AUTO_RESTART=false
  OVERRIDE_NO_AUTO_RESTART=""  # For set-override command: "true", "false", or ""
  USE_PTY=false
  NO_ANSI=false
  PRESERVE_CONTRACT=false
  TAIL_LINES=20
  SHOW_OVERRIDES=false
  SHOW_MUTATIONS=false  # V3.3

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
      --observe-only)
        WATCHDOG_OBSERVE_ONLY=true
        shift
        ;;
      --no-auto-restart)
        # Can be either a flag (for watchdog) or a value (for set-override)
        if [[ -n "${2:-}" ]] && [[ "$2" == "true" || "$2" == "false" ]]; then
          OVERRIDE_NO_AUTO_RESTART="$2"
          shift 2
        else
          WATCHDOG_NO_AUTO_RESTART=true
          shift
        fi
        ;;
      --pidfile)
        WATCHDOG_PIDFILE="${2:-}"
        shift 2
        ;;
      --pty)
        USE_PTY=true
        shift
        ;;
      --no-ansi)
        NO_ANSI=true
        shift
        ;;
      --preserve-contract)
        PRESERVE_CONTRACT=true
        shift
        ;;
      --lines)
        TAIL_LINES="${2:-20}"
        shift 2
        ;;
      --show-overrides)
        SHOW_OVERRIDES=true
        shift
        ;;
      --mutations)
        SHOW_MUTATIONS=true
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

# Warn about alternative log directories
warn_alternative_log_dirs() {
  if [[ "$LOG_DIR" == "/tmp/cc-glm-jobs" ]]; then
    return 0  # Default location, no warning needed
  fi

  # Check if default dir has jobs
  if [[ -d "/tmp/cc-glm-jobs" ]] && ls /tmp/cc-glm-jobs/*.pid >/dev/null 2>&1; then
    echo "WARN: Using non-default log-dir: $LOG_DIR" >&2
    echo "WARN: Default /tmp/cc-glm-jobs has existing jobs" >&2
  fi
}

# Show hint about log directory locality
show_log_locality_hint() {
  local host
  host="$(hostname 2>/dev/null || echo "unknown")"
  echo "hint: logs on $host at $LOG_DIR"
}

# Show enhanced locality hint with remote log suggestions when local is empty/stale
# Usage: show_enhanced_locality_hint [--stale]
show_enhanced_locality_hint() {
  local is_stale="${1:-}"
  local host
  host="$(hostname 2>/dev/null || echo "unknown")"

  # Count local jobs
  local local_count=0
  shopt -s nullglob
  local pids=("$LOG_DIR"/*.pid)
  local_count=${#pids[@]}

  if [[ "$is_stale" == "--stale" ]] || [[ $local_count -eq 0 ]]; then
    # Local is empty or stale - suggest where to look for authoritative logs
    echo "hint: local logs on $host at $LOG_DIR are $([ $local_count -eq 0 ] && echo "empty" || echo "stale")"
    echo "hint: if jobs were dispatched to remote VMs, check:"
    echo "  - macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh status'"
    echo "  - epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh status'"
    echo "  - homedesktop-wsl: tailscale ssh fengning@homedesktop-wsl 'cc-glm-job.sh status'"

    # Check for remote log dir patterns that might indicate cross-VM dispatch
    local found_remote_hints=()
    if [[ -d "$HOME/.cache/dx-dispatch" ]]; then
      found_remote_hints+=("$HOME/.cache/dx-dispatch (dx-dispatch cache)")
    fi
    if [[ -f "$HOME/.config/dx-dispatch" ]]; then
      found_remote_hints+=("$HOME/.config/dx-dispatch (dx-dispatch config)")
    fi

    if [[ ${#found_remote_hints[@]} -gt 0 ]]; then
      echo "hint: found dispatch artifacts suggesting remote execution:"
      printf '  - %s\n' "${found_remote_hints[@]}"
    fi
  else
    # Normal case - just show the standard hint
    echo "hint: logs on $host at $LOG_DIR ($local_count job(s))"
  fi
}

suggest_alternative_log_dirs() {
  if [[ "$LOG_DIR" == "/tmp/cc-glm-jobs" ]]; then
    shopt -s nullglob
    local alt_dirs=()
    for d in /tmp/cc-glm-jobs-*; do
      [[ -d "$d" ]] || continue
      alt_dirs+=("$d")
    done
    if [[ "${#alt_dirs[@]}" -gt 0 ]]; then
      echo "hint: found alternate log dirs:"
      printf '  %s\n' "${alt_dirs[@]}"
      echo "hint: rerun with --log-dir <one-of-the-above>"
    fi
  fi
}

# Guardrail: warn about multi-log-dir ambiguity before operations
# Returns 0 if ok to proceed, 1 if user should be warned
check_log_dir_ambiguity() {
  local operation="$1"
  local warn_file="/tmp/.cc-glm-last-logdir-warning"

  # Only warn for default log dir
  if [[ "$LOG_DIR" != "/tmp/cc-glm-jobs" ]]; then
    return 0
  fi

  # Check for alternative log dirs
  shopt -s nullglob
  local alt_dirs=()
  for d in /tmp/cc-glm-jobs-*; do
    [[ -d "$d" ]] || continue
    alt_dirs+=("$d")
  done

  if [[ ${#alt_dirs[@]} -gt 0 ]]; then
    # Throttle warnings (max once per hour)
    local now hour_ago
    now="$(date +%s)"
    hour_ago=$((now - 3600))

    if [[ -f "$warn_file" ]]; then
      local last_warn
      last_warn="$(cat "$warn_file" 2>/dev/null || echo "0")"
      if [[ "$last_warn" -gt "$hour_ago" ]]; then
        return 0  # Already warned recently
      fi
    fi

    echo "WARN: Multiple log directories detected. Using default: $LOG_DIR"
    echo "WARN: Alternative dirs found:"
    printf '  - %s\n' "${alt_dirs[@]}"
    echo "WARN: Use --log-dir <path> to target a specific directory"
    echo "WARN: (this warning throttles to once per hour)"

    echo "$now" > "$warn_file"
  fi

  return 0
}

start_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "start requires --beads" >&2; exit 2; }
  [[ -n "$PROMPT_FILE" ]] || { echo "start requires --prompt-file" >&2; exit 2; }
  [[ -f "$PROMPT_FILE" ]] || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  [[ -x "$HEADLESS" ]] || { echo "headless wrapper not executable: $HEADLESS" >&2; exit 1; }

  mkdir -p "$LOG_DIR"
  job_paths "$BEADS"

  # Warn about alternative log dirs
  warn_alternative_log_dirs

  local state
  state="$(job_state "$PID_FILE")"
  if [[ "$state" == "running" ]]; then
    echo "job $BEADS already running (pid=$(cat "$PID_FILE"))" >&2
    exit 1
  fi

  # Rotate any existing log
  rotate_log "$LOG_FILE"

  # Rotate outcome from previous run (preserve forensic history)
  rotate_outcome "$OUTCOME_FILE"

  cat > "$META_FILE" <<EOF
beads=$BEADS
repo=$REPO
worktree=$WORKTREE
prompt_file=$PROMPT_FILE
started_at=$(now_utc)
retries=0
use_pty=$USE_PTY
version=$CC_GLM_JOB_VERSION
EOF
  meta_set "$META_FILE" "launch_marker_at" "$(now_utc)"
  meta_set "$META_FILE" "launch_state" "starting"

  # Capture auth source if available
  local auth_source="unknown"
  if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
    auth_source="CC_GLM_AUTH_TOKEN"
  elif [[ -n "${CC_GLM_TOKEN_FILE:-}" ]]; then
    auth_source="CC_GLM_TOKEN_FILE"
  elif [[ -n "${ZAI_API_KEY:-}" ]]; then
    auth_source="ZAI_API_KEY"
  elif [[ -n "${CC_GLM_OP_URI:-}" ]]; then
    auth_source="CC_GLM_OP_URI"
  fi
  meta_set "$META_FILE" "auth_source" "$auth_source"
  meta_set "$META_FILE" "auth_mode" "$([[ "${CC_GLM_STRICT_AUTH:-1}" == "0" ]] && echo "non_strict" || echo "strict")"

  # Detached run; stdout/stderr go to per-job log.
  local exec_mode="nohup"  # Default; overridden below if PTY mode
  if [[ "$USE_PTY" == "true" ]]; then
    [[ -x "$PTY_RUN" ]] || { echo "PTY wrapper not executable: $PTY_RUN" >&2; exit 1; }
    # PTY handles output via --output; shell redirect is for pty-run's own stderr only
    nohup "$PTY_RUN" --output "$LOG_FILE" -- "$HEADLESS" --prompt-file "$PROMPT_FILE" 2>> "$LOG_FILE" &
    exec_mode="pty"
  else
    nohup "$HEADLESS" --prompt-file "$PROMPT_FILE" >> "$LOG_FILE" 2>&1 &
    exec_mode="nohup"
  fi
  local pid=$!
  echo "$pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$pid"
  meta_set "$META_FILE" "launch_state" "running"
  meta_set "$META_FILE" "execution_mode" "$exec_mode"
  persist_contract "$BEADS" "$CONTRACT_FILE"

  echo "started beads=$BEADS pid=$pid log=$LOG_FILE pty=$USE_PTY"
}

status_line() {
  local beads="$1"
  job_paths "$beads"
  local pid="" state="missing" log_bytes="0" last_update="-" retries="0" elapsed="-" outcome="-" duration="-" override="" mutations="-"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  state="$(job_state "$PID_FILE")"

  # Check for completed outcome
  if [[ -f "$OUTCOME_FILE" ]]; then
    local outcome_state outcome_exit outcome_duration
    outcome_state="$(meta_get "$OUTCOME_FILE" "state")"
    outcome_exit="$(meta_get "$OUTCOME_FILE" "exit_code")"
    outcome_duration="$(meta_get "$OUTCOME_FILE" "duration_sec")"
    outcome="${outcome_state:-completed}:${outcome_exit:-?}"
    if [[ -n "$outcome_duration" && "$outcome_duration" != "-" && "$outcome_duration" != "-"* ]]; then
      outcome="${outcome} (${outcome_duration}s)"
    fi
  fi

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
    local no_auto_restart blocked
    no_auto_restart="$(meta_get "$META_FILE" "no_auto_restart")"
    blocked="$(meta_get "$META_FILE" "blocked")"
    if [[ "$no_auto_restart" == "true" ]]; then
      override="no-restart"
    elif [[ "$blocked" == "true" ]]; then
      override="blocked"
    fi
  fi

  # V3.3: Check for mutations if requested
  if [[ "$SHOW_MUTATIONS" == "true" ]]; then
    mutations="$(check_mutations "$beads")"
    # Write mutation marker for later queries
    write_mutation_marker "$beads" "$mutations"
  fi

  # Elapsed from PID file age
  if [[ -f "$PID_FILE" ]]; then
    local pid_mtime now
    pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
    if [[ -n "$pid_mtime" ]]; then
      now="$(date +%s)"
      elapsed="$(format_elapsed "$((now - pid_mtime))")"
    fi
  fi

  local output
  if [[ "$SHOW_MUTATIONS" == "true" && "$SHOW_OVERRIDES" == "true" ]]; then
    output="$(printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-9s %-10s %s" \
      "$beads" "${pid:--}" "$state" "$elapsed" "$log_bytes" "$last_update" "$retries" "$mutations" "$override" "$outcome")"
  elif [[ "$SHOW_MUTATIONS" == "true" ]]; then
    output="$(printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-9s %s" \
      "$beads" "${pid:--}" "$state" "$elapsed" "$log_bytes" "$last_update" "$retries" "$mutations" "$outcome")"
  elif [[ "$SHOW_OVERRIDES" == "true" ]]; then
    output="$(printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-10s %s" \
      "$beads" "${pid:--}" "$state" "$elapsed" "$log_bytes" "$last_update" "$retries" "$override" "$outcome")"
  else
    output="$(printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %s" \
      "$beads" "${pid:--}" "$state" "$elapsed" "$log_bytes" "$last_update" "$retries" "$outcome")"
  fi

  if [[ "$NO_ANSI" == "true" ]]; then
    echo "$output" | strip_ansi
  else
    echo "$output"
  fi
}

status_cmd() {
  parse_common_args "$@"

  # Guardrail: warn about multi-log-dir ambiguity
  check_log_dir_ambiguity "status"

  if [[ "$SHOW_MUTATIONS" == "true" && "$SHOW_OVERRIDES" == "true" ]]; then
    printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-9s %-10s %s\n" \
      "bead" "pid" "state" "elapsed" "bytes" "last_update" "retry" "mut" "override" "outcome"
  elif [[ "$SHOW_MUTATIONS" == "true" ]]; then
    printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-9s %s\n" \
      "bead" "pid" "state" "elapsed" "bytes" "last_update" "retry" "mut" "outcome"
  elif [[ "$SHOW_OVERRIDES" == "true" ]]; then
    printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %-10s %s\n" \
      "bead" "pid" "state" "elapsed" "bytes" "last_update" "retry" "override" "outcome"
  else
    printf "%-14s %-8s %-12s %-9s %-9s %-16s %-6s %s\n" \
      "bead" "pid" "state" "elapsed" "bytes" "last_update" "retry" "outcome"
  fi

  if [[ -n "$BEADS" ]]; then
    status_line "$BEADS"
    show_log_locality_hint
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
    suggest_alternative_log_dirs
    show_enhanced_locality_hint  # Show remote log hints when local is empty
  else
    show_log_locality_hint
  fi
}

# V3.0: Progress-aware health check
# Uses process CPU time as primary signal, log growth as secondary
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

  # Check if process is still running
  if ! ps -p "$pid" >/dev/null 2>&1; then
    # Process exited - check outcome
    if [[ -f "$OUTCOME_FILE" ]]; then
      local exit_code
      exit_code="$(meta_get "$OUTCOME_FILE" "exit_code")"
      exit_code="${exit_code:-1}"
      if [[ "$exit_code" -eq 0 ]]; then
        printf "exited_ok"
      else
        printf "exited_err"
      fi
      return 0
    fi

    # No outcome file - check log for evidence
    local log_bytes=0
    if [[ -f "$LOG_FILE" ]]; then
      log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    fi

    if [[ "$log_bytes" -eq 0 ]]; then
      printf "stalled"  # Exited with no output = stalled/failed launch
    else
      # Heuristic: check last line for success indicators
      local last_line
      last_line="$(tail -1 "$LOG_FILE" 2>/dev/null || true)"
      if [[ "$last_line" == *"success"* ]] || [[ "$last_line" == *"completed"* ]]; then
        printf "exited_ok"
      else
        printf "exited_err"
      fi
    fi
    return 0
  fi

  # Process is running - check for blocked state
  if [[ -f "$META_FILE" ]]; then
    local blocked
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

  # Get process CPU time for progress detection
  local cpu_time
  cpu_time="$(process_cpu_time "$pid")"

  # Check for zero output - use grace window
  local log_bytes
  log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if [[ "$log_bytes" -eq 0 ]]; then
    local pid_age=0
    if [[ -f "$PID_FILE" ]]; then
      local pid_mtime
      pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
      if [[ -n "$pid_mtime" ]]; then
        pid_age=$(( $(date +%s) - pid_mtime ))
      fi
    fi
    # If process has CPU time but no log output, it's making progress
    if [[ "$cpu_time" -gt 0 ]]; then
      printf "healthy"  # Process is working, just hasn't written yet
      return 0
    fi
    # V3.2.1: Process alive but no output/CPU time - treat as active startup, not stalled
    # Only consider truly stalled if we've seen NO progress for multiple check intervals
    # This prevents false-positive restarts during slow startup (e.g., auth, model loading)
    if [[ "$pid_age" -gt "$stall_threshold" ]]; then
      # Check if we've recorded CPU time before (indicates repeated checks)
      if [[ -f "$META_FILE" ]]; then
        local prev_cpu_check
        prev_cpu_check="$(meta_get "$META_FILE" "last_cpu_time")"
        if [[ -n "$prev_cpu_check" && "$prev_cpu_check" != "0" ]]; then
          # We've seen CPU activity before, now it's gone - truly stalled
          printf "stalled"
          return 0
        fi
      fi
      # First time we're seeing zero CPU after threshold - give benefit of doubt
      # Record that we're in extended startup for next check
      if [[ -f "$META_FILE" ]]; then
        meta_set "$META_FILE" "extended_startup" "true"
      fi
      printf "starting"  # Still in startup, even past threshold
      return 0
    fi
    printf "starting"  # Within grace window
    return 0
  fi

  # Has output - check log staleness as secondary signal
  local now mtime age
  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$LOG_FILE")"
  age=$((now - mtime))

  # Primary signal: process CPU time indicates activity
  # Save current CPU time to meta for comparison on next check
  if [[ -f "$META_FILE" ]]; then
    local prev_cpu
    prev_cpu="$(meta_get "$META_FILE" "last_cpu_time")"
    prev_cpu="${prev_cpu:-0}"
    meta_set "$META_FILE" "last_cpu_time" "$cpu_time"

    # If CPU time increased, process is making progress regardless of log
    if [[ "$cpu_time" -gt "$prev_cpu" ]]; then
      printf "healthy"
      return 0
    fi
  fi

  # Secondary signal: log staleness
  if [[ "$age" -gt "$stall_threshold" ]]; then
    # Log is stale AND CPU time didn't increase = stalled
    printf "stalled"
    return 0
  fi

  printf "healthy"
}

check_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "check requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  if [[ ! -f "$META_FILE" ]]; then
    echo "job $BEADS has no metadata file"
    # Help operator find job on remote hosts
    echo "hint: if job was dispatched to a remote VM, check:" >&2
    echo "  macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh check --beads $BEADS'" >&2
    echo "  epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh check --beads $BEADS'" >&2
    suggest_alternative_log_dirs
    exit 1
  fi

  local health
  health="$(job_health "$BEADS" "$((STALL_MINUTES * 60))")"

  local output
  case "$health" in
    healthy)
      output="job $BEADS healthy: running with progress"
      ;;
    starting)
      output="job $BEADS starting: within grace window"
      ;;
    stalled)
      output="job $BEADS stalled: no progress detected"
      # Add remote hints for stalled jobs
      echo "hint: if job was dispatched remotely, check authoritative logs:" >&2
      echo "  macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh tail --beads $BEADS'" >&2
      ;;
    exited_ok)
      output="job $BEADS completed successfully (exit 0)"
      ;;
    exited_err)
      output="job $BEADS exited with error"
      ;;
    blocked)
      output="job $BEADS blocked: max retries exhausted"
      ;;
    missing)
      output="job $BEADS missing: no job state found"
      ;;
    *)
      output="job $BEADS state=$health"
      ;;
  esac

  if [[ "$NO_ANSI" == "true" ]]; then
    echo "$output" | strip_ansi
  else
    echo "$output"
  fi

  # Exit codes for scripting
  case "$health" in
    healthy|starting|exited_ok) exit 0 ;;
    stalled) exit 2 ;;
    exited_err|blocked) exit 3 ;;
    missing) exit 1 ;;
    *) exit 1 ;;
  esac
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
    # Wait briefly then check
    sleep 1
    if ps -p "$pid" >/dev/null 2>&1; then
      kill -9 "$pid" 2>/dev/null || true
    fi

    # Record outcome
    local exit_code=137  # SIGKILL
    if [[ -f "$META_FILE" ]]; then
      persist_outcome "$BEADS" "$exit_code" "$OUTCOME_FILE" "$META_FILE"
    fi

    echo "stopped $BEADS (pid=$pid, killed)"
  else
    echo "job $BEADS already not running (pid=$pid)"

    # Record outcome if we have exit info
    if [[ -f "$OUTCOME_FILE" ]]; then
      : # Already has outcome
    elif [[ -f "$META_FILE" ]]; then
      persist_outcome "$BEADS" "1" "$OUTCOME_FILE" "$META_FILE"  # Unknown exit
    fi
  fi
}

health_cmd() {
  parse_common_args "$@"
  local stall_seconds=$((STALL_MINUTES * 60))

  # Guardrail: warn about multi-log-dir ambiguity
  check_log_dir_ambiguity "health"

  if [[ "$SHOW_OVERRIDES" == "true" ]]; then
    printf "%-14s %-8s %-12s %-16s %-6s %-10s %s\n" \
      "bead" "pid" "health" "last_update" "retry" "override" "outcome"
  else
    printf "%-14s %-8s %-12s %-16s %-6s %s\n" \
      "bead" "pid" "health" "last_update" "retry" "outcome"
  fi

  if [[ -n "$BEADS" ]]; then
    health_line "$BEADS" "$stall_seconds"
    show_log_locality_hint
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
    suggest_alternative_log_dirs
    show_enhanced_locality_hint  # Show remote log hints when local is empty
  else
    show_log_locality_hint
  fi
}

health_line() {
  local beads="$1"
  local stall_threshold="$2"
  job_paths "$beads"
  local pid="" health="missing" last_update="-" retries="0" outcome="-" override=""

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
    # Check for per-bead override flags (V3.2)
    local no_auto_restart blocked
    no_auto_restart="$(meta_get "$META_FILE" "no_auto_restart")"
    blocked="$(meta_get "$META_FILE" "blocked")"
    if [[ "$no_auto_restart" == "true" ]]; then
      override="no-restart"
    elif [[ "$blocked" == "true" ]]; then
      override="blocked"
    fi
  fi

  # Check outcome
  if [[ -f "$OUTCOME_FILE" ]]; then
    local outcome_state outcome_exit outcome_duration
    outcome_state="$(meta_get "$OUTCOME_FILE" "state")"
    outcome_exit="$(meta_get "$OUTCOME_FILE" "exit_code")"
    outcome_duration="$(meta_get "$OUTCOME_FILE" "duration_sec")"
    outcome="${outcome_state:-?}:${outcome_exit:-?}"
    # Add duration if available and job is done
    if [[ -n "$outcome_duration" && "$outcome_duration" != "-" && "$outcome_duration" != "-"* ]]; then
      outcome="${outcome} (${outcome_duration}s)"
    fi
  fi

  local output
  if [[ "$SHOW_OVERRIDES" == "true" ]]; then
    output="$(printf "%-14s %-8s %-12s %-16s %-6s %-10s %s" \
      "$beads" "${pid:--}" "$health" "$last_update" "$retries" "$override" "$outcome")"
  else
    output="$(printf "%-14s %-8s %-12s %-16s %-6s %s" \
      "$beads" "${pid:--}" "$health" "$last_update" "$retries" "$outcome")"
  fi

  if [[ "$NO_ANSI" == "true" ]]; then
    echo "$output" | strip_ansi
  else
    echo "$output"
  fi
}

restart_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "restart requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  if [[ ! -f "$META_FILE" ]]; then
    echo "no metadata file for $BEADS: $META_FILE" >&2
    exit 1
  fi

  # Verify contract if requested
  if [[ "$PRESERVE_CONTRACT" == "true" ]] && [[ -f "$CONTRACT_FILE" ]]; then
    if ! verify_contract "$CONTRACT_FILE"; then
      echo "ERROR: Contract verification failed for $BEADS" >&2
      echo "  Current env differs from saved contract in: $CONTRACT_FILE" >&2
      echo "  Aborting restart to prevent inconsistent execution." >&2
      exit 1
    fi
  fi

  # Get current metadata
  local retries prompt_file repo worktree meta_use_pty effective_use_pty
  retries="$(meta_get "$META_FILE" "retries")"
  retries="${retries:-0}"
  prompt_file="$(meta_get "$META_FILE" "prompt_file")"
  repo="$(meta_get "$META_FILE" "repo")"
  worktree="$(meta_get "$META_FILE" "worktree")"
  meta_use_pty="$(meta_get "$META_FILE" "use_pty")"
  effective_use_pty="$USE_PTY"

  # Preserve previous mode unless caller explicitly passes --pty
  if [[ "$effective_use_pty" != "true" && "$meta_use_pty" == "true" ]]; then
    effective_use_pty="true"
  fi

  # Auto PTY fallback if previous attempt had zero output
  if [[ "$effective_use_pty" != "true" && -f "$LOG_FILE" ]]; then
    local log_bytes
    log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    if [[ "$log_bytes" -eq 0 ]]; then
      effective_use_pty="true"
      echo "note: auto-enabling PTY due to zero output on previous attempt"
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

  # Rotate log (preserves history)
  rotate_log "$LOG_FILE"

  # Rotate outcome (preserves forensic history)
  rotate_outcome "$OUTCOME_FILE"

  # Increment retries
  local new_retries=$((retries + 1))
  meta_set "$META_FILE" "retries" "$new_retries"
  meta_set "$META_FILE" "restarted_at" "$(now_utc)"
  meta_set "$META_FILE" "launch_marker_at" "$(now_utc)"
  meta_set "$META_FILE" "launch_state" "restarting"

  # Start new job
  [[ -x "$HEADLESS" ]] || { echo "headless wrapper not executable: $HEADLESS" >&2; exit 1; }
  local exec_mode="nohup"  # Default; overridden below if PTY mode
  if [[ "$effective_use_pty" == "true" ]]; then
    [[ -x "$PTY_RUN" ]] || { echo "PTY wrapper not executable: $PTY_RUN" >&2; exit 1; }
    # PTY handles output via --output; shell redirect is for pty-run's own stderr only
    nohup "$PTY_RUN" --output "$LOG_FILE" -- "$HEADLESS" --prompt-file "$prompt_file" 2>> "$LOG_FILE" &
    exec_mode="pty"
  else
    nohup "$HEADLESS" --prompt-file "$prompt_file" >> "$LOG_FILE" 2>&1 &
    exec_mode="nohup"
  fi
  local new_pid=$!
  echo "$new_pid" > "$PID_FILE"
  meta_set "$META_FILE" "pid" "$new_pid"
  meta_set "$META_FILE" "launch_state" "running"
  meta_set "$META_FILE" "execution_mode" "$exec_mode"
  meta_set "$META_FILE" "use_pty" "$effective_use_pty"
  persist_contract "$BEADS" "$CONTRACT_FILE"

  echo "restarted beads=$BEADS pid=$new_pid retries=$new_retries log=$LOG_FILE pty=$effective_use_pty"
}

tail_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "tail requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "no log file for $BEADS: $LOG_FILE" >&2
    # Help operator find logs on remote hosts
    echo "hint: if job was dispatched to a remote VM, check:" >&2
    echo "  macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh tail --beads $BEADS'" >&2
    echo "  epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh tail --beads $BEADS'" >&2
    suggest_alternative_log_dirs
    exit 1
  fi

  # Check for empty log file - might indicate remote execution
  local log_bytes
  log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
  if [[ "$log_bytes" -eq 0 ]]; then
    echo "(log file exists but is empty: $LOG_FILE)"
    echo "hint: empty log may indicate job not yet started or output redirected elsewhere"
    echo "hint: if job was dispatched to a remote VM, check logs there:"
    echo "  macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh tail --beads $BEADS'"
    echo "  epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh tail --beads $BEADS'"
    return 0
  fi

  if [[ "$NO_ANSI" == "true" ]]; then
    tail -n "$TAIL_LINES" "$LOG_FILE" | strip_ansi
  else
    tail -n "$TAIL_LINES" "$LOG_FILE"
  fi
}

set_override_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "set-override requires --beads" >&2; exit 2; }
  job_paths "$BEADS"

  if [[ ! -f "$META_FILE" ]]; then
    echo "no metadata file for $BEADS: $META_FILE" >&2
    echo "hint: job must be started first before setting overrides" >&2
    exit 1
  fi

  local current_value
  current_value="$(meta_get "$META_FILE" "no_auto_restart")"
  current_value="${current_value:-false}"

  # If no value specified, just show current state
  if [[ -z "$OVERRIDE_NO_AUTO_RESTART" ]]; then
    echo "override for $BEADS:"
    echo "  no_auto_restart=$current_value"
    return 0
  fi

  # Validate the value
  if [[ "$OVERRIDE_NO_AUTO_RESTART" != "true" && "$OVERRIDE_NO_AUTO_RESTART" != "false" ]]; then
    echo "invalid value for --no-auto-restart: $OVERRIDE_NO_AUTO_RESTART" >&2
    echo "valid values: true, false" >&2
    exit 2
  fi

  # Set the new value
  meta_set "$META_FILE" "no_auto_restart" "$OVERRIDE_NO_AUTO_RESTART"
  meta_set "$META_FILE" "override_set_at" "$(now_utc)"

  echo "override updated for $BEADS:"
  echo "  no_auto_restart: $current_value -> $OVERRIDE_NO_AUTO_RESTART"
  echo ""
  echo " watchdog will now:"
  if [[ "$OVERRIDE_NO_AUTO_RESTART" == "true" ]]; then
    echo "  - mark as blocked instead of restarting when stalled"
  else
    echo "  - restart normally when stalled (subject to max-retries)"
  fi
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

  local mode_desc="normal"
  if [[ "$WATCHDOG_OBSERVE_ONLY" == "true" ]]; then
    mode_desc="observe-only"
  fi

  echo "watchdog started: mode=$mode_desc interval=${WATCHDOG_INTERVAL}s stall=${STALL_MINUTES}m max-retries=${WATCHDOG_MAX_RETRIES} once=${WATCHDOG_ONCE} beads=${BEADS:-all}"
  echo "press Ctrl+C to stop"
  show_log_locality_hint

  # Guardrail: warn about multi-log-dir ambiguity
  check_log_dir_ambiguity "watchdog"

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

      # Check for per-bead no-auto-restart flag
      local bead_no_restart="false"
      if [[ -f "$META_FILE" ]]; then
        bead_no_restart="$(meta_get "$META_FILE" "no_auto_restart")"
        bead_no_restart="${bead_no_restart:-false}"
      fi

      local health
      health="$(job_health "$beads" "$stall_seconds")"
      echo "[$beads] health=$health"

      case "$health" in
        healthy|starting|exited_ok)
          # Nothing to do
          ;;
        exited_err)
          echo "[$beads] exited with error - check logs"
          ;;
        stalled)
          # Check observe-only mode
          if [[ "$WATCHDOG_OBSERVE_ONLY" == "true" ]]; then
            echo "[$beads] OBSERVE-ONLY: would restart but observing only"
            continue
          fi

          # Check global or per-bead no-auto-restart
          if [[ "$WATCHDOG_NO_AUTO_RESTART" == "true" || "$bead_no_restart" == "true" ]]; then
            echo "[$beads] NO-AUTO-RESTART: stalled but restart disabled"
            meta_set "$META_FILE" "blocked" "true"
            meta_set "$META_FILE" "blocked_at" "$(now_utc)"
            meta_set "$META_FILE" "blocked_reason" "no_auto_restart"
            continue
          fi

          # Check retry count
          local retries
          retries="$(meta_get "$META_FILE" "retries")"
          retries="${retries:-0}"
          echo "[$beads] stalled, retries=$retries/$WATCHDOG_MAX_RETRIES"

          if [[ "$retries" -ge "$WATCHDOG_MAX_RETRIES" ]]; then
            # Mark as blocked
            meta_set "$META_FILE" "blocked" "true"
            meta_set "$META_FILE" "blocked_at" "$(now_utc)"
            meta_set "$META_FILE" "blocked_reason" "max_retries"
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
      suggest_alternative_log_dirs
      # Show remote hints on first iteration when empty
      if [[ $iteration -eq 1 ]]; then
        show_enhanced_locality_hint
      fi
    fi

    if [[ "$WATCHDOG_ONCE" == "true" ]]; then
      echo "watchdog completed single iteration (--once)"
      break
    fi

    sleep "$WATCHDOG_INTERVAL"
  done
}

# V3.3: Preflight command - verify job prerequisites
preflight_cmd() {
  parse_common_args "$@"
  preflight_check "$BEADS"
}

# V3.3: Mutations command - show worktree changes
mutations_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "mutations requires --beads" >&2; exit 2; }

  job_paths "$BEADS"

  if [[ ! -f "$META_FILE" ]]; then
    echo "no metadata file for $BEADS" >&2
    exit 1
  fi

  local worktree
  worktree="$(meta_get "$META_FILE" "worktree")"

  if [[ -z "$worktree" || ! -d "$worktree" ]]; then
    echo "no worktree configured for $BEADS"
    exit 0
  fi

  echo "=== Mutations for $BEADS ==="
  echo "worktree: $worktree"
  echo ""

  local mutation_count
  mutation_count="$(check_mutations "$BEADS")"

  echo "mutation_count: $mutation_count"

  if [[ "$mutation_count" -gt 0 ]]; then
    echo ""
    echo "Changed files:"
    if [[ -d "$worktree/.git" ]]; then
      (cd "$worktree" && git status --porcelain 2>/dev/null | head -50)
      local total
      total="$(cd "$worktree" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$total" -gt 50 ]]; then
        echo "... ($((total - 50)) more files)"
      fi
    else
      find "$worktree" -type f -newer "$META_FILE" 2>/dev/null | head -50
    fi
  fi

  # Write mutation marker
  write_mutation_marker "$BEADS" "$mutation_count"
}

case "$CMD" in
  start) start_cmd "$@" ;;
  status) status_cmd "$@" ;;
  check) check_cmd "$@" ;;
  health) health_cmd "$@" ;;
  restart) restart_cmd "$@" ;;
  stop) stop_cmd "$@" ;;
  tail) tail_cmd "$@" ;;
  set-override) set_override_cmd "$@" ;;
  preflight) preflight_cmd "$@" ;;
  mutations) mutations_cmd "$@" ;;
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
