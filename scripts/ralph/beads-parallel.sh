#!/bin/bash
# Ralph Parallel Execution via Beads Dependencies
# Usage: ./beads-parallel.sh <task-id-1> <task-id-2> ... [--max-parallel N]
# Bash 3.2 compatible (macOS default)

set -e

# Configuration
BEADS_DIR="/Users/fengning/agent-skills/.beads"
MAX_PARALLEL=${MAX_PARALLEL:-3}  # Default: 3 parallel workers
WORKSPACE="/Users/fengning/agent-skills"
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
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    agent-*)
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
log "Tasks: $TASK_IDS"
log "Max parallel workers: $MAX_PARALLEL"
log ""

# =============================================================================
# STEP 1: Build dependency graph (stored as temp files for bash 3.2 compatibility)
# =============================================================================

log "Building dependency graph..."

GRAPH_DIR="/tmp/ralph-graph-$$"
mkdir -p "$GRAPH_DIR"

# PERFORMANCE FIX: Batch fetch all task data at once
# Use bd list --json once to get all tasks, then filter locally
log "Fetching task data from Beads..."
ALL_TASKS_JSON=$(BEADS_DIR="$BEADS_DIR" /opt/homebrew/bin/bd list --json 2>/dev/null)

# Create lookup table from all tasks
echo "$ALL_TASKS_JSON" > "$GRAPH_DIR/all-tasks.json"

for task_id in $TASK_IDS; do
  # Extract task from all tasks JSON
  task_json=$(echo "$ALL_TASKS_JSON" | jq -r ".[] | select(.id == \"$task_id\")")

  if [ -z "$task_json" ]; then
    log_error "Task $task_id not found"
    rm -rf "$GRAPH_DIR"
    exit 1
  fi

  # Extract dependencies and save to file
  deps=$(echo "$task_json" | jq -r '.dependencies[]?.id' | tr '\n' ' ' | sed 's/ $//')
  echo "$deps" > "$GRAPH_DIR/${task_id}-deps"
  echo "pending" > "$GRAPH_DIR/${task_id}-status"
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
export COMPLETED FAILED GRAPH_DIR LOG_DIR MAX_PARALLEL WORKSPACE BEADS_DIR

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
      local attempt=1
      while [ $attempt -le $MAX_ATTEMPTS ]; do
        log "  [$task_id] Retry attempt $attempt/$MAX_ATTEMPTS"

        # Re-run the task (reuse same worker_num if possible)
        # Find available worker number
        local retry_worker_num=$worker_num

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
