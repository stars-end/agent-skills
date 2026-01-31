#!/bin/bash
set -e

# Ralph Autonomous Loop with Beads Integration
# Usage: ./beads-integration.sh <epic-id>

EPIC_ID="$1"
if [ -z "$EPIC_ID" ]; then
  echo "Usage: $0 <epic-id>"
  echo "Example: $0 agent-test-epic"
  exit 1
fi

export BEADS_DIR=/Users/fengning/agent-skills/.beads

# Configuration
BASE="http://127.0.0.1:4105"
IMPLEMENTER_AGENT="ralph-implementer"
REVIEWER_AGENT="ralph-reviewer"
IMPL_PROVIDER="zai-coding-plan"
IMPL_MODEL="glm-4.7"
REV_PROVIDER="zai-coding-plan"
REV_MODEL="glm-4.7"

# Timeout settings (seconds)
AGENT_TIMEOUT=180         # Per-agent call timeout (3 minutes)
MAX_ATTEMPTS=3            # Max revision attempts per task

WORKSPACE="/Users/fengning/agent-skills"
WORK_DIR="$WORKSPACE/.ralph-work-$$"
mkdir -p "$WORK_DIR/logs"
LOG_DIR="$WORK_DIR/logs"

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_DIR/beads-integration.log"
}

error() {
  echo "[$(date +%H:%M:%S)] ERROR: $*" | tee -a "$LOG_DIR/beads-integration.log" >&2
}

# Initialize git workspace
cd "$WORKSPACE"
# Clean up existing work directory if it exists
if [ -d "$WORK_DIR" ]; then
  rm -rf "$WORK_DIR" 2>/dev/null || true
fi
mkdir -p "$WORK_DIR"
mkdir -p "$WORK_DIR/logs"  # Create logs directory BEFORE logging starts
cd "$WORK_DIR"
git init -q
git config user.email "ralph-beads@local"
git config user.name "Ralph Beads Integration"
git commit --allow-empty -m "Initial commit" -q

log "=== Ralph Beads Integration ==="
log "Epic ID: $EPIC_ID"
log "Work directory: $WORK_DIR"
log ""

# Get epic details
log "Fetching epic details..."
EPIC_JSON=$(bd --no-daemon --db "$BEADS_DIR/beads.db" --allow-stale show "$EPIC_ID" --json 2>/dev/null)
if [ -z "$EPIC_JSON" ]; then
  error "Epic $EPIC_ID not found"
  exit 1
fi

EPIC_TITLE=$(echo "$EPIC_JSON" | jq -r '.[0].title')
EPIC_DESC=$(echo "$EPIC_JSON" | jq -r '.[0].description')
log "Epic: $EPIC_TITLE"
log "Description: $EPIC_DESC"
log ""

# Get all subtasks of this epic (from dependents array)
log "Fetching subtasks..."
SUBTASKS=$(echo "$EPIC_JSON" | jq -r '.[0].dependents // []')

if [ -z "$SUBTASKS" ] || [ "$SUBTASKS" = "[]" ]; then
  error "No subtasks found for epic $EPIC_ID"
  exit 1
fi

# Count subtasks
SUBTASK_COUNT=$(echo "$SUBTASKS" | jq 'length')
log "Found $SUBTASK_COUNT subtasks"
log ""

# Sort subtasks by dependencies (simple topological sort)
# For now, just process in order - full dependency sorting would require more complex logic
SUBTASK_IDS=$(echo "$SUBTASKS" | jq -r '.[].id')

# Statistics
TOTAL_TASKS=$SUBTASK_COUNT
COMPLETED=0
REVISIONS=0
FAILED=0

# Session management
create_session() {
  curl -s -X POST "$BASE/session" -H "Content-Type: application/json" -d '{"title":"Ralph Beads"}' | jq -r '.id'
}

delete_session() {
  curl -s -X DELETE "$BASE/session/$1" >/dev/null 2>&1 || true
}

