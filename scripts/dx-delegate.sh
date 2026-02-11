#!/usr/bin/env bash
#
# dx-delegate.sh
#
# DX-compliant wrapper for cc-glm headless delegation.
# Enforces V8.1 guardrails: canonical CWD hard-stop, worktree validation,
# Feature-Key tracking, and logging.
#
# Usage:
#   dx-delegate.sh --beads-id bd-XXXX --repo repo-name --prompt "..."
#   dx-delegate.sh --beads-id bd-XXXX --repo repo-name --prompt-file /path/to/prompt.txt
#   dx-delegate.sh --beads-id bd-XXXX --repo repo-name --scope "..." --constraints "..." --prompt "..."
#
# Environment:
#   AGENTS_ROOT: Path to agent-skills (default: ~/agent-skills)
#   DX_DELEGATE_LOG_DIR: Log directory (default: /tmp/dx-delegate)
#

set -euo pipefail

# Defaults
AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agent-skills}"
DX_DELEGATE_LOG_DIR="${DX_DELEGATE_LOG_DIR:-/tmp/dx-delegate}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical detection library
if [[ -f "$SCRIPT_DIR/lib/canonical-detect.sh" ]]; then
  source "$SCRIPT_DIR/lib/canonical-detect.sh"
else
  echo "Error: canonical-detect.sh not found at $SCRIPT_DIR/lib/" >&2
  exit 2
fi

usage() {
  cat >&2 <<'EOF'
dx-delegate.sh - DX-compliant cc-glm delegation wrapper

Usage:
  dx-delegate.sh --beads-id bd-XXXX --repo repo-name --prompt "..."
  dx-delegate.sh --beads-id bd-XXXX --repo repo-name --prompt-file /path/to/prompt.txt
  dx-delegate.sh --beads-id bd-XXXX --repo repo-name --scope "..." --constraints "..." --prompt "..."

Required:
  --beads-id bd-XXXX      Beads issue ID (e.g., bd-f6fh)
  --repo repo-name        Repository name (e.g., agent-skills, prime-radiant-ai)

Prompt (one required):
  --prompt "..."          Inline prompt string
  --prompt-file path      Read prompt from file

Optional context:
  --scope "..."           Task scope description
  --constraints "..."     Technical constraints
  --expected-outputs "..." Expected deliverables

Options:
  --no-logging            Disable session logging
  --dry-run               Show what would be delegated without running
  -h, --help              Show this help

Examples:
  # Simple delegation
  dx-delegate.sh --beads-id bd-f6fh --repo agent-skills \\
    --prompt "Update README with new usage examples"

  # Full context delegation
  dx-delegate.sh --beads-id bd-f6fh --repo agent-skills \\
    --scope "Add delegation boundary documentation" \\
    --constraints "No functional changes, docs only" \\
    --expected-outputs "Unified diff, validation commands" \\
    --prompt "Update extended/cc-glm/SKILL.md with delegation rules"

Notes:
  - Enforces canonical CWD hard-stop (blocks work in ~/{agent-skills,prime-radiant-ai,affordabot,llm-common})
  - Validates worktree exists at /tmp/agents/<beads-id>/<repo>
  - Logs session to /tmp/dx-delegate/<beads-id>/timestamp.log
  - Requires Feature-Key for traceability
EOF
}

# Parse arguments
BEADS_ID=""
REPO=""
PROMPT=""
PROMPT_FILE=""
SCOPE=""
CONSTRAINTS=""
EXPECTED_OUTPUTS=""
ENABLE_LOGGING=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beads-id)
      BEADS_ID="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --prompt)
      PROMPT="${2:-}"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --constraints)
      CONSTRAINTS="${2:-}"
      shift 2
      ;;
    --expected-outputs)
      EXPECTED_OUTPUTS="${2:-}"
      shift 2
      ;;
    --no-logging)
      ENABLE_LOGGING=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Validation
die() { echo "Error: $*" >&2; exit 2; }

[[ -n "$BEADS_ID" ]] || die "Missing required: --beads-id"
[[ -n "$REPO" ]] || die "Missing required: --repo"

# Beads ID format validation (basic check)
if [[ ! "$BEADS_ID" =~ ^bd-[a-z0-9]+$ ]]; then
  die "Invalid Beads ID format: $BEADS_ID (expected: bd-XXXX)"
fi

# Canonical CWD hard-stop (V8.1 guardrail)
if _dx_is_canonical_cwd_fast; then
  cat >&2 <<'EOF'
🚨 BLOCKED: Current working directory is within a canonical clone.

Canonical repositories (read-mostly):
  ~/agent-skills
  ~/prime-radiant-ai
  ~/affordabot
  ~/llm-common

To delegate work:
  1. Create a worktree: dx-worktree create $BEADS_ID $REPO
  2. cd to worktree: cd /tmp/agents/$BEADS_ID/$REPO
  3. Run dx-delegate.sh from the worktree

Recovery:
  dx-worktree create $BEADS_ID $REPO
  cd /tmp/agents/$BEADS_ID/$REPO
EOF
  exit 1
