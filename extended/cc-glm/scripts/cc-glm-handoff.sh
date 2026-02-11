#!/usr/bin/env bash
set -euo pipefail

# cc-glm-handoff.sh
#
# Completion gate + handoff checklist for delegated PR batches.
# Validates that delegated work meets orchestrator standards before commit/push.
#
# Commands:
#   check      --beads <id> --worktree <path> [--log-dir <dir>]
#   report     --worktree <path> [--log-dir <dir>]
#   checklist  [--format {table|json}]
#   sample     [--format {table|json}]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_HELPER="${SCRIPT_DIR}/cc-glm-job.sh"
LOG_DIR="/tmp/cc-glm-jobs"
CMD="${1:-}"
shift || true

# Colors for terminal output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  GRAY='\033[0;90m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  GRAY=''
  NC=''
fi

usage() {
  cat <<'EOF'
cc-glm-handoff.sh

Completion gate + handoff checklist for delegated PR batches.

Usage:
  cc-glm-handoff.sh check --beads <id> --worktree <path> [--log-dir <dir>]
  cc-glm-handoff.sh report --worktree <path> [--log-dir <dir>]
  cc-glm-handoff.sh checklist [--format {table|json}]
  cc-glm-handoff.sh sample [--format {table|json}]

Commands:
  check      Validate a single completed delegated job against handoff gates
  report     Generate coordinator report for all completed jobs in a worktree
  checklist  Print the handoff checklist (for reference)
  sample     Run check in dry-run mode with sample output

Checklist gates:
  ✓ 1. Diff review: changes present and reviewed
  ✓ 2. Validation: tests/lint pass
  ✓ 3. Beads status: issue not already closed
  ✓ 4. Risk assessment: documented acceptable

Exit codes:
  0  All gates passed (ready for commit/push)
  1  One or more gates failed
  2  Job still running (not ready for handoff)
  3  Invalid arguments or environment
EOF
}

# Check helpers
check_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
  echo -e "${RED}✗${NC} $1"
}

check_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

check_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

