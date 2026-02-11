#!/usr/bin/env bash
set -euo pipefail

# cc-glm-wave.sh
#
# Dependency-aware wave planner for cc-glm headless delegation.
#
# Organizes tasks into waves based on depends_on relationships and enforces
# max parallelism (default: 4 workers). Provides partial rerun support for
# failed tasks.
#
# Usage:
#   cc-glm-wave.sh plan --manifest /path/to/manifest.toml
#   cc-glm-wave.sh status --manifest /path/to/manifest.toml
#   cc-glm-wave.sh run --manifest /path/to/manifest.toml [--wave N]
#   cc-glm-wave.sh rerun --manifest /path/to/manifest.toml --task <id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_HELPER="${SCRIPT_DIR}/cc-glm-job.sh"

LOG_DIR="/tmp/cc-glm-jobs"
DEFAULT_MAX_WORKERS=4
CMD="${1:-}"
shift || true

usage() {
  cat <<'EOF'
cc-glm-wave.sh

Dependency-aware wave planner for cc-glm headless delegation.

Task Manifest (TOML format):
  [[tasks]]
  id = "bd-001"
  repo = "agent-skills"
  worktree = "/tmp/agents/bd-001/agent-skills"
  prompt_file = "/tmp/cc-glm-jobs/bd-001.prompt.txt"
  depends_on = []  # empty if no dependencies

  [[tasks]]
  id = "bd-002"
  repo = "agent-skills"
  worktree = "/tmp/agents/bd-002/agent-skills"
  prompt_file = "/tmp/cc-glm-jobs/bd-002.prompt.txt"
  depends_on = ["bd-001"]  # waits for bd-001 to complete

  [[tasks]]
  id = "bd-003"
  repo = "agent-skills"
  worktree = "/tmp/agents/bd-003/agent-skills"
  prompt_file = "/tmp/cc-glm-jobs/bd-003.prompt.txt"
  depends_on = ["bd-001", "bd-002"]  # waits for both

Commands:
  plan    --manifest <path> [--max-workers N] [--out-dir <dir>]
           Generate wave plan and write wave-*.txt files.

  status  --manifest <path> [--log-dir <dir>]
           Show wave and task status table.

  run     --manifest <path> [--wave N] [--max-workers N] [--log-dir <dir>]
           Execute a wave (or all waves sequentially if --wave omitted).

  rerun   --manifest <path> --task <id> [--log-dir <dir>]
           Re-run a specific failed task (mark as pending and run).

  clean   --manifest <path> [--log-dir <dir>]
           Clean up wave artifacts for a manifest.

  selftest
           Run parser and wave planning validation tests.

Wave Dispatch Algorithm:
  1. Topologically sort tasks by depends_on edges.
  2. Partition into waves: each wave contains tasks with all deps satisfied.
  3. Within each wave, run up to max_workers tasks in parallel.
  4. A wave is "complete" when all its tasks exit (success or failure).
  5. Next wave starts only after all tasks in current wave complete.

Partial Rerun Semantics:
  - Failed tasks are marked with state=failed in metadata.
  - "rerun" clears failed state and re-executes just that task.
  - Dependent waves are not re-run unless their specific deps failed.

Notes:
  - Max parallelism is per-wave, not global.
  - Default max_workers is 4 (configurable via --max-workers or env var).
  - Wave state files: /tmp/cc-glm-jobs/<manifest-basename>-wave-<N>.state
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

# Simple TOML parser (bash-only, minimal subset needed)
# Outputs: id|repo|worktree|prompt_file|depends_on (comma-separated)
parse_toml_tasks() {
  local manifest="$1"
  local in_tasks=0
  local id="" repo="" worktree="" prompt_file="" depends_on=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Track [[tasks]] sections
    if [[ "$line" =~ ^\[\[tasks\]\] ]]; then
      # Emit previous task if exists
      if [[ -n "$id" ]]; then
        printf "%s|%s|%s|%s|%s\n" "$id" "$repo" "$worktree" "$prompt_file" "$depends_on"
      fi
      in_tasks=1
      id="" repo="" worktree="" prompt_file="" depends_on=""
      continue
    fi

    [[ "$in_tasks" -eq 0 ]] && continue

    # Parse key-value pairs (simple strings and arrays)
    if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      case "$key" in
        id)
          # Handle quoted string
          [[ "$value" =~ ^\"([^\"]*)\" ]] && id="${BASH_REMATCH[1]}"
          ;;
        repo)
          [[ "$value" =~ ^\"([^\"]*)\" ]] && repo="${BASH_REMATCH[1]}"
          ;;
        worktree)
          [[ "$value" =~ ^\"([^\"]*)\" ]] && worktree="${BASH_REMATCH[1]}"
          ;;
        prompt_file)
          [[ "$value" =~ ^\"([^\"]*)\" ]] && prompt_file="${BASH_REMATCH[1]}"
          ;;
        depends_on)
          # Handle array like ["a", "b"] -> a,b (comma-separated)
          # Strip leading whitespace, brackets, quotes, and remaining spaces.
          # For empty [], produce empty string.
          depends_on="$(echo "$value" | sed 's/^[[:space:]]*//;s/^\[//;s/\]$//;s/"//g;s/ //g')"
          ;;
      esac
    fi
  done < "$manifest"

  # Emit last task
  if [[ -n "$id" ]]; then
    printf "%s|%s|%s|%s|%s\n" "$id" "$repo" "$worktree" "$prompt_file" "$depends_on"
  fi
}

# Topological sort with cycle detection (Kahn's algorithm)
# Output: sorted task ids (one per line)
# Uses pseudo-associative arrays via variable indirection for bash 3.2 compatibility:
#   _TS_deps_<id> = comma-separated dependency list
#   _TS_indegree_<id> = integer indegree count
#   _TS_visited_<id> = "1" if visited
# Uses indexed arrays for task processing: _TS_tasks, _TS_queue, _TS_result
topo_sort() {
  # Clear globals from previous runs
  # Unset all _TS_* variables to avoid stale state
  eval "$(set | grep -E '^_TS_(deps|indegree|visited)_' | sed 's/=.*//' | xargs -I {} echo unset {})" 2>/dev/null || true

  declare -a _TS_tasks=()

  # Build adjacency and indegree maps using variable indirection
  while IFS='|' read -r id repo worktree prompt_file depends_on; do
    [[ -z "$id" ]] && continue
    _TS_tasks+=("$id")

    # Clean id for use as variable name (replace hyphens with underscores)
    local clean_id="${id//-/_}"

    # Initialize indegree to 0, increment for each dep
    local indegree_val=0
    if [[ -n "$depends_on" ]]; then
      IFS=',' read -ra deps_arr <<< "$depends_on"
      for dep in "${deps_arr[@]}"; do
        [[ -z "$dep" ]] && continue
        # Append to deps list
        local current_deps=""
        local varname="_TS_deps_${clean_id}"
        eval "current_deps=\"\${${varname}-}\""
        eval "${varname}=\"\${current_deps}${dep},\""
        ((indegree_val++)) || true
      done
    fi
    # Set indegree
    eval "_TS_indegree_${clean_id}=${indegree_val}"
  done

  # Kahn's algorithm
  declare -a _TS_queue=() _TS_result=()

  # Start with tasks having no dependencies
  for id in "${_TS_tasks[@]}"; do
    local clean_id="${id//-/_}"
    local indeg_var="_TS_indegree_${clean_id}"
    local indeg=""
    eval "indeg=\"\${${indeg_var}-0}\""
    [[ -z "$indeg" ]] && indeg=0
    if [[ "$indeg" -eq 0 ]]; then
      _TS_queue+=("$id")
      eval "_TS_visited_${clean_id}=1"
    fi
  done

  while [[ ${#_TS_queue[@]} -gt 0 ]]; do
    local id="${_TS_queue[0]}"
    _TS_queue=("${_TS_queue[@]:1}")
    _TS_result+=("$id")

    # Decrease indegree for dependents
    for other in "${_TS_tasks[@]}"; do
      local clean_other="${other//-/_}"
      local deps_var="_TS_deps_${clean_other}"
      local dep_list=""
      eval "dep_list=\"\${${deps_var}-}\""
      [[ -z "$dep_list" ]] && continue

      if [[ "$dep_list" == *"${id},"* ]]; then
        local indeg_var="_TS_indegree_${clean_other}"
        local curr=""
        eval "curr=\"\${${indeg_var}-0}\""
        [[ -z "$curr" ]] && curr=0
        eval "${indeg_var}=$((curr - 1))"

        # Check if indegree is now 0 and not yet visited
        local new_indeg=""
        eval "new_indeg=\"\${${indeg_var}-0}\""
        [[ -z "$new_indeg" ]] && new_indeg=0

        local visited_var="_TS_visited_${clean_other}"
        local visited=""
        eval "visited=\"\${${visited_var}-}\""

        if [[ "$new_indeg" -eq 0 && -z "$visited" ]]; then
          _TS_queue+=("$other")
          eval "${visited_var}=1"
        fi
      fi
    done
  done

  # Check for cycles
  if [[ ${#_TS_result[@]} -ne ${#_TS_tasks[@]} ]]; then
    echo "Error: circular dependency detected in tasks" >&2
    return 1
  fi

  printf "%s\n" "${_TS_result[@]}"
}

# Generate wave plan from manifest
plan_cmd() {
  local manifest=""
  local max_workers="${CC_GLM_MAX_WORKERS:-$DEFAULT_MAX_WORKERS}"
  local out_dir="$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)
        manifest="${2:-}"
        shift 2
        ;;
      --max-workers)
        max_workers="${2:-}"
        shift 2
        ;;
      --out-dir)
        out_dir="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "plan requires --manifest" >&2; exit 2; }
  [[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 1; }

  mkdir -p "$out_dir"

  local manifest_base
  manifest_base="$(basename "$manifest" .toml)"

  # Parse and sort tasks (topo_sort may fail on circular deps)
  local -a sorted_tasks=()
  local topo_output
  local topo_result=0
  topo_output="$(parse_toml_tasks "$manifest" | topo_sort)" || topo_result=$?
  if [[ $topo_result -ne 0 ]]; then
    echo "Error: failed to plan waves - check dependencies" >&2
    exit 1
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] && sorted_tasks+=("$id")
  done <<< "$topo_output"

  # Build waves: group tasks where all deps are in previous waves
  local -a waves=()
  # Use pseudo-associative arrays via variable indirection for bash 3.2 compatibility
  # _PLAN_wave_map_<clean_id> = wave number
  # _PLAN_task_deps_<clean_id> = comma-separated dependency list
  local wave_num=0

  # Build lookup for task deps and wave planning
  while IFS='|' read -r id repo worktree prompt_file depends_on; do
    [[ -z "$id" ]] && continue
    local clean_id="${id//-/_}"
    eval "_PLAN_task_deps_${clean_id}=\"${depends_on}\""
  done < <(parse_toml_tasks "$manifest")

  for id in "${sorted_tasks[@]}"; do
    local clean_id="${id//-/_}"
    local deps_var="_PLAN_task_deps_${clean_id}"
    local deps=""
    eval "deps=\"\${${deps_var}-}\""

    local max_dep_wave=-1

    if [[ -n "$deps" ]]; then
      IFS=',' read -ra deps_arr <<< "$deps"
      for dep in "${deps_arr[@]}"; do
        [[ -z "$dep" ]] && continue
        local clean_dep="${dep//-/_}"
        local dep_wave_var="_PLAN_wave_map_${clean_dep}"
        local dep_wave=""
        eval "dep_wave=\"\${${dep_wave_var}--1}\""
        [[ "$dep_wave" -gt "$max_dep_wave" ]] && max_dep_wave="$dep_wave"
      done
    fi

    local target_wave=$((max_dep_wave + 1))
    eval "_PLAN_wave_map_${clean_id}=${target_wave}"

    # Extend waves array if needed
    while [[ ${#waves[@]} -le "$target_wave" ]]; do
      waves+=("")
    done

    # Append task to wave (with pipe-delimited full task data)
    while IFS='|' read -r full_id repo worktree prompt_file _ignored_deps; do
      if [[ "$full_id" == "$id" ]]; then
        waves[$target_wave]="${waves[$target_wave]}${full_id}|${repo}|${worktree}|${prompt_file}\n"
        break
      fi
    done < <(parse_toml_tasks "$manifest")
  done

  # Clean up globals
  eval "$(set | grep -E '^_PLAN_(wave_map|task_deps)_' | sed 's/=.*//' | xargs -I {} echo unset {})" 2>/dev/null || true

  # Write wave files
  echo "# Wave plan for $manifest"
  echo "# Generated: $(now_utc)"
  echo "# Max workers per wave: $max_workers"
  echo ""

  local wave_idx=0
  for wave_tasks in "${waves[@]}"; do
    [[ -z "$wave_tasks" ]] && continue

    local wave_file="$out_dir/${manifest_base}-wave-${wave_idx}.txt"
    local state_file="$out_dir/${manifest_base}-wave-${wave_idx}.state"

    {
      echo "# Wave $wave_idx tasks"
      echo "$wave_tasks"
    } > "$wave_file"

    # Initialize state file
    cat > "$state_file" <<EOF
manifest=$manifest
wave=$wave_idx
max_workers=$max_workers
started_at=
completed_at=
state=pending
tasks=$(echo "$wave_tasks" | grep -c '^[^#]' || echo 0)
pending=$(echo "$wave_tasks" | grep -c '^[^#]' || echo 0)
running=0
completed=0
failed=0
EOF

    # Count tasks and show summary
    local task_count
    task_count="$(echo "$wave_tasks" | grep -c '^[^#]' || echo 0)"

    echo "Wave $wave_idx: $task_count task(s)"
    echo "  Plan: $wave_file"
    echo "  State: $state_file"

    # Show task list
    while IFS='|' read -r id repo worktree prompt_file; do
      [[ -z "$id" ]] && continue
      echo "    - $id (repo=$repo)"
    done <<< "$wave_tasks"

    echo ""
    ((wave_idx++)) || true
  done

  echo "Total waves: $wave_idx"
  echo "To run all waves: cc-glm-wave.sh run --manifest $manifest"
}

# Get state value from wave state file
wave_state_get() {
  local state_file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1==key {gsub(/^ +| +$/, "", $2); print $2; exit}' "$state_file" 2>/dev/null || echo ""
}

# Set state value in wave state file
wave_state_set() {
  local state_file="$1"
  local key="$2"
  local val="$3"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$state_file" ]]; then
    awk -F= -v key="$key" '$1!=key {print $0}' "$state_file" > "$tmp"
  fi
  printf "%s=%s\n" "$key" "$val" >> "$tmp"
  mv "$tmp" "$state_file"
}

# Update wave state by polling task states
update_wave_state() {
  local state_file="$1"
  local log_dir="$2"

  local wave
  wave="$(wave_state_get "$state_file" "wave")"

  # Read wave plan to get task list
  local manifest
  manifest="$(wave_state_get "$state_file" "manifest")"
  local manifest_base
  manifest_base="$(basename "$manifest" .toml)"
  local wave_plan="${log_dir}/${manifest_base}-wave-${wave}.txt"

  local pending=0 running=0 completed=0 failed=0

  while IFS='|' read -r id repo worktree prompt_file; do
    [[ -z "$id" || "$id" =~ ^# ]] && continue

    local pid_file="${log_dir}/${id}.pid"
    local meta_file="${log_dir}/${id}.meta"

    if [[ ! -f "$pid_file" ]]; then
      ((pending++)) || true
      continue
    fi

    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"

    if ps -p "$pid" >/dev/null 2>&1; then
      ((running++)) || true
    else
      # Check meta for completion status
      if [[ -f "$meta_file" ]]; then
        local exit_code
        exit_code="$(awk -F= '$1=="exit_code" {print $2; exit}' "$meta_file" 2>/dev/null || echo "")"
        if [[ "$exit_code" == "0" ]]; then
          ((completed++)) || true
        else
          ((failed++)) || true
        fi
      else
        ((completed++)) || true  # Assume completed if no meta
      fi
    fi
  done < "$wave_plan"

  wave_state_set "$state_file" "pending" "$pending"
  wave_state_set "$state_file" "running" "$running"
  wave_state_set "$state_file" "completed" "$completed"
  wave_state_set "$state_file" "failed" "$failed"

  # Determine overall wave state
  local total=$((pending + running + completed + failed))
  local started_at
  started_at="$(wave_state_get "$state_file" "started_at")"

  if [[ -z "$started_at" && "$running" -gt 0 ]]; then
    wave_state_set "$state_file" "started_at" "$(now_utc)"
  fi

  if [[ "$running" -eq 0 && "$pending" -eq 0 ]]; then
    wave_state_set "$state_file" "completed_at" "$(now_utc)"
    if [[ "$failed" -gt 0 ]]; then
      wave_state_set "$state_file" "state" "failed"
    else
      wave_state_set "$state_file" "state" "completed"
    fi
  elif [[ "$running" -gt 0 ]]; then
    wave_state_set "$state_file" "state" "running"
  fi
}

status_cmd() {
  local manifest=""
  local log_dir="$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)
        manifest="${2:-}"
        shift 2
        ;;
      --log-dir)
        log_dir="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "status requires --manifest" >&2; exit 2; }
  [[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 1; }

  local manifest_base
  manifest_base="$(basename "$manifest" .toml)"

  printf "%-10s %-14s %-12s %-8s %-8s %-8s %-8s %-12s\n" \
    "wave" "state" "started" "pending" "running" "completed" "failed" "elapsed"
  echo "--------------------------------------------------------------------------------------------------------"

  shopt -s nullglob
  local found=0
  for state_file in "$log_dir"/${manifest_base}-wave-*.state; do
    [[ -f "$state_file" ]] || continue
    found=1

    update_wave_state "$state_file" "$log_dir"

    local wave state started_at completed_at pending running completed failed
    wave="$(wave_state_get "$state_file" "wave")"
    state="$(wave_state_get "$state_file" "state")"
    started_at="$(wave_state_get "$state_file" "started_at")"
    pending="$(wave_state_get "$state_file" "pending")"
    running="$(wave_state_get "$state_file" "running")"
    completed="$(wave_state_get "$state_file" "completed")"
    failed="$(wave_state_get "$state_file" "failed")"

    local elapsed="-"
    if [[ -n "$started_at" ]]; then
      local start_epoch now
      start_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || date -d "$started_at" "+%s" 2>/dev/null || echo "0")"
      now="$(date +%s)"
      elapsed="$(format_elapsed "$((now - start_epoch))")"
    fi

    local short_started="${started_at:--}"
    [[ "$short_started" != "-" ]] && short_started="${started_at:11:8}"  # Show HH:MM:SS only

    printf "%-10s %-14s %-12s %-8s %-8s %-8s %-8s %-12s\n" \
      "$state" "$wave" "$short_started" "$pending" "$running" "$completed" "$failed" "$elapsed"
  done

  if [[ "$found" -eq 0 ]]; then
    echo "(no wave state files found - run 'plan' first)"
  fi

  # Also show individual task status if any
  if "$JOB_HELPER" status --log-dir "$log_dir" 2>/dev/null | grep -q "bead"; then
    echo ""
    echo "Individual task status:"
    "$JOB_HELPER" status --log-dir "$log_dir"
  fi
}

run_cmd() {
  local manifest=""
  local target_wave=""
  local max_workers="${CC_GLM_MAX_WORKERS:-$DEFAULT_MAX_WORKERS}"
  local log_dir="$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)
        manifest="${2:-}"
        shift 2
        ;;
      --wave)
        target_wave="${2:-}"
        shift 2
        ;;
      --max-workers)
        max_workers="${2:-}"
        shift 2
        ;;
      --log-dir)
        log_dir="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "run requires --manifest" >&2; exit 2; }
  [[ -f "$manifest" ]] || { echo "manifest not found: $manifest" >&2; exit 1; }

  local manifest_base
  manifest_base="$(basename "$manifest" .toml)"

  # Find wave files
  shopt -s nullglob
  local -a wave_files=("$log_dir"/${manifest_base}-wave-*.txt)
  [[ ${#wave_files[@]} -eq 0 ]] && {
    echo "No wave plan files found - run 'plan' first" >&2
    exit 1
  }

  # Sort waves by number
  IFS=$'\n' wave_files=($(sort <<<"${wave_files[*]}"))
  unset IFS

  for wave_file in "${wave_files[@]}"; do
    local wave_num
    wave_num="$(basename "$wave_file" .txt)"
    wave_num="${wave_num##*-}"

    # Skip if targeting specific wave
    if [[ -n "$target_wave" && "$wave_num" != "$target_wave" ]]; then
      continue
    fi

    local state_file="${wave_file%.txt}.state"

    # Check if already completed
    local state
    state="$(wave_state_get "$state_file" "state")"

    if [[ "$state" == "completed" ]]; then
      echo "Wave $wave_num: already completed, skipping"
      continue
    fi

    echo "=== Executing Wave $wave_num ==="

    # Read tasks from wave file
    local -a task_pids=()
    local running_count=0

    while IFS='|' read -r id repo worktree prompt_file; do
      [[ -z "$id" || "$id" =~ ^# ]] && continue

      # Check if task already done
      local pid_file="${log_dir}/${id}.pid"
      local meta_file="${log_dir}/${id}.meta"

      if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid="$(cat "$pid_file" 2>/dev/null || true)"
        if ! ps -p "$existing_pid" >/dev/null 2>&1; then
          local exit_code
          exit_code="$(wave_state_get "$meta_file" "exit_code" 2>/dev/null || echo "")"
          if [[ "$exit_code" == "0" ]]; then
            echo "  [$id] already completed"
            continue
          fi
        fi
      fi

      # Wait for worker slot
      while [[ "$running_count" -ge "$max_workers" ]]; do
        sleep 2
        running_count=0
        for check_pid in "${task_pids[@]}"; do
          ps -p "$check_pid" >/dev/null 2>&1 && ((running_count++)) || true
        done
      done

      # Start task
      echo "  [$id] starting (repo=$repo, worktree=$worktree)"
      "$JOB_HELPER" start \
        --beads "$id" \
        --repo "$repo" \
        --worktree "$worktree" \
        --prompt-file "$prompt_file" \
        --log-dir "$log_dir" >/dev/null

      local new_pid
      new_pid="$(cat "${pid_file}" 2>/dev/null || echo "")"
      task_pids+=("$new_pid")
      ((running_count++)) || true

      # Small delay to avoid thundering herd
      sleep 1
    done < "$wave_file"

    # Wait for all tasks in this wave to complete
    echo "  Waiting for ${#task_pids[@]} task(s) to complete..."
    for pid in "${task_pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done

    # Update wave state
    update_wave_state "$state_file" "$log_dir"

    local final_state final_completed final_failed
    final_state="$(wave_state_get "$state_file" "state")"
    final_completed="$(wave_state_get "$state_file" "completed")"
    final_failed="$(wave_state_get "$state_file" "failed")"

    echo "  Wave $wave_num complete: state=$final_state, completed=$final_completed, failed=$final_failed"

    # Stop if wave failed (don't run subsequent waves)
    if [[ "$final_failed" -gt 0 ]]; then
      echo "  Wave $wave_num had failures - stopping subsequent waves"
      echo "  Use 'rerun' to re-run failed tasks, then 'run' to continue"
      exit 1
    fi

    # Stop if we only wanted to run one wave
    [[ -n "$target_wave" ]] && break

    echo ""
  done
}

rerun_cmd() {
  local manifest=""
  local task_id=""
  local log_dir="$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)
        manifest="${2:-}"
        shift 2
        ;;
      --task)
        task_id="${2:-}"
        shift 2
        ;;
      --log-dir)
        log_dir="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "rerun requires --manifest" >&2; exit 2; }
  [[ -n "$task_id" ]] || { echo "rerun requires --task" >&2; exit 2; }

  # Find the task in the manifest
  local found_id="" repo="" worktree="" prompt_file=""

  while IFS='|' read -r id r w p; do
    if [[ "$id" == "$task_id" ]]; then
      found_id="$id"
      repo="$r"
      worktree="$w"
      prompt_file="$p"
      break
    fi
  done < <(parse_toml_tasks "$manifest")

  [[ -n "$found_id" ]] || { echo "task not found in manifest: $task_id" >&2; exit 1; }

  echo "Re-running task: $task_id"

  # Clean up old artifacts
  local pid_file="${log_dir}/${task_id}.pid"
  local meta_file="${log_dir}/${task_id}.meta"
  local log_file="${log_dir}/${task_id}.log"

  # Stop if running
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if ps -p "$pid" >/dev/null 2>&1; then
      "$JOB_HELPER" stop --beads "$task_id" --log-dir "$log_dir" >/dev/null || true
    fi
  fi

  # Archive old log
  if [[ -f "$log_file" ]]; then
    mv "$log_file" "${log_file}.old.$(date +%s)"
  fi

  # Restart with fresh state
  "$JOB_HELPER" start \
    --beads "$task_id" \
    --repo "$repo" \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --log-dir "$log_dir"

  echo "Task $task_id restarted. Monitor with:"
  echo "  cc-glm-wave.sh status --manifest $manifest"
}

clean_cmd() {
  local manifest=""
  local log_dir="$LOG_DIR"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest)
        manifest="${2:-}"
        shift 2
        ;;
      --log-dir)
        log_dir="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
  done

  [[ -n "$manifest" ]] || { echo "clean requires --manifest" >&2; exit 2; }

  local manifest_base
  manifest_base="$(basename "$manifest" .toml)"

  shopt -s nullglob
  local count=0
  for f in "$log_dir"/${manifest_base}-wave-*.{txt,state}; do
    [[ -f "$f" ]] || continue
    rm -f "$f"
    ((count++)) || true
  done

  echo "Cleaned $count wave artifact(s)"
}

# Self-test: verify parser handles depends_on arrays correctly
selftest_cmd() {
  local test_manifest
  test_manifest="$(mktemp -t cc-glm-test-XXXXXX.toml)"

  cat > "$test_manifest" <<'EOF'
# Test manifest for depends_on array parsing
[[tasks]]
id = "task-a"
repo = "test-repo"
worktree = "/tmp/test-a"
prompt_file = "/tmp/a.prompt"
depends_on = []

[[tasks]]
id = "task-b"
repo = "test-repo"
worktree = "/tmp/test-b"
prompt_file = "/tmp/b.prompt"
depends_on = ["task-a"]

[[tasks]]
id = "task-c"
repo = "test-repo"
worktree = "/tmp/test-c"
prompt_file = "/tmp/c.prompt"
depends_on = ["task-a", "task-b"]

[[tasks]]
id = "task-d"
repo = "test-repo"
worktree = "/tmp/test-d"
prompt_file = "/tmp/d.prompt"
depends_on = ["task-c"]
EOF

  echo "=== Self-Test: Parser and Wave Planning ==="
  echo ""

  # Test parser output
  echo "1. Testing parser output:"
  echo "--------------------------"
  parse_toml_tasks "$test_manifest" | while IFS='|' read -r id repo worktree prompt_file depends_on; do
    echo "  id=$id depends_on=[$depends_on]"
  done
  echo ""

  # Test wave generation
  echo "2. Testing wave plan generation:"
  echo "----------------------------------"
  local out_dir
  out_dir="$(mktemp -d -t cc-glm-wave-test-XXXXXX)"
  plan_cmd --manifest "$test_manifest" --out-dir "$out_dir" 2>&1 | grep -E "^Wave|^Total|^    -" || true

  echo ""
  echo "3. Validation results:"
  echo "-----------------------"

  local passed=0 failed=0

  # Check that task-a is in wave 0 (no deps)
  if grep -q "task-a" "$out_dir/"*"-wave-0.txt" 2>/dev/null; then
    echo "✓ task-a correctly in wave 0 (no deps)"
    ((passed++))
  else
    echo "✗ task-a NOT in wave 0 (expected: no deps)"
    ((failed++))
  fi

  # Check that task-b is in wave 1 (depends on task-a)
  if grep -q "task-b" "$out_dir/"*"-wave-1.txt" 2>/dev/null; then
    echo "✓ task-b correctly in wave 1 (depends_on=[task-a])"
    ((passed++))
  else
    echo "✗ task-b NOT in wave 1 (expected: depends_on=[task-a])"
    ((failed++))
  fi

  # Check that task-c is in wave 2 (depends on task-a and task-b)
  if grep -q "task-c" "$out_dir/"*"-wave-2.txt" 2>/dev/null; then
    echo "✓ task-c correctly in wave 2 (depends_on=[task-a,task-b])"
    ((passed++))
  else
    echo "✗ task-c NOT in wave 2 (expected: depends_on=[task-a,task-b])"
    ((failed++))
  fi

  # Check that task-d is in wave 3 (depends on task-c)
  if grep -q "task-d" "$out_dir/"*"-wave-3.txt" 2>/dev/null; then
    echo "✓ task-d correctly in wave 3 (depends_on=[task-c])"
    ((passed++))
  else
    echo "✗ task-d NOT in wave 3 (expected: depends_on=[task-c])"
    ((failed++))
  fi

  echo ""
  if [[ "$failed" -eq 0 ]]; then
    echo "✓ All $passed tests passed!"
    rm -rf "$test_manifest" "$out_dir"
    return 0
  else
    echo "✗ $failed/$((passed + failed)) tests failed"
    rm -rf "$test_manifest" "$out_dir"
    return 1
  fi
}

case "$CMD" in
  plan) plan_cmd "$@" ;;
  status) status_cmd "$@" ;;
  run) run_cmd "$@" ;;
  rerun) rerun_cmd "$@" ;;
  clean) clean_cmd "$@" ;;
  selftest) selftest_cmd "$@" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage
    exit 2
    ;;
esac
