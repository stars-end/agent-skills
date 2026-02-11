#!/usr/bin/env bash
set -euo pipefail

# cc-glm-telemetry.sh
#
# Summarize effectiveness telemetry for delegated cc-glm batches.
# Scans /tmp/cc-glm-jobs for PID/log/meta artifacts and produces summary stats.
#
# Usage:
#   cc-glm-telemetry.sh [--log-dir <dir>] [--filter <prefix>]
#
# Output includes:
#   - Launched, completed, stalled, restarted, blocked counts
#   - Median completion time
#   - Per-job evidence paths (log/meta)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/cc-glm-jobs"
FILTER=""

usage() {
  cat <<'EOF'
cc-glm-telemetry.sh

Summarize effectiveness telemetry for delegated cc-glm batches.

Usage:
  cc-glm-telemetry.sh [--log-dir <dir>] [--filter <prefix>]

Options:
  --log-dir <dir>   Path to job artifacts (default: /tmp/cc-glm-jobs)
  --filter <prefix> Filter jobs by beads prefix (e.g., "bd-3p27")

Metrics reported:
  - launched:   Total jobs with metadata files
  - completed:  Jobs that exited cleanly (PID exists, process not running)
  - stalled:   Running but no log updates for 20+ minutes
  - restarted: Jobs with retries > 0 in metadata
  - blocked:   Jobs that failed after retry (retries >= 1, not running)
  - median time: Median completion time for completed jobs
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-dir)
        LOG_DIR="${2:-}"
        shift 2
        ;;
      --filter)
        FILTER="${2:-}"
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

file_mtime_epoch() {
  local f="$1"
  if stat -f "%m" "$f" >/dev/null 2>&1; then
    stat -f "%m" "$f"
    return 0
  fi
  stat -c "%Y" "$f"
}