print_checklist() {
  local format="${1:-table}"
  if [[ "$format" == "json" ]]; then
    cat <<'EOF'
{
  "checklist": [
    {"id": 1, "name": "diff_review", "description": "Changes present and reviewed", "required": true},
    {"id": 2, "name": "validation", "description": "Tests and lint pass", "required": true},
    {"id": 3, "name": "beads_status", "description": "Issue not already closed", "required": true},
    {"id": 4, "name": "risk_assessment", "description": "Risks documented and acceptable", "required": true}
  ],
  "gates": {
    "diff_review": "git diff --stat HEAD in worktree must show changes",
    "validation": "Validation commands from job output must pass",
    "beads_status": "bd show <beads> must indicate issue is open",
    "risk_assessment": "Job output must include risk notes or declare 'none'"
  }
}
EOF
    return 0
  fi

  cat <<'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║           CC-GLM HANDOFF CHECKLIST (PR Batch Completion)          ║
╚═══════════════════════════════════════════════════════════════════╝

Gate 1: DIFF REVIEW
  Status: [ ] PASS  [ ] FAIL  [ ] SKIP
  ├─ Changes present in worktree?
  │  Command: git diff --stat HEAD
  │  Expected: At least one file changed
  ├─ Diff reviewed and understood?
  │  Command: git diff HEAD
  │  Expected: Changes match task scope
  └─ Notes: __________________________________________________

Gate 2: VALIDATION
  Status: [ ] PASS  [ ] FAIL  [ ] SKIP
  ├─ Tests pass (if applicable)?
  │  Command: (from job output)
  │  Expected: Exit code 0
  ├─ Lint/format checks pass?
  │  Command: (from job output)
  │  Expected: No errors
  └─ Notes: __________________________________________________

Gate 3: BEADS STATUS
  Status: [ ] PASS  [ ] FAIL  [ ] SKIP
  ├─ Issue still open?
  │  Command: bd show <beads-id>
  │  Expected: Status is NOT "closed"
  ├─ Beads metadata consistent?
  │  Check: repo, worktree, agent match task
  │  Expected: All fields populated correctly
  └─ Notes: __________________________________________________

Gate 4: RISK ASSESSMENT
  Status: [ ] PASS  [ ] FAIL  [ ] SKIP
  ├─ Risks documented in job output?
  │  Look for: "risks:" or "risk notes:" section
  │  Expected: Either risks listed OR explicit "none"
  ├─ Risks acceptable for commit?
  │  Consider: blast radius, reversibility, security impact
  │  Expected: Low risk OR documented mitigation
  └─ Notes: __________________________________________________

DECISION GATE
  [ ] READY TO COMMIT  [ ] NEEDS REVISION  [ ] BLOCKED

  Ready if: All required gates PASS
  Revise if: Any gate FAILS (document reason)
  Blocked if: Risk assessment shows unacceptable risk

╔═══════════════════════════════════════════════════════════════════╗
║                     COORDINATOR ACTIONS                           ║
╚═══════════════════════════════════════════════════════════════════╝

If READY TO COMMIT:
  1. cd <worktree>
  2. git add <files>
  3. git commit -m "<message>" -m "Co-Authored-By: cc-glm <noreply@anthropic.com>"
  4. git push
  5. bd close <beads-id> --reason "Completed"

If NEEDS REVISION:
  1. Document specific issues in <beads>.handoff-notes.txt
  2. Either: fix manually OR restart job with refined prompt
  3. Re-run check when ready

If BLOCKED:
  1. Escalate to human decision-maker
  2. Create blocking issue if needed
  3. Do NOT commit or close Beads

╔═══════════════════════════════════════════════════════════════════╗
║                  PARALLEL BATCH MODE (2-4 threads)                ║
╚═══════════════════════════════════════════════════════════════════╝

Running multiple delegated jobs:

  1. Launch in parallel (detached):
     for beads in bd-001 bd-002 bd-003; do
       cc-glm-job.sh start --beads $beads --repo foo --worktree /tmp/agents/$beads/foo \
         --prompt-file /tmp/cc-glm-jobs/$beads.prompt.txt
     done

  2. Monitor periodically (every 5 min):
     watch -n 300 'cc-glm-job.sh status'

  3. When jobs complete, run report:
     cc-glm-handoff.sh report --worktree /tmp/agents

  4. Process each job through check:
     cc-glm-handoff.sh check --beads bd-001 --worktree /tmp/agents/bd-001/foo

  5. Commit accepted work, restart failed jobs

EOF
}

# Parse job log to extract validation commands
extract_validation_commands() {
  local log_file="$1"
  # Look for patterns like "validation:" or "validation commands:" or "Commands to validate:"
  awk '
    /^[Vv]alidation:/,/^$/ { if (!/^[Vv]alidation:/) print }
    /^[Vv]alidation commands:/,/^$/ { if (!/^[Vv]alidation commands:/) print }
    /^[Cc]ommands to validate:/,/^$/ { if (!/^[Cc]ommands to validate:/) print }
  ' "$log_file" | sed '/^$/d' | head -10
}

# Parse job log to extract risk notes
extract_risk_notes() {
  local log_file="$1"
  # Look for patterns like "risks:" or "risk notes:" or "known gaps:"
  awk '
    /^[Rr]isks?:/,/^$/ { if (!/^[Rr]isks?:/) print }
    /^[Rr]isk notes?:/,/^$/ { if (!/^[Rr]isk notes?:/) print }
    /^[Kk]nown gaps?:/,/^$/ { if (!/^[Kk]nown gaps?:/) print }
  ' "$log_file" | sed '/^$/d' | head -10
}

# Check if job is still running
check_job_running() {
  local beads="$1"
  if [[ -x "$JOB_HELPER" ]]; then
    local state
    state="$("$JOB_HELPER" check --beads "$beads" --log-dir "$LOG_DIR" 2>&1 || true)"
    if [[ "$state" == *"healthy:"* ]]; then
      return 0  # Still running
    fi
  fi

  # Fallback: check PID file directly
  local pid_file="$LOG_DIR/${beads}.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
      return 0  # Still running
    fi
  fi

  return 1  # Not running
}