run_agent() {
  local agent="$1"
  local provider="$2"
  local model="$3"
  local prompt="$4"
  local output_file="$5"

  local session_id=$(create_session)
  local escaped_prompt=$(echo "$prompt" | jq -Rs .)

  local response=$(timeout "$AGENT_TIMEOUT" curl -s -X POST "$BASE/session/$session_id/message" \
    -H "Content-Type: application/json" \
    -d "{\"agent\":\"$agent\",\"model\":{\"providerID\":\"$provider\",\"modelID\":\"$model\"},\"parts\":[{\"type\":\"text\",\"text\":$escaped_prompt}]}")

  delete_session "$session_id"

  echo "$response" > "$output_file.json"

  # Extract text using JSON parsing - get first text part with full content (no head -1, text may contain newlines)
  local text=$(echo "$response" | jq -r '.parts[] | select(.type == "text") | .text' 2>/dev/null)

  # Fallback to regex if JSON parsing fails (no head -1 here either)
  if [ -z "$text" ]; then
    text=$(echo "$response" | grep -o '"type":"text"[^}]*"text":"[^"]*"' | sed 's/.*"text":"\([^"]*\)".*/\1/')
  fi

  if [ -z "$text" ]; then
    text="ERROR: No response"
  fi

  # Remove markdown code blocks if present (LLMs often wrap responses in ```text```)
  text=$(echo "$text" | sed 's/^```\s*//; s/\s*```\s*$//')

  # Check if text is empty after markdown stripping (agent returned only ``` markers)
  if [ -z "$text" ]; then
    text="ERROR: Empty agent response after markdown stripping"
  fi

  # Write output file (more robust)
  {
    printf '%s\n' "$text" > "$output_file" 2>/dev/null || echo "Failed to write to: [$output_file]"
  } 2>&1

  # Return the text
  printf '%s\n' "$text"
}

parse_signal() {
  local output="$1"

  # Check for APPROVED signal (multiple patterns for robustness)
  if echo "$output" | grep -qE "(✅ APPROVED|APPROVED|✅)"; then
    echo "APPROVED"
  # Check for REVISION_REQUIRED signal (multiple patterns)
  elif echo "$output" | grep -qE "(🔴 REVISION_REQUIRED|REVISION_REQUIRED|🔴)"; then
    echo "REVISION_REQUIRED"
  else
    echo "UNKNOWN"
  fi
}

# Process each subtask
TASK_NUM=1
for TASK_ID in $SUBTASK_IDS; do
  log "$(printf '=%.0s' {1..60})"
  log " TASK $TASK_NUM/$TOTAL_TASKS: $TASK_ID"
  log "$(printf '=%.0s' {1..60})"

  # Get task details
  TASK_JSON=$(bd --no-daemon --db "$BEADS_DIR/beads.db" --allow-stale show "$TASK_ID" --json 2>/dev/null)
  TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.[0].title')
  TASK_DESC=$(echo "$TASK_JSON" | jq -r '.[0].description // "No description"')

  log "Title: $TASK_TITLE"
  log "Description: $TASK_DESC"
  log ""

  # Create task file for Ralph
  cat > "$WORK_DIR/RALPH_TASK.md" << EOF
# Ralph Task: $TASK_TITLE

## Task ID
$TASK_ID

## Description
$TASK_DESC

## Acceptance
Complete this task according to the description above.
EOF

  git add "$WORK_DIR/RALPH_TASK.md"
  git commit -m "Add task file for $TASK_ID" -q

  attempt=1
  approved=false

  while [ $attempt -le "$MAX_ATTEMPTS" ] && [ "$approved" = false ]; do
    log "Attempt $attempt/$MAX_ATTEMPTS"

    # Get current commit
    BEFORE_COMMIT=$(cd "$WORK_DIR" && git rev-parse HEAD)

    # Run implementer
    log "🟢 IMPLEMENTER ($IMPL_MODEL)"
    # Store prompt in variable first (avoid multi-line string in command substitution)
    impl_prompt="Working directory: $WORK_DIR

Read the task from RALPH_TASK.md and implement it.

Task: $TASK_DESC
Task ID: $TASK_ID

IMPORTANT: Use absolute paths for all file operations.
Working directory: $WORK_DIR

NOTE: OpenCode may add an extra trailing newline. This is acceptable.