format_duration() {
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

meta_get() {
  local meta="$1"
  local key="$2"
  awk -F= -v key="$key" '$1==key {print substr($0, length(key)+2); exit}' "$meta" 2>/dev/null || true
}

# Calculate median of array of integers
calc_median() {
  local nums=("$@")
  local n=${#nums[@]}
  if [[ $n -eq 0 ]]; then
    echo "-"
    return
  fi

  # Sort numerically
  local sorted=($(printf '%s\n' "${nums[@]}" | sort -n))

  local mid=$((n / 2))
  if [[ $((n % 2)) -eq 1 ]]; then
    echo "${sorted[$mid]}"
  else
    local a="${sorted[$((mid - 1))]}"
    local b="${sorted[$mid]}"
    echo "$(((a + b) / 2))"
  fi
}

# Check if job is stalled (running but no log growth for 20+ minutes)
is_stalled() {
  local log_file="$1"
  local stall_threshold="${2:-1200}"  # 20 minutes in seconds

  if [[ ! -f "$log_file" ]]; then
    return 1
  fi

  local now mtime age
  now="$(date +%s)"
  mtime="$(file_mtime_epoch "$log_file")"
  age=$((now - mtime))

  [[ "$age" -gt "$stall_threshold" ]]
}

# Parse started_at timestamp to epoch
parse_to_epoch() {
  local ts="$1"
  # Parse ISO 8601 timestamp like 2026-02-11T04:16:47Z
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +"%s" >/dev/null 2>&1; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +"%s"
  elif date -d "$ts" +"%s" >/dev/null 2>&1; then
    date -d "$ts" +"%s"
  else
    echo "0"
  fi
}

# Check if job appears blocked (exited after at least one retry)
is_blocked() {
  local meta_file="$1"
  local state="$2"

  if [[ "$state" != "exited" ]]; then
    return 1
  fi

  local retries
  retries="$(meta_get "$meta_file" "retries")"
  retries="${retries:-0}"

  [[ "$retries" -ge 1 ]]
}

main() {
  parse_args "$@"

  if [[ ! -d "$LOG_DIR" ]]; then
    echo "Error: log directory not found: $LOG_DIR" >&2
    exit 1
  fi

  # Trackers
  local launched=0 completed=0 stalled=0 restarted=0 blocked=0
  local completion_times=()

  # Use temp files for portability (associative arrays not available in bash < 4)
  local tmp_states tmp_times tmp_evidences
  tmp_states="$(mktemp)"
  tmp_times="$(mktemp)"
  tmp_evidences="$(mktemp)"

  # Cleanup temp files on exit
  trap "rm -f '$tmp_states' '$tmp_times' '$tmp_evidences' 2>/dev/null || true" EXIT

  # Find all meta files (primary indicator of launched jobs)
  shopt -s nullglob
  local meta_files=()
  for meta in "$LOG_DIR"/*.meta; do
    if [[ -n "$FILTER" ]]; then
      local basename
      basename="$(basename "$meta" .meta)"
      if [[ ! "$basename" =~ ^"$FILTER" ]]; then
        continue
      fi
    fi
    meta_files+=("$meta")
  done

  launched=${#meta_files[@]}

  if [[ $launched -eq 0 ]]; then
    echo "No jobs found in $LOG_DIR"
    exit 0
  fi

  # Header
  echo "=== cc-glm Telemetry Summary ==="
  echo "Log directory: $LOG_DIR"
  if [[ -n "$FILTER" ]]; then
    echo "Filter: $FILTER"
  fi
  echo "Scan time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""

  # Collect metrics per job
  # Use temp files for portability (associative arrays not available in bash < 4)
  local tmp_states
  local tmp_times
  local tmp_evidences
  tmp_states="$(mktemp)"
  tmp_times="$(mktemp)"
  tmp_evidences="$(mktemp)"

  for meta_file in "${meta_files[@]}"; do
    local beads_name
    beads_name="$(basename "$meta_file" .meta)"
    local pid_file="$LOG_DIR/${beads_name}.pid"
    local log_file="$LOG_DIR/${beads_name}.log"

    # Determine job state
    local state
    state="$(job_state "$pid_file")"
    echo "$beads_name|$state" >> "$tmp_states"

    # Evidence path
    echo "$beads_name|log:$log_file meta:$meta_file" >> "$tmp_evidences"

    # Get retries for restarted count
    local retries
    retries="$(meta_get "$meta_file" "retries")"
    retries="${retries:-0}"

    if [[ "$retries" -gt 0 ]]; then
      ((restarted++))
    fi

    local final_state="$state"

    # State-based counts
    case "$state" in
      running)
        if is_stalled "$log_file" 1200; then
          ((stalled++))
          final_state="stalled"
          # Update state in temp file
          sed -i '' "s/^$beads_name|[^|]*$/$beads_name|stalled/" "$tmp_states" 2>/dev/null || \
            sed -i "s/^$beads_name|[^|]*$/$beads_name|stalled/" "$tmp_states" 2>/dev/null || true
        fi
        ;;
      exited)
        ((completed++))

        # Calculate completion time if available
        local started_at
        started_at="$(meta_get "$meta_file" "started_at")"
        if [[ -n "$started_at" ]] && [[ "$started_at" != "0" ]]; then
          local start_epoch end_epoch
          start_epoch="$(parse_to_epoch "$started_at")"
          if [[ -f "$pid_file" ]]; then
            end_epoch="$(file_mtime_epoch "$pid_file")"
            local duration=$((end_epoch - start_epoch))
            if [[ "$duration" -gt 0 ]]; then
              completion_times+=("$duration")
              echo "$beads_name|$duration" >> "$tmp_times"
            fi
          fi
        fi

        # Check for blocked (failed after retry)
        if is_blocked "$meta_file" "$state"; then
          ((blocked++))
          final_state="blocked"
          # Update state in temp file
          sed -i '' "s/^$beads_name|[^|]*$/$beads_name|blocked/" "$tmp_states" 2>/dev/null || \
            sed -i "s/^$beads_name|[^|]*$/$beads_name|blocked/" "$tmp_states" 2>/dev/null || true
        fi
        ;;
    esac
  done

  # Print summary
  echo "--- Summary Metrics ---"
  printf "Launched:   %3d\n" "$launched"
  printf "Completed:  %3d\n" "$completed"
  printf "Stalled:    %3d\n" "$stalled"
  printf "Restarted:  %3d\n" "$restarted"
  printf "Blocked:    %3d\n" "$blocked"

  # Median completion time
  if [[ ${#completion_times[@]} -gt 0 ]]; then
    local median
    median="$(calc_median "${completion_times[@]}")"
    printf "Median time: %s\n" "$(format_duration "$median")"
  else
    printf "Median time: -\n"
  fi

  echo ""
  echo "--- Job Details ---"
  printf "%-20s %-12s %-12s %s\n" "Job" "State" "Duration" "Evidence"
  printf "%-20s %-12s %-12s %s\n" "---" "-----" "--------" "--------"

  # Get sorted list of job names
  local sorted_jobs
  sorted_jobs="$(cut -d'|' -f1 "$tmp_states" 2>/dev/null | sort)"

  # Sort and print job details from temp files
  echo "$sorted_jobs" | while IFS= read -r job_name; do
    # Get state
    local state
    state="$(grep "^${job_name}|" "$tmp_states" 2>/dev/null | cut -d'|' -f2)"
    state="${state:--}"

    # Get duration
    local duration_line duration_sec
    duration_line="$(grep "^${job_name}|" "$tmp_times" 2>/dev/null | cut -d'|' -f2)"
    if [[ -n "$duration_line" ]]; then
      duration="$(format_duration "$duration_line")"
    else
      duration="-"
    fi

    # Get evidence
    local evidence
    evidence="$(grep "^${job_name}|" "$tmp_evidences" 2>/dev/null | cut -d'|' -f2)"
    evidence="${evidence:--}"

    printf "%-20s %-12s %-12s %s\n" "$job_name" "$state" "$duration" "$evidence"
  done
}

main "$@"
