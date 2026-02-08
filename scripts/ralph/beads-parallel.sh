#!/usr/bin/env bash
# Ralph Parallel Execution via Beads Dependencies
# Usage: ./beads-parallel.sh <task-id-1> <task-id-2> ... [--max-parallel N] [--resume <checkpoint-file>] [--close-mode orchestrator|none]
# Bash 3.2 compatible (macOS default)
#
# dx-alpha Protocol:
#   Implementers are READ-ONLY in Beads. The orchestrator (this script) handles closing.
#   --close-mode orchestrator (default): Close Beads issues after task completion
#   --close-mode none: Do not close (planner closes manually)
#
# Examples:
#   ./beads-parallel.sh bd-abc bd-def bd-ghi
#   ./beads-parallel.sh bd-* --max-parallel 4
#   ./beads-parallel.sh bd-* --max-parallel 2 --resume .ralph-checkpoint-epic-123.txt
#   ./beads-parallel.sh bd-* --close-mode none  # Planner closes manually
#
# Environment Variables:
#   KEEP_WORKTREES=1    Keep worktrees after completion (for debugging)
#   MAX_PARALLEL=N      Override default parallel worker count (default: 3)

set -e

# Required: external beads DB
if [[ -z "${BEADS_DIR:-}" ]]; then
  echo "BEADS_DIR is required (external Beads DB)." >&2
  exit 1
fi