fi

# Worktree validation
WORKTREE_PATH="/tmp/agents/$BEADS_ID/$REPO"
if [[ ! -d "$WORKTREE_PATH/.git" ]]; then
  cat >&2 <<EOF
🚨 BLOCKED: Worktree not found at $WORKTREE_PATH

Required structure: /tmp/agents/<beads-id>/<repo>/.git

To create worktree:
  dx-worktree create $BEADS_ID $REPO

Current directory: $(pwd)
Expected worktree: $WORKTREE_PATH
EOF
  exit 1
fi

# Detect current branch for context
CURRENT_BRANCH="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

# Load prompt from file if specified
if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    die "Prompt file not found: $PROMPT_FILE"
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# Validate prompt content
if [[ -z "$PROMPT" ]]; then
  die "Missing prompt content (use --prompt or --prompt-file)"
fi

# Build DX-compliant prompt template
FULL_PROMPT="you're a mid-level junior dev agent working in a git worktree.

Repo: $WORKTREE_PATH
Branch: $CURRENT_BRANCH
Feature-Key: $BEADS_ID
Agent: cc-glm

## DX V8.1 Invariants (must follow)
- Never edit canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}. Work only in the worktree path above.
- Do not run git commit/push, do not open PRs. Just propose diffs + commands to run.
- Any new scripts must be deterministic + safe (no secrets).
"

# Add optional context sections
if [[ -n "$SCOPE" ]]; then
  FULL_PROMPT+="

## Scope
$SCOPE
"
fi

if [[ -n "$CONSTRAINTS" ]]; then
  FULL_PROMPT+="

## Constraints
$CONSTRAINTS
"
fi

if [[ -n "$EXPECTED_OUTPUTS" ]]; then
  FULL_PROMPT+="

## Expected Outputs
$EXPECTED_OUTPUTS
"
fi

FULL_PROMPT+="

## Task
$PROMPT

## Output Format
Provide a unified diff patch against current files, then list any commands to run to validate.
"

# Dry run: show prompt and exit
if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DX-Delegate Dry Run ===" >&2
  echo "Beads ID: $BEADS_ID" >&2
  echo "Repo: $REPO" >&2
  echo "Worktree: $WORKTREE_PATH" >&2
  echo "Branch: $CURRENT_BRANCH" >&2
  echo "Logging: $ENABLE_LOGGING" >&2
  echo "" >&2
  echo "=== Generated Prompt ===" >&2
  echo "$FULL_PROMPT"
  exit 0
fi

# Setup logging
if [[ "$ENABLE_LOGGING" == "true" ]]; then
  LOG_DIR="$DX_DELEGATE_LOG_DIR/$BEADS_ID"
  mkdir -p "$LOG_DIR"
  TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  LOG_FILE="$LOG_DIR/${TIMESTAMP}.log"

  {
    echo "=== DX-Delegate Session ==="
    echo "Timestamp: $(date -Iseconds)"
    echo "Beads ID: $BEADS_ID"
    echo "Repo: $REPO"
    echo "Worktree: $WORKTREE_PATH"
    echo "Branch: $CURRENT_BRANCH"
    echo "CWD: $(pwd)"
    echo ""
    echo "=== Prompt ==="
    echo "$FULL_PROMPT"
    echo ""
    echo "=== Output ==="
  } | tee -a "$LOG_FILE"
else
  LOG_FILE="/dev/null"
fi

# Prefer cc-glm (zsh function). Use a temp file to avoid quoting issues.
CC_GLM_WRAPPER="$AGENTS_ROOT/extended/cc-glm/scripts/cc-glm-headless.sh"
tmp="$(mktemp)"
cleanup() { rm -f "$tmp" 2>/dev/null || true; }
trap cleanup EXIT
printf "%s" "$FULL_PROMPT" > "$tmp"

# Run cc-glm with DX-compliant prompt
if [[ -x "$CC_GLM_WRAPPER" || -f "$CC_GLM_WRAPPER" ]]; then
  if bash "$CC_GLM_WRAPPER" --prompt-file "$tmp" 2>&1 | tee -a "$LOG_FILE"; then
    # Success
    {
      echo ""
      echo "=== Session Complete ==="
      echo "Log: $LOG_FILE"
    } | tee -a "$LOG_FILE" >&2
    exit 0
  fi
fi

# Fallback: standard Claude Code headless mode
if command -v claude >/dev/null 2>&1; then
  {
    echo "Note: cc-glm wrapper failed, falling back to claude headless mode"
  } | tee -a "$LOG_FILE" >&2

  if claude -p "$(cat "$tmp")" --output-format text 2>&1 | tee -a "$LOG_FILE"; then
    {
      echo ""
      echo "=== Session Complete ==="
      echo "Log: $LOG_FILE"
    } | tee -a "$LOG_FILE" >&2
    exit 0
  fi
fi

{
  echo ""
  echo "=== Session Failed ==="
  echo "Error: neither cc-glm nor claude is available on PATH"
  echo "Log: $LOG_FILE"
} | tee -a "$LOG_FILE" >&2
exit 1
