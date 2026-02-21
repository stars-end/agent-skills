#!/usr/bin/env bash
set -euo pipefail

# cc-glm-job.sh (V3.4 - Deterministic Substates + Integrity Gates)
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
#   status       [--beads <id>] [--log-dir <dir>] [--no-ansi] [--mutations] [--json]
#   check        --beads <id> [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi] [--json]
#   health       [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi] [--json]
#   restart      --beads <id> [--log-dir <dir>] [--pty] [--preserve-contract]
#   stop         --beads <id> [--log-dir <dir>]
#   tail         --beads <id> [--log-dir <dir>] [--lines <n>] [--no-ansi]
#   set-override --beads <id> [--no-auto-restart <true|false>] [--log-dir <dir>]
#   preflight    [--beads <id>] [--log-dir <dir>]  (V3.3)
#   mutations    --beads <id> [--log-dir <dir>]    (V3.3)
#   baseline-gate [--beads <id> | --worktree <path>] --required-baseline <sha> [--json]
#   integrity-gate [--beads <id> | --worktree <path>] --reported-commit <sha> [--branch <name>] [--json]
#   feature-key-gate [--beads <id> | --worktree <path>] --feature-key <bd-id> [--branch <name>] [--base-branch <name>] [--json]
#   watchdog     [--beads <id>] [--log-dir <dir>] [--interval <secs>] [--stall-minutes <n>] [--max-retries <n>]
#                [--once] [--observe-only] [--no-auto-restart] [--pidfile <path>]
#
# V3.4 Changes:
#   - Deterministic substates: launching, waiting_first_output, silent_mutation, stalled
#   - Machine-readable JSON output for status/check/health/preflight/gates (--json)
#   - Pre-dispatch runtime baseline gate command (baseline-gate)
#   - Post-wave report integrity gate command (integrity-gate)
#   - Feature-Key governance gate command (feature-key-gate)
#   - Start-time baseline enforcement via CC_GLM_REQUIRED_BASELINE
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
CC_GLM_JOB_VERSION="3.4.0"

LOG_DIR="/tmp/cc-glm-jobs"
CMD="${1:-}"
shift || true