# bd binary (allow override)
BD_BIN="${BD_BIN:-bd}"
if [[ "$BD_BIN" == */* ]]; then
  [[ -x "$BD_BIN" ]] || { echo "BD_BIN not executable: $BD_BIN" >&2; exit 1; }
else
  command -v "$BD_BIN" >/dev/null 2>&1 || { echo "bd binary not found: $BD_BIN" >&2; exit 1; }
fi

# Configuration
MAX_PARALLEL=${MAX_PARALLEL:-3}  # Default: 3 parallel workers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
LOG_DIR="$WORKSPACE/.ralph-parallel-logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
  echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"
}

# Create log directory
mkdir -p "$LOG_DIR"

# Parse arguments
TASK_IDS=""
RESUME_MODE=""
CLOSE_MODE="orchestrator"  # dx-alpha default: orchestrator closes Beads issues
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --resume)
      RESUME_MODE="$2"
      shift 2
      ;;
    --close-mode)
      CLOSE_MODE="$2"
      if [[ "$CLOSE_MODE" != "orchestrator" && "$CLOSE_MODE" != "none" ]]; then
        log_error "Invalid --close-mode: $CLOSE_MODE (must be 'orchestrator' or 'none')"
        exit 1
      fi
      shift 2
      ;;
    agent-*|bd-*)
      TASK_IDS="$TASK_IDS $1"
      shift
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Trim leading space
TASK_IDS=$(echo "$TASK_IDS" | sed 's/^ //')

if [ -z "$TASK_IDS" ]; then
  log_error "No task IDs provided. Usage: $0 <task-id-1> <task-id-2> ... [--max-parallel N]"
  exit 1
fi

log "=== Ralph Parallel Execution ==="
if [ -n "$RESUME_MODE" ]; then
  log "Resume mode: loading checkpoint from $RESUME_MODE"
fi
log "Tasks: $TASK_IDS"
log "Max parallel workers: $MAX_PARALLEL"
log "Close mode: $CLOSE_MODE (dx-alpha: implementers read-only)"
log ""

# =============================================================================
# RESUME MODE: Load checkpoint if specified (agent-duf)
# =============================================================================
COMPLETED_TASKS=""
if [ -n "$RESUME_MODE" ]; then
  CHECKPOINT_FILE="$WORKSPACE/$RESUME_MODE"
  if [ -f "$CHECKPOINT_FILE" ]; then
    log "Loading checkpoint from $CHECKPOINT_FILE..."
    COMPLETED_TASKS=$(cat "$CHECKPOINT_FILE" | tr '\n' ' ' | sed 's/ $//')
    log "Previously completed: $COMPLETED_TASKS"
  else
    log_warning "Checkpoint file not found: $CHECKPOINT_FILE"
    log_warning "Starting fresh execution"
  fi
fi

# =============================================================================
# STEP 1: Build dependency graph (stored as temp files for bash 3.2 compatibility)
# =============================================================================

log "Building dependency graph..."

GRAPH_DIR="/tmp/ralph-graph-$$"
mkdir -p "$GRAPH_DIR"

# FIX: Use bd show for each task to get full dependencies array
# bd list --json only returns dependency_count (integer), not IDs
# bd show --json returns full dependencies array with IDs
# Note: bd show returns JSON array [{issue}], so use .[0] wrapper
log "Fetching task data from Beads..."

for task_id in $TASK_IDS; do
  # Get full task data including dependencies
  # Use --allow-stale to bypass stale check when database has sync issues
  task_json=$(BEADS_DIR="$BEADS_DIR" "$BD_BIN" --no-daemon --allow-stale show "$task_id" --json 2>/dev/null)

  if [ -z "$task_json" ]; then
    log_error "Task $task_id not found"
    rm -rf "$GRAPH_DIR"
    exit 1
  fi

  # Extract dependencies from array and save to file
  # bd show returns [{...}], so use .[0].dependencies[].id
  deps=$(echo "$task_json" | jq -r '.[0].dependencies[]?.id' | tr '\n' ' ' | sed 's/ $//')
  echo "$deps" > "$GRAPH_DIR/${task_id}-deps"

  # RESUME MODE: Mark previously completed tasks
  if [[ " $COMPLETED_TASKS " =~ " $task_id " ]]; then
    echo "complete" > "$GRAPH_DIR/${task_id}-status"
    log "  [$task_id] Skipping (completed in previous run)"
  else
    echo "pending" > "$GRAPH_DIR/${task_id}-status"
  fi

  echo "0" > "$GRAPH_DIR/${task_id}-incoming"
done

log "Built graph with $(echo $TASK_IDS | wc -w | tr -d ' ') tasks"
log ""

# =============================================================================
# STEP 2: Compute incoming edge counts
# =============================================================================

log "Computing dependency counts..."

for task_id in $TASK_IDS; do
  deps=$(cat "$GRAPH_DIR/${task_id}-deps")
  if [ -n "$deps" ]; then
    count=$(echo "$deps" | wc -w | tr -d ' ')
  else
    count=0
  fi
  echo "$count" > "$GRAPH_DIR/${task_id}-incoming"
done

# =============================================================================
# STEP 3: Topological sort (Kahn's algorithm) - build execution layers
# =============================================================================

log "Computing execution order (topological sort)..."

# Find tasks with no incoming edges (ready to run)
READY_TASKS=""
for task_id in $TASK_IDS; do
  incoming=$(cat "$GRAPH_DIR/${task_id}-incoming")
  if [ "$incoming" -eq 0 ]; then
    READY_TASKS="$READY_TASKS $task_id"
  fi
done

READY_TASKS=$(echo "$READY_TASKS" | sed 's/^ //')

# Build execution layers
LAYER_NUM=0
PROCESSED_TASKS=""

while [ -n "$READY_TASKS" ]; do
  # Current layer = all currently ready tasks
  echo "$READY_TASKS" > "$GRAPH_DIR/layer-$LAYER_NUM"
  log "  Layer $LAYER_NUM: $READY_TASKS"
  PROCESSED_TASKS="$PROCESSED_TASKS $READY_TASKS"

  # For each task in current layer, reduce incoming count of dependents
  for task_id in $READY_TASKS; do
    for other_id in $TASK_IDS; do
      other_deps=$(cat "$GRAPH_DIR/${other_id}-deps")
      if [[ " $other_deps " =~ " $task_id " ]]; then
        current=$(cat "$GRAPH_DIR/${other_id}-incoming")
        echo $((current - 1)) > "$GRAPH_DIR/${other_id}-incoming"
      fi
    done
  done

  # Find newly ready tasks (incoming=0, not yet processed, not in READY_TASKS)
  NEW_READY=""
  for task_id in $TASK_IDS; do
    incoming=$(cat "$GRAPH_DIR/${task_id}-incoming")
    status=$(cat "$GRAPH_DIR/${task_id}-status")
    if [ "$incoming" -eq 0 ] && [ "$status" = "pending" ]; then
      # Check if not already in processed tasks
      if [[ ! " $PROCESSED_TASKS " =~ " $task_id " ]]; then
        if [[ ! " $READY_TASKS " =~ " $task_id " ]]; then
          NEW_READY="$NEW_READY $task_id"
        fi
      fi
    fi
  done

  READY_TASKS=$(echo "$NEW_READY" | sed 's/^ //')
  ((LAYER_NUM++))
done

# Check for cycles
has_cycle=false
for task_id in $TASK_IDS; do
  incoming=$(cat "$GRAPH_DIR/${task_id}-incoming")
  if [ "$incoming" -gt 0 ]; then
    log_error "Circular dependency detected involving $task_id"
    has_cycle=true
  fi
done

if [ "$has_cycle" = true ]; then
  log_error "Cannot execute with circular dependencies"
  rm -rf "$GRAPH_DIR"
  exit 1
fi

TOTAL_LAYERS=$LAYER_NUM
log "Computed $TOTAL_LAYERS execution layers"
log ""

# =============================================================================
# STEP 4: Execute layers in parallel
# =============================================================================

COMPLETED=0
FAILED=0
START_TIME=$(date +%s)

# =============================================================================
# Helper: Progress reporting (agent-4e4)
# =============================================================================
show_progress() {
  local current=$1
  local total=$2
  local layer=$3

  # Count completed/pending
  local completed_count=0
  local running_count=0
  local pending_count=$total

  for task_id in $TASK_IDS; do
    local status=$(cat "$GRAPH_DIR/${task_id}-status" 2>/dev/null)
    case "$status" in
      complete) ((completed_count++)); ((pending_count--));;
      running) ((running_count++));;
      *) ;;
    esac
  done

  local elapsed=$(( $(date +%s) - START_TIME))
  local elapsed_min=$((elapsed / 60))

  log "[$((layer + 1))/$TOTAL_LAYERS] $completed_count/$total complete, $running_count running, $pending_count pending (${elapsed_min}m elapsed)"
}

# =============================================================================
# Helper: Retry logic with max attempts (agent-amm)
# =============================================================================
MAX_ATTEMPTS=3

run_single_task() {
  local task_id="$1"
  local layer_num="$2"
  local worker_num="$3"

  local log_file="$LOG_DIR/${task_id}-layer${layer_num}-worker${worker_num}.log"

  # Update status
  echo "running" > "$GRAPH_DIR/${task_id}-status"

  # ============================================================================
  # INTEGRATION: Use worktree-setup.sh instead of inline git worktree
  # ============================================================================
  log "  [$task_id] Worker $worker_num: Creating worktree via worktree-setup.sh..."

  # Call worktree-setup.sh script
  if [ -f "./scripts/worktree-setup.sh" ]; then
    # Capture output and extract just the worktree path (last line)
    worktree_output=$(./scripts/worktree-setup.sh "$task_id" "agent-skills" 2>&1)
    worktree=$(echo "$worktree_output" | tail -1 | tr -d '\n')

    # Check if worktree-setup.sh succeeded and worktree exists
    if [ ! -d "$worktree" ]; then
      log_error "  [$task_id] Worktree setup failed"
      log_error "  [$task_id] Output: $worktree_output"
      echo "failed" > "$GRAPH_DIR/${task_id}-status"
      return 1
    fi
  else
    log_error "  [$task_id] worktree-setup.sh not found"
    echo "failed" > "$GRAPH_DIR/${task_id}-status"
    return 1
  fi

  log "  [$task_id] Worker $worker_num: Worktree created at $worktree"

  # Change to worktree directory
  cd "$worktree" || {
    log_error "  [$task_id] Failed to cd to worktree"
    echo "failed" > "$GRAPH_DIR/${task_id}-status"
    return 1
  }

  # INTEGRATION: Add mise trust support
  log "  [$task_id] Worker $worker_num: Setting up mise trust..."
  mise trust --yes "$worktree/.mise.toml" 2>/dev/null || true

  # Run the beads integration script for this single task
  log "  [$task_id] Worker $worker_num: Starting Ralph loop..."

  if ./scripts/ralph/beads-integration.sh "$task_id" > "$log_file" 2>&1; then
    log_success "  [$task_id] Worker $worker_num: ✓ COMPLETE"
    echo "complete" > "$GRAPH_DIR/${task_id}-status"

    # dx-alpha: Orchestrator closes Beads issues (implementers are read-only)
    if [ "$CLOSE_MODE" = "orchestrator" ]; then
      log "  [$task_id] Closing Beads issue (close-mode: orchestrator)..."
      BEADS_DIR="$BEADS_DIR" "$BD_BIN" --no-daemon close "$task_id" \
        --reason="Completed via Ralph orchestrator" 2>/dev/null || \
        log_warning "  [$task_id] Failed to close Beads issue (non-fatal)"
    fi

    # INTEGRATION: Keep worktree for debugging if KEEP_WORKTREES=1
    if [ "${KEEP_WORKTREES:-0}" != "1" ]; then
      cd "$WORKSPACE" || true
      git worktree remove "$worktree" -f 2>/dev/null || true
      log "  [$task_id] Worktree cleaned up"
    else
      log "  [$task_id] Worktree kept at: $worktree (KEEP_WORKTREES=1)"
    fi

    ((COMPLETED++))
  else
    log_error "  [$task_id] Worker $worker_num: ✗ FAILED (see $log_file)"
    echo "failed" > "$GRAPH_DIR/${task_id}-status"

    # Keep failed worktree for debugging
    log "  [$task_id] Worktree kept at: $worktree for debugging"

    ((FAILED++))
  fi

  cd "$WORKSPACE" || true
}

# Export functions and variables for subshells
export -f log log_success log_error log_warning run_single_task
export COMPLETED FAILED GRAPH_DIR LOG_DIR MAX_PARALLEL WORKSPACE BEADS_DIR CLOSE_MODE BD_BIN

# Execute each layer
for ((layer=0; layer<TOTAL_LAYERS; layer++)); do
  layer_tasks=$(cat "$GRAPH_DIR/layer-$layer")
  layer_size=$(echo "$layer_tasks" | wc -w | tr -d ' ')

  log "=================================================="
  log "LAYER $((layer + 1))/$TOTAL_LAYERS: $layer_size task(s)"
  log "=================================================="

  # Split into batches of MAX_PARALLEL
  batch_start=1
  worker_num=0

  while [ $batch_start -le $layer_size ]; do
    batch_end=$((batch_start + MAX_PARALLEL - 1))
    if [ $batch_end -gt $layer_size ]; then
      batch_end=$layer_size
    fi

    # Get tasks for this batch
    batch_tasks=$(echo "$layer_tasks" | awk -v start=$batch_start -v end=$batch_end '{for(i=start;i<=end;i++) print $i}')

    # Start workers for this batch
    worker_pids=""

    for task_id in $batch_tasks; do
      # Check if dependencies are satisfied
      deps=$(cat "$GRAPH_DIR/${task_id}-deps")
      deps_ok=true

      if [ -n "$deps" ]; then
        for dep_id in $deps; do
          dep_status=$(cat "$GRAPH_DIR/${dep_id}-status")
          if [ "$dep_status" != "complete" ]; then
            log_warning "  [$task_id] Waiting for dependency $dep_id (status: $dep_status)..."
            deps_ok=false
            break
          fi
        done
      fi

      if [ "$deps_ok" = true ]; then
        # Run task in background (using subshell to avoid job control issues)
        (
          source /dev/stdin <<< "$(declare -f log log_success log_error log_warning run_single_task)"
          run_single_task "$task_id" "$layer" "$worker_num"
        ) &
        worker_pids="$worker_pids $!"
        ((worker_num++))
      else
        log_warning "  [$task_id] Skipping (dependencies not met)"
      fi
    done

    # Wait for this batch to complete
    for pid in $worker_pids; do
      wait $pid 2>/dev/null || true
    done

    # INTEGRATION: Progress reporting after each batch
    show_progress "$((batch_end - 1))" "$layer_size" "$layer"

    batch_start=$((batch_end + 1))
  done

  log ""

  # INTEGRATION: Retry logic for failed tasks in this layer
  # Collect failed task IDs
  FAILED_TASKS=""
  for task_id in $layer_tasks; do
    status=$(cat "$GRAPH_DIR/${task_id}-status" 2>/dev/null)
    if [ "$status" = "failed" ]; then
      FAILED_TASKS="$FAILED_TASKS $task_id"
    fi
  done

  if [ -n "$FAILED_TASKS" ]; then
    log "Retrying ${#FAILED_TASKS[@]} failed task(s) from this layer..."
    for task_id in $FAILED_TASKS; do
      attempt=1
      while [ $attempt -le $MAX_ATTEMPTS ]; do
        log "  [$task_id] Retry attempt $attempt/$MAX_ATTEMPTS"

        # Re-run the task (reuse same worker_num if possible)
        # Find available worker number
        retry_worker_num=$worker_num

        run_single_task "$task_id" "$layer" "$retry_worker_num"
        ((worker_num++))

        # Check if succeeded
        status=$(cat "$GRAPH_DIR/${task_id}-status" 2>/dev/null)
        if [ "$status" = "complete" ]; then
          log_success "  [$task_id] Retry succeeded!"
          break
        else
          ((attempt++))
        fi
      done
    done
  fi

  # RESUME MODE: Save checkpoint after each layer completes (agent-duf)
  if [ -n "$RESUME_MODE" ]; then
    CHECKPOINT_FILE="$WORKSPACE/$RESUME_MODE"
    # Collect all completed tasks so far
    COMPLETED_IN_CHECKPOINT=""
    for task_id in $TASK_IDS; do
      status=$(cat "$GRAPH_DIR/${task_id}-status" 2>/dev/null)
      if [ "$status" = "complete" ]; then
        COMPLETED_IN_CHECKPOINT="$COMPLETED_IN_CHECKPOINT$task_id\n"
      fi
    done
    echo -e "$COMPLETED_IN_CHECKPOINT" > "$CHECKPOINT_FILE"
    log "Checkpoint saved: $(echo -e "$COMPLETED_IN_CHECKPOINT" | wc -l | tr -d ' ') tasks completed"
  fi

  log ""
done

# Cleanup
rm -rf "$GRAPH_DIR"

# =============================================================================
# STEP 5: Summary
# =============================================================================

log "=================================================="
log "SUMMARY"
log "=================================================="
log "Total tasks: $(echo $TASK_IDS | wc -w | tr -d ' ')"
log "Completed: $COMPLETED"
log "Failed: $FAILED"
log ""

if [ $FAILED -eq 0 ]; then
  log_success "✓ ALL TASKS COMPLETED"
  exit 0
else
  log_error "✗ SOME TASKS FAILED"
  exit 1
fi