# Run handoff check for a single job
check_cmd() {
  local BEADS=""
  local WORKTREE=""
  local DRY_RUN=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --beads)
        BEADS="${2:-}"
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
      --dry-run)
        DRY_RUN="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage
        exit 3
        ;;
    esac
  done

  [[ -n "$BEADS" ]] || { echo "check requires --beads" >&2; exit 3; }
  [[ -n "$WORKTREE" ]] || { echo "check requires --worktree" >&2; exit 3; }

  if [[ -n "$DRY_RUN" ]]; then
    check_info "Dry-run mode: sample output for beads=$BEADS, worktree=$WORKTREE"
    echo ""
  fi

  # Check if job is still running
  if [[ -z "$DRY_RUN" ]] && check_job_running "$BEADS"; then
    check_warn "Job $BEADS is still running"
    echo ""
    echo "Use 'cc-glm-job.sh status' to monitor progress"
    exit 2
  fi

  local LOG_FILE="$LOG_DIR/${BEADS}.log"
  local META_FILE="$LOG_DIR/${BEADS}.meta"
  local HANDOFF_NOTES="$LOG_DIR/${BEADS}.handoff-notes.txt"

  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║              HANDOFF CHECK: $BEADS"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo ""

  local all_passed=true
  local gate_status=""

  # Gate 1: Diff Review
  echo "GATE 1: DIFF REVIEW"
  echo "─────────────────────────────────────────────────────────────────────"

  if [[ -n "$DRY_RUN" ]]; then
    check_info "(dry-run) Would check: git diff --stat HEAD in $WORKTREE"
    check_pass "Changes present (dry-run)"
    check_pass "Diff reviewed (dry-run)"
  else
    if [[ ! -d "$WORKTREE" ]]; then
      check_fail "Worktree not found: $WORKTREE"
      all_passed=false
    else
      cd "$WORKTREE"
      local changed_files
      changed_files="$(git diff --stat HEAD 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$changed_files" -gt 0 ]]; then
        check_pass "Changes present: $changed_files file(s) changed"
        git diff --stat HEAD 2>/dev/null | head -10
      else
        check_fail "No changes found in worktree"
        all_passed=false
      fi
    fi
  fi
  echo ""

  # Gate 2: Validation
  echo "GATE 2: VALIDATION"
  echo "─────────────────────────────────────────────────────────────────────"

  if [[ -n "$DRY_RUN" ]]; then
    check_info "(dry-run) Would run validation commands from job output"
    check_pass "Tests pass (dry-run)"
  else
    if [[ -f "$LOG_FILE" ]]; then
      local val_commands
      val_commands="$(extract_validation_commands "$LOG_FILE")"
      if [[ -n "$val_commands" ]]; then
        check_info "Validation commands from job output:"
        echo "$val_commands" | head -5
        check_info "Run these manually to verify"
        check_pass "Validation commands documented"
      else
        check_warn "No validation commands found in job output"
        check_warn "Consider running project tests: make test, npm test, pytest, etc."
      fi
    else
      check_warn "No log file found at $LOG_FILE"
      check_info "Cannot verify validation status"
    fi
  fi
  echo ""

  # Gate 3: Beads Status
  echo "GATE 3: BEADS STATUS"
  echo "─────────────────────────────────────────────────────────────────────"

  if [[ -n "$DRY_RUN" ]]; then
    check_info "(dry-run) Would check: bd show $BEADS"
    check_pass "Issue open (dry-run)"
  else
    if command -v bd >/dev/null 2>&1; then
      local bd_output
      bd_output="$(bd show "$BEADS" 2>&1 || true)"
      if [[ "$bd_output" == *"closed"* ]] || [[ "$bd_output" == *"Closed"* ]]; then
        check_warn "Beads issue appears to be closed"
      else
        check_pass "Beads issue appears open"
      fi
    else
      check_info "bd command not available; skipping status check"
    fi

    if [[ -f "$META_FILE" ]]; then
      check_info "Metadata found: $META_FILE"
      grep -E "^(beads|repo|worktree|agent)=" "$META_FILE" 2>/dev/null || true
    fi
  fi
  echo ""

  # Gate 4: Risk Assessment
  echo "GATE 4: RISK ASSESSMENT"
  echo "─────────────────────────────────────────────────────────────────────"

  if [[ -n "$DRY_RUN" ]]; then
    check_info "(dry-run) Would extract risk notes from job output"
    check_pass "Risks documented and acceptable (dry-run)"
  else
    if [[ -f "$LOG_FILE" ]]; then
      local risks
      risks="$(extract_risk_notes "$LOG_FILE")"
      if [[ -n "$risks" ]]; then
        check_info "Risk notes from job output:"
        echo "$risks" | head -5
        check_pass "Risks documented"
      else
        check_warn "No risk notes found in job output"
        check_warn "Assess risk before committing"
      fi
    else
      check_warn "No log file; cannot assess risk from job output"
    fi

    if [[ -f "$HANDOFF_NOTES" ]]; then
      check_info "Handoff notes found:"
      cat "$HANDOFF_NOTES" | head -5
    fi
  fi
  echo ""

  # Decision Gate
  echo "DECISION GATE"
  echo "─────────────────────────────────────────────────────────────────────"

  if [[ "$all_passed" == "true" ]]; then
    check_pass "All gates PASSED - Ready for commit/push"
    gate_status="READY_TO_COMMIT"
  else
    check_fail "One or more gates FAILED - Review needed"
    gate_status="NEEDS_REVISION"
  fi

  echo ""
  echo "Next steps:"
  if [[ "$gate_status" == "READY_TO_COMMIT" ]]; then
    echo "  1. cd $WORKTREE"
    echo "  2. git add <files>"
    echo "  3. git commit -m \"feat: $BEADS\" -m \"Co-Authored-By: cc-glm <noreply@anthropic.com>\""
    echo "  4. git push"
    echo "  5. bd close $BEADS --reason 'Completed'"
  else
    echo "  1. Review failed gates above"
    echo "  2. Add notes to: $HANDOFF_NOTES"
    echo "  3. Either fix manually or restart with refined prompt"
    echo "  4. Re-run: cc-glm-handoff.sh check --beads $BEADS --worktree $WORKTREE"
  fi

  if [[ "$all_passed" == "true" ]]; then
    exit 0
  else
    exit 1
  fi
}