usage() {
  cat <<'EOF'
cc-glm-job.sh (V3.4 - Deterministic Substates + Integrity Gates)

Usage:
  cc-glm-job.sh start --beads <id> --prompt-file <path> [options]
  cc-glm-job.sh status [--beads <id>] [--log-dir <dir>] [--no-ansi] [--mutations] [--json]
  cc-glm-job.sh check --beads <id> [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi] [--json]
  cc-glm-job.sh health [--beads <id>] [--log-dir <dir>] [--stall-minutes <n>] [--no-ansi] [--json]
  cc-glm-job.sh restart --beads <id> [--log-dir <dir>] [--pty] [--preserve-contract]
  cc-glm-job.sh stop --beads <id> [--log-dir <dir>]
  cc-glm-job.sh tail --beads <id> [--log-dir <dir>] [--lines <n>] [--no-ansi]
  cc-glm-job.sh set-override --beads <id> [--no-auto-restart <true|false>]
  cc-glm-job.sh preflight [--beads <id>] [--log-dir <dir>]
  cc-glm-job.sh mutations --beads <id> [--log-dir <dir>]
  cc-glm-job.sh baseline-gate [--beads <id> | --worktree <path>] --required-baseline <sha> [--json]
  cc-glm-job.sh integrity-gate [--beads <id> | --worktree <path>] --reported-commit <sha> [--branch <name>] [--json]
  cc-glm-job.sh feature-key-gate [--beads <id> | --worktree <path>] --feature-key <bd-id> [--branch <name>] [--base-branch <name>] [--json]
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
  baseline-gate Verify runtime commit meets minimum required baseline.
  integrity-gate Verify reported commit exists and is ancestor of branch head.
  feature-key-gate Verify commits include task-specific Feature-Key trailer.
  watchdog     Run watchdog loop: monitor jobs, restart stalled jobs.

Options:
  --pty               Use PTY-backed execution for reliable output capture.
  --no-ansi           Strip ANSI codes from output.
  --mutations         Show mutation count in status output (V3.3).
  --json              Emit machine-readable JSON output.
  --observe-only      Watchdog monitors but never restarts (observe-only mode).
  --no-auto-restart   Disable auto-restart for specific beads in watchdog.
  --preserve-contract On restart, abort if env contract cannot be preserved.
  --required-baseline Required commit SHA for baseline gate.
  --reported-commit   Commit reported by wave/agent for integrity check.
  --feature-key       Expected Feature-Key trailer value (e.g., bd-xga8.2.2).
  --branch            Branch name for integrity check (defaults to HEAD branch).
  --base-branch       Base branch for Feature-Key commit range (default: master).
  --once              Run exactly one watchdog iteration, then exit.
  --lines N           Number of lines for tail command (default: 20).

V3.4 Features:
  - Deterministic launch substates (no ambiguous running/empty state)
  - JSON output mode for automation loops
  - Baseline and integrity gate commands
  - Start command can enforce baseline via CC_GLM_REQUIRED_BASELINE

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

Health States (V3.4):
  launching    - Process started, awaiting first output, within startup window
  waiting_first_output - No output yet, but process/mutation evidence indicates progress
  silent_mutation - Worktree changed despite empty log output
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

# Basic JSON escaper for machine-readable output.
json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

join_by() {
  local delim="$1"
  shift || true
  local out="" first=true
  local item
  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      out="$item"
      first=false
    else
      out="${out}${delim}${item}"
    fi
  done
  printf '%s' "$out"
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

resolve_worktree() {
  local beads="$1"
  local from_flag="${2:-}"
  local resolved="$from_flag"
  if [[ -z "$resolved" && -n "$beads" ]]; then
    job_paths "$beads"
    resolved="$(meta_get "$META_FILE" "worktree" 2>/dev/null || true)"
  fi
  if [[ -z "$resolved" ]]; then
    resolved="$(pwd)"
  fi
  printf '%s' "$resolved"
}

# V8: Target identity validation for stop/check/restart
# Ensures current directory or --worktree flag matches job's recorded worktree.
# Prevents mis-targeting when multiple worktrees share the same beads ID.
ensure_target_identity() {
  local beads="$1"
  local cmd="$2"
  local provided_worktree="${3:-}"

  job_paths "$beads"
  if [[ ! -f "$META_FILE" ]]; then
    return 0  # No job metadata yet, nothing to validate against
  fi

  local meta_worktree
  meta_worktree="$(meta_get "$META_FILE" "worktree" 2>/dev/null || true)"

  # If job was started with no worktree, we can't validate identity.
  [[ -n "$meta_worktree" ]] || return 0

  local canonical_meta
  canonical_meta="$(cd "$meta_worktree" 2>/dev/null && pwd -P || echo "$meta_worktree")"

  local target
  if [[ -n "$provided_worktree" ]]; then
    target="$(cd "$provided_worktree" 2>/dev/null && pwd -P || echo "$provided_worktree")"
  else
    target="$(pwd -P)"
  fi

  # Exact match or subdirectory (for convenience when running from within worktree)
  if [[ "$target" != "$canonical_meta" && "$target" != "$canonical_meta"/* ]]; then
    echo "ERROR: Target identity mismatch for job $beads ($cmd)" >&2
    echo "  Job worktree:    $canonical_meta" >&2
    echo "  Target worktree: $target" >&2
    echo "  Aborting to prevent side effects on unintended worktree." >&2
    echo "  Hint: cd to the correct worktree or use --worktree <path>" >&2
    exit 1
  fi
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
        # P1 fix: Add 30s timeout to op read (bd-5wys.26)
        if timeout 30 op read "$ZAI_API_KEY" >/dev/null 2>&1; then
          auth_ok=true
        else
          echo "AUTH_PROBE_TIMEOUT"
          echo "  ERROR: op read timed out or failed for ZAI_API_KEY"
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
      # P1 fix: Add 30s timeout to op read (bd-5wys.26)
      if timeout 30 op read "$CC_GLM_OP_URI" >/dev/null 2>&1; then
        auth_ok=true
      else
        echo "AUTH_PROBE_TIMEOUT"
        echo "  ERROR: op read timed out or failed for CC_GLM_OP_URI"
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
      # P1 fix: Add 30s timeout to op read (bd-5wys.26)
      if timeout 30 op read "op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY" >/dev/null 2>&1; then
        auth_ok=true
      else
        echo "AUTH_PROBE_TIMEOUT"
        echo "  ERROR: No auth source configured and default op:// resolution timed out or failed"
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

baseline_gate_eval() {
  local worktree="$1"
  local required="$2"

  local runtime_commit=""
  local passed=false
  local reason_code="unknown"
  local details=""

  if [[ -z "$required" ]]; then
    reason_code="required_baseline_missing"
    details="required baseline is empty"
  elif [[ ! -d "$worktree" ]]; then
    reason_code="worktree_missing"
    details="worktree not found: $worktree"
  elif ! git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
    reason_code="not_a_git_repo"
    details="not a git worktree: $worktree"
  else
    runtime_commit="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
    if [[ -z "$runtime_commit" ]]; then
      reason_code="runtime_commit_missing"
      details="failed to resolve runtime HEAD commit"
    elif ! git -C "$worktree" cat-file -e "${required}^{commit}" >/dev/null 2>&1; then
      reason_code="required_commit_missing"
      details="required commit not found in repo"
    elif git -C "$worktree" merge-base --is-ancestor "$required" "$runtime_commit" >/dev/null 2>&1; then
      passed=true
      reason_code="baseline_ok"
      details="runtime commit meets required baseline"
    else
      reason_code="baseline_not_met"
      details="runtime commit is behind required baseline"
    fi
  fi

  printf '%s|%s|%s|%s|%s\n' "$passed" "$reason_code" "$runtime_commit" "$required" "$details"
}

integrity_gate_eval() {
  local worktree="$1"
  local reported_commit="$2"
  local branch_name="${3:-}"

  local passed=false
  local reason_code="unknown"
  local details=""
  local branch_head=""

  if [[ -z "$reported_commit" ]]; then
    reason_code="reported_commit_missing"
    details="reported commit not provided"
  elif [[ ! -d "$worktree" ]]; then
    reason_code="worktree_missing"
    details="worktree not found: $worktree"
  elif ! git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
    reason_code="not_a_git_repo"
    details="not a git worktree: $worktree"
  else
    if [[ -z "$branch_name" ]]; then
      branch_name="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
    if [[ -z "$branch_name" ]]; then
      reason_code="branch_missing"
      details="could not resolve branch name"
    elif ! branch_head="$(git -C "$worktree" rev-parse "$branch_name" 2>/dev/null)"; then
      reason_code="branch_head_missing"
      details="branch not found: $branch_name"
      branch_head=""
    elif ! git -C "$worktree" cat-file -e "${reported_commit}^{commit}" >/dev/null 2>&1; then
      reason_code="reported_commit_not_found"
      details="reported commit does not exist"
    elif git -C "$worktree" merge-base --is-ancestor "$reported_commit" "$branch_head" >/dev/null 2>&1; then
      passed=true
      reason_code="integrity_ok"
      details="reported commit is ancestor of branch head"
    else
      reason_code="reported_not_ancestor"
      details="reported commit is not ancestor of branch head"
    fi
  fi

  printf '%s|%s|%s|%s|%s|%s\n' "$passed" "$reason_code" "$branch_name" "$branch_head" "$reported_commit" "$details"
}

feature_key_gate_eval() {
  local worktree="$1"
  local feature_key="$2"
  local branch_name="${3:-}"
  local base_branch="${4:-master}"

  local passed=false
  local reason_code="unknown"
  local details=""
  local checked_commits=0
  local missing_commits=0

  if [[ -z "$feature_key" ]]; then
    reason_code="feature_key_missing"
    details="feature key is required"
  elif [[ ! -d "$worktree" ]]; then
    reason_code="worktree_missing"
    details="worktree not found: $worktree"
  elif ! git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
    reason_code="not_a_git_repo"
    details="not a git worktree: $worktree"
  else
    if [[ -z "$branch_name" ]]; then
      branch_name="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
    if [[ -z "$branch_name" ]]; then
      reason_code="branch_missing"
      details="could not resolve branch name"
    elif ! git -C "$worktree" rev-parse "$branch_name" >/dev/null 2>&1; then
      reason_code="branch_head_missing"
      details="branch not found: $branch_name"
    elif ! git -C "$worktree" rev-parse "$base_branch" >/dev/null 2>&1; then
      reason_code="base_branch_missing"
      details="base branch not found: $base_branch"
    else
      local commit
      while IFS= read -r commit; do
        [[ -n "$commit" ]] || continue
        checked_commits=$((checked_commits + 1))
        local body
        body="$(git -C "$worktree" show -s --format=%B "$commit" 2>/dev/null || true)"
        if ! printf '%s\n' "$body" | grep -q "^Feature-Key: ${feature_key}$"; then
          missing_commits=$((missing_commits + 1))
        fi
      done < <(git -C "$worktree" rev-list "${base_branch}..${branch_name}" 2>/dev/null || true)

      if [[ "$checked_commits" -eq 0 ]]; then
        reason_code="no_commits_in_range"
        details="no commits in range ${base_branch}..${branch_name}"
      elif [[ "$missing_commits" -eq 0 ]]; then
        passed=true
        reason_code="feature_key_ok"
        details="all ${checked_commits} commits include Feature-Key: ${feature_key}"
      else
        reason_code="feature_key_missing_in_commits"
        details="${missing_commits}/${checked_commits} commits missing Feature-Key: ${feature_key}"
      fi
    fi
  fi

  printf '%s|%s|%s|%s|%s|%s|%s\n' "$passed" "$reason_code" "$branch_name" "$base_branch" "$feature_key" "$checked_commits" "$details"
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
  OUTPUT_JSON=false
  REQUIRED_BASELINE=""
  REPORTED_COMMIT=""
  BRANCH_NAME=""
  FEATURE_KEY=""
  BASE_BRANCH="${CC_GLM_BASE_BRANCH:-master}"

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
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --required-baseline)
        REQUIRED_BASELINE="${2:-}"
        shift 2
        ;;
      --reported-commit)
        REPORTED_COMMIT="${2:-}"
        shift 2
        ;;
      --branch)
        BRANCH_NAME="${2:-}"
        shift 2
        ;;
      --feature-key)
        FEATURE_KEY="${2:-}"
        shift 2
        ;;
      --base-branch)
        BASE_BRANCH="${2:-}"
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

  # Optional pre-dispatch runtime baseline gate (P0).
  if [[ -n "${CC_GLM_REQUIRED_BASELINE:-}" ]]; then
    local gate_worktree gate_result gate_pass gate_reason gate_runtime gate_required gate_details
    gate_worktree="$(resolve_worktree "$BEADS" "$WORKTREE")"
    gate_result="$(baseline_gate_eval "$gate_worktree" "$CC_GLM_REQUIRED_BASELINE")"
    IFS='|' read -r gate_pass gate_reason gate_runtime gate_required gate_details <<< "$gate_result"
    if [[ "$gate_pass" != "true" ]]; then
      echo "baseline gate failed: reason=$gate_reason required=$gate_required runtime=${gate_runtime:--} worktree=$gate_worktree" >&2
      echo "details: $gate_details" >&2
      exit 1
    fi
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
  local pid="" state="missing" reason="-" log_bytes="0" last_update="-" retries="0" elapsed="-" outcome="-" duration="-" override="" mutations="-"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  local detail
  detail="$(job_health_detail "$beads" "$((STALL_MINUTES * 60))")"
  IFS='|' read -r state reason mutations log_bytes _cpu _pid_age _log_age <<< "$detail"

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
  if [[ "$SHOW_MUTATIONS" == "true" && "$mutations" == "-" ]]; then
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

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"beads":"%s",' "$(json_escape "$beads")"
    printf '"pid":"%s",' "$(json_escape "${pid:--}")"
    printf '"state":"%s",' "$(json_escape "$state")"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"elapsed":"%s",' "$(json_escape "$elapsed")"
    printf '"log_bytes":%s,' "${log_bytes:-0}"
    printf '"last_update":"%s",' "$(json_escape "$last_update")"
    printf '"retry_count":%s,' "${retries:-0}"
    printf '"mutation_count":%s,' "${mutations:-0}"
    printf '"override":"%s",' "$(json_escape "$override")"
    printf '"outcome":"%s"' "$(json_escape "$outcome")"
    printf '}\n'
    return 0
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

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local rows=()
    if [[ -n "$BEADS" ]]; then
      rows+=("$(status_line "$BEADS")")
    else
      shopt -s nullglob
      local pidf beads
      for pidf in "$LOG_DIR"/*.pid; do
        beads="$(basename "$pidf" .pid)"
        rows+=("$(status_line "$beads")")
      done
    fi
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"log_dir":"%s",' "$(json_escape "$LOG_DIR")"
    printf '"jobs":[%s]' "$(join_by "," "${rows[@]}")"
    printf '}\n'
    return 0
  fi

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

# V3.4: Deterministic health detail classification with explicit reason codes.
# Output format:
#   state|reason_code|mutation_count|log_bytes|cpu_time|pid_age_seconds|log_age_seconds
job_health_detail() {
  local beads="$1"
  job_paths "$beads"
  local stall_threshold="${2:-$((STALL_MINUTES * 60))}"

  local state="missing"
  local reason_code="pid_file_missing"
  local mutation_count=0
  local log_bytes=0
  local cpu_time=0
  local pid_age=0
  local log_age=0

  if [[ ! -f "$PID_FILE" ]]; then
    printf "%s|%s|%s|%s|%s|%s|%s\n" "$state" "$reason_code" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    printf "missing|pid_empty|0|0|0|0|0\n"
    return 0
  fi

  if [[ -f "$PID_FILE" ]]; then
    local pid_mtime now
    pid_mtime="$(file_mtime_epoch "$PID_FILE" 2>/dev/null || echo "")"
    now="$(date +%s)"
    if [[ -n "$pid_mtime" ]]; then
      pid_age=$((now - pid_mtime))
    fi
  fi

  if [[ -f "$META_FILE" ]]; then
    mutation_count="$(check_mutations "$beads")"
    write_mutation_marker "$beads" "$mutation_count"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    log_bytes="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    local log_mtime now
    log_mtime="$(file_mtime_epoch "$LOG_FILE" 2>/dev/null || echo "")"
    now="$(date +%s)"
    if [[ -n "$log_mtime" ]]; then
      log_age=$((now - log_mtime))
    fi
  fi

  if ! ps -p "$pid" >/dev/null 2>&1; then
    if [[ -f "$OUTCOME_FILE" ]]; then
      local exit_code
      exit_code="$(meta_get "$OUTCOME_FILE" "exit_code")"
      exit_code="${exit_code:-1}"
      if [[ "$exit_code" -eq 0 ]]; then
        printf "exited_ok|outcome_exit_0|%s|%s|0|%s|%s\n" "$mutation_count" "$log_bytes" "$pid_age" "$log_age"
      else
        printf "exited_err|outcome_exit_nonzero|%s|%s|0|%s|%s\n" "$mutation_count" "$log_bytes" "$pid_age" "$log_age"
      fi
      return 0
    fi
    if [[ "$log_bytes" -eq 0 ]]; then
      printf "stalled|process_exited_no_output|%s|%s|0|%s|%s\n" "$mutation_count" "$log_bytes" "$pid_age" "$log_age"
      return 0
    fi
    printf "exited_err|process_exited_without_outcome|%s|%s|0|%s|%s\n" "$mutation_count" "$log_bytes" "$pid_age" "$log_age"
    return 0
  fi

  if [[ -f "$META_FILE" ]]; then
    local blocked
    blocked="$(meta_get "$META_FILE" "blocked")"
    if [[ "$blocked" == "true" ]]; then
      printf "blocked|blocked_flag_set|%s|%s|0|%s|%s\n" "$mutation_count" "$log_bytes" "$pid_age" "$log_age"
      return 0
    fi
  fi

  cpu_time="$(process_cpu_time "$pid")"

  if [[ "$log_bytes" -eq 0 ]]; then
    if [[ "$mutation_count" -gt 0 ]]; then
      printf "silent_mutation|worktree_changed_no_output|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
      return 0
    fi
    if [[ "$cpu_time" -gt 0 ]]; then
      if [[ "$pid_age" -gt "$stall_threshold" ]]; then
        printf "waiting_first_output|cpu_progress_no_output_past_threshold|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
      else
        printf "launching|cpu_progress_no_output|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
      fi
      return 0
    fi
    if [[ "$pid_age" -gt "$stall_threshold" ]]; then
      printf "stalled|no_output_no_progress_after_threshold|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
    else
      printf "launching|no_output_within_grace|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
    fi
    return 0
  fi

  if [[ -f "$META_FILE" ]]; then
    local prev_cpu
    prev_cpu="$(meta_get "$META_FILE" "last_cpu_time")"
    prev_cpu="${prev_cpu:-0}"
    meta_set "$META_FILE" "last_cpu_time" "$cpu_time"
    if [[ "$cpu_time" -gt "$prev_cpu" ]]; then
      printf "healthy|cpu_progress|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
      return 0
    fi
  fi

  if [[ "$log_age" -gt "$stall_threshold" ]]; then
    printf "stalled|stale_log_and_no_cpu_progress|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
    return 0
  fi

  printf "healthy|recent_log_activity|%s|%s|%s|%s|%s\n" "$mutation_count" "$log_bytes" "$cpu_time" "$pid_age" "$log_age"
}

job_health() {
  local beads="$1"
  local stall_threshold="${2:-$((STALL_MINUTES * 60))}"
  local detail
  detail="$(job_health_detail "$beads" "$stall_threshold")"
  printf "%s" "${detail%%|*}"
}

check_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "check requires --beads" >&2; exit 2; }
  job_paths "$BEADS"
  ensure_target_identity "$BEADS" "check" "$WORKTREE"

  if [[ ! -f "$META_FILE" ]]; then
    echo "job $BEADS has no metadata file"
    # Help operator find job on remote hosts
    echo "hint: if job was dispatched to a remote VM, check:" >&2
    echo "  macmini: tailscale ssh fengning@macmini 'cc-glm-job.sh check --beads $BEADS'" >&2
    echo "  epyc6:   tailscale ssh feng@epyc6 'cc-glm-job.sh check --beads $BEADS'" >&2
    suggest_alternative_log_dirs
    exit 1
  fi

  local detail health reason mutation_count log_bytes cpu_time pid_age log_age
  detail="$(job_health_detail "$BEADS" "$((STALL_MINUTES * 60))")"
  IFS='|' read -r health reason mutation_count log_bytes cpu_time pid_age log_age <<< "$detail"

  local output
  case "$health" in
    healthy)
      output="job $BEADS healthy: running with progress"
      ;;
    starting|launching)
      output="job $BEADS launching: waiting for first output"
      ;;
    waiting_first_output)
      output="job $BEADS waiting_first_output: process active but no output yet"
      ;;
    silent_mutation)
      output="job $BEADS silent_mutation: worktree changed while log is empty (inspect mutations)"
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

  output="$output reason=$reason mutation_count=$mutation_count log_bytes=$log_bytes cpu_time=${cpu_time}s"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"beads":"%s",' "$(json_escape "$BEADS")"
    printf '"health":"%s",' "$(json_escape "$health")"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"stall_threshold_seconds":%s,' "$((STALL_MINUTES * 60))"
    printf '"mutation_count":%s,' "${mutation_count:-0}"
    printf '"log_bytes":%s,' "${log_bytes:-0}"
    printf '"cpu_time_seconds":%s,' "${cpu_time:-0}"
    printf '"pid_age_seconds":%s,' "${pid_age:-0}"
    printf '"log_age_seconds":%s' "${log_age:-0}"
    printf '}\n'
  else
  if [[ "$NO_ANSI" == "true" ]]; then
    echo "$output" | strip_ansi
  else
    echo "$output"
  fi
  fi

  # Exit codes for scripting
  case "$health" in
    healthy|starting|launching|waiting_first_output|silent_mutation|exited_ok) exit 0 ;;
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
  ensure_target_identity "$BEADS" "stop" "$WORKTREE"

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

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local rows=()
    if [[ -n "$BEADS" ]]; then
      rows+=("$(health_line "$BEADS" "$stall_seconds")")
    else
      shopt -s nullglob
      local pidf beads
      for pidf in "$LOG_DIR"/*.pid; do
        beads="$(basename "$pidf" .pid)"
        rows+=("$(health_line "$beads" "$stall_seconds")")
      done
    fi
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"log_dir":"%s",' "$(json_escape "$LOG_DIR")"
    printf '"stall_threshold_seconds":%s,' "$stall_seconds"
    printf '"jobs":[%s]' "$(join_by "," "${rows[@]}")"
    printf '}\n'
    return 0
  fi

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
  local pid="" health="missing" reason="-" last_update="-" retries="0" outcome="-" override="" mutation_count="0" log_bytes="0" cpu_time="0" pid_age="0" log_age="0"

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  local detail
  detail="$(job_health_detail "$beads" "$stall_threshold")"
  IFS='|' read -r health reason mutation_count log_bytes cpu_time pid_age log_age <<< "$detail"

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

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"beads":"%s",' "$(json_escape "$beads")"
    printf '"pid":"%s",' "$(json_escape "${pid:--}")"
    printf '"health":"%s",' "$(json_escape "$health")"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"last_update":"%s",' "$(json_escape "$last_update")"
    printf '"retry_count":%s,' "${retries:-0}"
    printf '"mutation_count":%s,' "${mutation_count:-0}"
    printf '"log_bytes":%s,' "${log_bytes:-0}"
    printf '"cpu_time_seconds":%s,' "${cpu_time:-0}"
    printf '"pid_age_seconds":%s,' "${pid_age:-0}"
    printf '"log_age_seconds":%s,' "${log_age:-0}"
    printf '"override":"%s",' "$(json_escape "$override")"
    printf '"outcome":"%s"' "$(json_escape "$outcome")"
    printf '}\n'
    return 0
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
  ensure_target_identity "$BEADS" "restart" "$WORKTREE"

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
  ensure_target_identity "$BEADS" "tail" "$WORKTREE"

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
  ensure_target_identity "$BEADS" "set-override" "$WORKTREE"

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
        healthy|starting|launching|waiting_first_output|exited_ok)
          # Nothing to do
          ;;
        silent_mutation)
          echo "[$beads] SILENT_MUTATION: worktree changed with no output; inspect via 'cc-glm-job.sh mutations --beads $beads'"
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
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local out rc
    out="$(preflight_check "$BEADS" 2>&1)" || rc=$?
    rc="${rc:-0}"
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"beads":"%s",' "$(json_escape "$BEADS")"
    printf '"passed":%s,' "$([[ "$rc" -eq 0 ]] && echo true || echo false)"
    printf '"exit_code":%s,' "$rc"
    printf '"output":"%s"' "$(json_escape "$out")"
    printf '}\n'
    return "$rc"
  fi
  preflight_check "$BEADS"
}

# V3.3: Mutations command - show worktree changes
mutations_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] || { echo "mutations requires --beads" >&2; exit 2; }

  job_paths "$BEADS"
  ensure_target_identity "$BEADS" "mutations" "$WORKTREE"

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

baseline_gate_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] && ensure_target_identity "$BEADS" "baseline-gate" "$WORKTREE"
  [[ -n "$REQUIRED_BASELINE" ]] || { echo "baseline-gate requires --required-baseline" >&2; exit 2; }

  local worktree
  worktree="$(resolve_worktree "$BEADS" "$WORKTREE")"

  local result pass reason runtime required details
  result="$(baseline_gate_eval "$worktree" "$REQUIRED_BASELINE")"
  IFS='|' read -r pass reason runtime required details <<< "$result"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"worktree":"%s",' "$(json_escape "$worktree")"
    printf '"required_baseline":"%s",' "$(json_escape "$required")"
    printf '"runtime_commit":"%s",' "$(json_escape "$runtime")"
    printf '"passed":%s,' "$([[ "$pass" == "true" ]] && echo true || echo false)"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"details":"%s"' "$(json_escape "$details")"
    printf '}\n'
  else
    if [[ "$pass" == "true" ]]; then
      echo "baseline gate passed: runtime=$runtime required=$required worktree=$worktree"
    else
      echo "baseline gate failed: reason=$reason runtime=${runtime:--} required=$required worktree=$worktree"
      echo "details: $details"
    fi
  fi

  if [[ "$pass" == "true" ]]; then
    return 0
  fi
  return 4
}

integrity_gate_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] && ensure_target_identity "$BEADS" "integrity-gate" "$WORKTREE"
  [[ -n "$REPORTED_COMMIT" ]] || { echo "integrity-gate requires --reported-commit" >&2; exit 2; }

  local worktree
  worktree="$(resolve_worktree "$BEADS" "$WORKTREE")"

  local result pass reason branch_name branch_head reported details
  result="$(integrity_gate_eval "$worktree" "$REPORTED_COMMIT" "$BRANCH_NAME")"
  IFS='|' read -r pass reason branch_name branch_head reported details <<< "$result"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"worktree":"%s",' "$(json_escape "$worktree")"
    printf '"branch":"%s",' "$(json_escape "$branch_name")"
    printf '"branch_head":"%s",' "$(json_escape "$branch_head")"
    printf '"reported_commit":"%s",' "$(json_escape "$reported")"
    printf '"passed":%s,' "$([[ "$pass" == "true" ]] && echo true || echo false)"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"details":"%s"' "$(json_escape "$details")"
    printf '}\n'
  else
    if [[ "$pass" == "true" ]]; then
      echo "integrity gate passed: reported=$reported branch=$branch_name head=$branch_head"
    else
      echo "integrity gate failed: reason=$reason reported=$reported branch=$branch_name head=${branch_head:--}"
      echo "details: $details"
    fi
  fi

  if [[ "$pass" == "true" ]]; then
    return 0
  fi
  return 4
}

feature_key_gate_cmd() {
  parse_common_args "$@"
  [[ -n "$BEADS" ]] && ensure_target_identity "$BEADS" "feature-key-gate" "$WORKTREE"
  [[ -n "$FEATURE_KEY" ]] || { echo "feature-key-gate requires --feature-key" >&2; exit 2; }

  local worktree
  worktree="$(resolve_worktree "$BEADS" "$WORKTREE")"

  local result pass reason branch_name base_branch feature_key checked_commits details
  result="$(feature_key_gate_eval "$worktree" "$FEATURE_KEY" "$BRANCH_NAME" "$BASE_BRANCH")"
  IFS='|' read -r pass reason branch_name base_branch feature_key checked_commits details <<< "$result"

  if [[ "$OUTPUT_JSON" == "true" ]]; then
    printf '{'
    printf '"generated_at":"%s",' "$(json_escape "$(now_utc)")"
    printf '"worktree":"%s",' "$(json_escape "$worktree")"
    printf '"branch":"%s",' "$(json_escape "$branch_name")"
    printf '"base_branch":"%s",' "$(json_escape "$base_branch")"
    printf '"feature_key":"%s",' "$(json_escape "$feature_key")"
    printf '"checked_commits":%s,' "${checked_commits:-0}"
    printf '"passed":%s,' "$([[ "$pass" == "true" ]] && echo true || echo false)"
    printf '"reason_code":"%s",' "$(json_escape "$reason")"
    printf '"details":"%s"' "$(json_escape "$details")"
    printf '}\n'
  else
    if [[ "$pass" == "true" ]]; then
      echo "feature-key gate passed: feature_key=$feature_key branch=$branch_name base=$base_branch commits=$checked_commits"
    else
      echo "feature-key gate failed: reason=$reason feature_key=$feature_key branch=$branch_name base=$base_branch"
      echo "details: $details"
    fi
  fi

  if [[ "$pass" == "true" ]]; then
    return 0
  fi
  return 4
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
  baseline-gate) baseline_gate_cmd "$@" ;;
  integrity-gate) integrity_gate_cmd "$@" ;;
  feature-key-gate) feature_key_gate_cmd "$@" ;;
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