Output: IMPLEMENTATION_COMPLETE when done."
    impl_output=$(run_agent "$IMPLEMENTER_AGENT" "$IMPL_PROVIDER" "$IMPL_MODEL" "$impl_prompt" "$LOG_DIR/impl-$TASK_ID-attempt-$attempt.log")

    echo "$impl_output" >> "$LOG_DIR/test.log"

    # Stage and commit changes
    cd "$WORK_DIR"
    git add -A 2>/dev/null || true
    git commit -m "$TASK_ID: Cycle $TASK_NUM attempt $attempt [$TASK_ID]" -q 2>/dev/null || true

    AFTER_COMMIT=$(cd "$WORK_DIR" && git rev-parse HEAD)

    # Run reviewer
    log "🔴 REVIEWER ($REV_MODEL)"
    # Store prompt in variable first (avoid multi-line string in command substitution)
    rev_prompt="Working directory: $WORK_DIR

Review the implementation for task: $TASK_TITLE
Task ID: $TASK_ID

Check the implementation by examining files in: $WORK_DIR
List files: ls $WORK_DIR
Read task: cat $WORK_DIR/RALPH_TASK.md

Verify the implementation satisfies the requirements.

IMPORTANT: Be lenient about extra trailing newlines (OpenCode known issue).
Focus on: correct file created, correct content, functional implementation.

Output signal (one line only):
✅ APPROVED: [concise reason]
🔴 REVISION_REQUIRED: [specific issue]"
    rev_output=$(run_agent "$REVIEWER_AGENT" "$REV_PROVIDER" "$REV_MODEL" "$rev_prompt" "$LOG_DIR/rev-$TASK_ID-attempt-$attempt.log")

    echo "$rev_output" >> "$LOG_DIR/test.log"

    signal=$(parse_signal "$rev_output")
    log "Decision: $signal"

    if [ "$signal" = "APPROVED" ]; then
      log "Signal: $rev_output"
      ((COMPLETED++))
      approved=true

      # Mark Beads task as complete
      log "Closing Beads task: $TASK_ID"
      bd --no-daemon --db "$BEADS_DIR/beads.db" close "$TASK_ID" --reason="Completed via Ralph Beads Integration: $rev_output" 2>/dev/null || true

      # Create final commit with Beads ID
      git commit --amend -m "$TASK_ID: Complete [$TASK_ID]

Approved via Ralph Beads Integration
$rev_output" -q

    elif [ "$signal" = "REVISION_REQUIRED" ]; then
      log "Signal: $rev_output"
      ((REVISIONS++))
      ((attempt++))

      if [ $attempt -gt "$MAX_ATTEMPTS" ]; then
        ((FAILED++))
        log "❌ Task $TASK_ID FAILED after $MAX_ATTEMPTS attempts"
        approved=true
      fi
    else
      ((FAILED++))
      log "❌ Task $TASK_ID FAILED - Unknown signal"
      approved=true
    fi

    log ""
  done

  ((TASK_NUM++))
done

# Final statistics
log "$(printf '=%.0s' {1..60})"
log " 📊 FINAL STATISTICS"
log "$(printf '=%.0s' {1..60})"
log "Total tasks: $TOTAL_TASKS"
log "Completed: $COMPLETED"
log "Revisions: $REVISIONS"
log "Failed: $FAILED"
log "Success rate: $(( (COMPLETED * 100) / TOTAL_TASKS ))%"
log ""

# Check if epic is complete
if [ $COMPLETED -eq $TOTAL_TASKS ]; then
  log "✅ ALL TASKS COMPLETED - EPIC READY FOR REVIEW"

  # Mark epic as complete
  log "Closing epic: $EPIC_ID"
  bd --no-daemon --db "$BEADS_DIR/beads.db" close "$EPIC_ID" --reason="All subtasks completed via Ralph Beads Integration" 2>/dev/null || true
else
  log "⚠️  SOME TASKS FAILED - EPIC INCOMPLETE"
fi

# Check for orphaned sessions
REMAINING=$(curl -s "$BASE/session" | jq 'length' 2>/dev/null || echo "0")
log "Remaining OpenCode sessions: $REMAINING"

log ""
log "Work directory preserved at: $WORK_DIR"
log "Logs available at: $LOG_DIR"

if [ $FAILED -eq 0 ] && [ $COMPLETED -eq $TOTAL_TASKS ]; then
  exit 0
else
  exit 1
fi