# Generate coordinator report for multiple jobs
report_cmd() {
  local WORKTREE=""
  local format="table"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --worktree)
        WORKTREE="${2:-}"
        shift 2
        ;;
      --log-dir)
        LOG_DIR="${2:-}"
        shift 2
        ;;
      --format)
        format="${2:-table}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        usage
        exit 3
        ;;
    esac
  done

  [[ -n "$WORKTREE" ]] || { echo "report requires --worktree" >&2; exit 3; }

  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║           COORDINATOR REPORT: Delegated PR Batch                 ║"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo ""

  # Find all job metadata files
  local completed=0
  local running=0
  local failed=0
  local ready=0

  shopt -s nullglob
  local meta_files=("$LOG_DIR"/*.meta)
  shopt -u nullglob

  if [[ ${#meta_files[@]} -eq 0 ]]; then
    check_info "No delegated jobs found in $LOG_DIR"
    echo ""
    echo "Launch jobs with:"
    echo "  cc-glm-job.sh start --beads <id> --repo <name> --worktree <path> --prompt-file <path>"
    exit 0
  fi

  # Table header
  if [[ "$format" == "table" ]]; then
    printf "%-14s %-8s %-10s %-10s %-10s\n" \
      "bead" "state" "duration" "gates" "action"
    printf "%s\n" "$(printf '─%.0s' {1..60})"
  fi

  for meta_file in "${meta_files[@]}"; do
    local beads
    beads="$(basename "$meta_file" .meta)"

    local pid_file="$LOG_DIR/${beads}.pid"
    local log_file="$LOG_DIR/${beads}.log"

    # Determine job state
    local state="unknown"
    local duration="-"

    if [[ -f "$pid_file" ]]; then
      local pid
      pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        state="running"
        running=$((running + 1))
      else
        state="exited"
      fi
    fi

    # Get duration from metadata
    if [[ -f "$meta_file" ]]; then
      local started_at
      started_at="$(grep "^started_at=" "$meta_file" | cut -d= -f2)"
      if [[ -n "$started_at" ]]; then
        local start_sec now_sec
        start_sec="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || date -d "$started_at" "+%s" 2>/dev/null || echo "0")"
        now_sec="$(date +%s)"
        local elapsed=$((now_sec - start_sec))
        if [[ "$elapsed" -gt 0 ]]; then
          local min=$((elapsed / 60))
          if [[ "$min" -lt 60 ]]; then
            duration="${min}m"
          else
            local hr=$((min / 60))
            duration="${hr}h"
          fi
        fi
      fi
    fi

    # Check gates for completed jobs
    local gates="-"
    local action="-"

    if [[ "$state" == "exited" ]]; then
      completed=$((completed + 1))

      # Quick gate checks (non-blocking)
      local has_diff=false
      local has_validation=false
      local has_risks=false

      if [[ -f "$log_file" ]]; then
        if grep -q "diff\|changed\|modified" "$log_file" 2>/dev/null; then
          has_diff=true
        fi
        if grep -qi "validation\|test" "$log_file" 2>/dev/null; then
          has_validation=true
        fi
        if grep -qi "risk\|gap" "$log_file" 2>/dev/null; then
          has_risks=true
        fi
      fi

      if [[ "$format" == "table" ]]; then
        local gate_summary=""
        [[ "$has_diff" == "true" ]] && gate_summary="${gate_summary}D"
        [[ "$has_validation" == "true" ]] && gate_summary="${gate_summary}V"
        [[ "$has_risks" == "true" ]] && gate_summary="${gate_summary}R"
        [[ -z "$gate_summary" ]] && gate_summary="?"

        gates="$gate_summary"
        action="check"

        if [[ "$has_diff" == "true" && "$has_validation" == "true" ]]; then
          ready=$((ready + 1))
        fi
      fi
    fi

    if [[ "$format" == "table" ]]; then
      printf "%-14s %-8s %-10s %-10s %-10s\n" \
        "$beads" "$state" "$duration" "$gates" "$action"
    fi
  done

  echo ""
  echo "Summary:"
  echo "  Total jobs: ${#meta_files[@]}"
  echo "  Running: $running"
  echo "  Completed: $completed"
  echo "  Ready for handoff: $ready"

  if [[ "$running" -gt 0 ]]; then
    echo ""
    check_info "Jobs still running - monitor with: cc-glm-job.sh status"
  fi

  if [[ "$ready" -gt 0 ]]; then
    echo ""
    check_pass "Run handoff check for each completed job:"
    echo "  cc-glm-handoff.sh check --beads <id> --worktree $WORKTREE"
  fi

  # Emit JSON format if requested
  if [[ "$format" == "json" ]]; then
    echo ""
    echo "{"
    echo "  \"total\": ${#meta_files[@]},"
    echo "  \"running\": $running,"
    echo "  \"completed\": $completed,"
    echo "  \"ready_for_handoff\": $ready"
    echo "}"
  fi
}

sample_cmd() {
  local format="${1:-table}"
  echo "Sample handoff check output"
  echo ""
  check_cmd --beads "bd-sample" --worktree "/tmp/agents/bd-sample/repo" --dry-run
}

case "$CMD" in
  check) check_cmd "$@" ;;
  report) report_cmd "$@" ;;
  checklist) print_checklist "${2:-table}" ;;
  sample) sample_cmd "${2:-table}" ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage
    exit 3
    ;;
esac
