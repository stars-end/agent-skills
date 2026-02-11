#!/usr/bin/env bash
set -euo pipefail

# generate-prompt.sh
#
# Strict prompt compiler for cc-glm delegation (DX V8.1 contract).
# Generates low-variance prompts for junior/mid delegates.
#
# Usage:
#   generate-prompt.sh --beads bd-xxxx --repo repo-name --task "..." [...]
#   generate-prompt.sh --config /path/to/config.yaml
#
# Output: /tmp/cc-glm-prompts/<beads-id>.prompt.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="8.1.0"

usage() {
  cat <<'EOF'
generate-prompt.sh v8.1.0 - Strict prompt compiler for cc-glm delegation

REQUIRED OPTIONS:
  --beads <id>           Beads issue ID (e.g., bd-3p27.2)
  --repo <name>           Repository name (e.g., agent-skills, prime-radiant-ai)
  --task <description>     Task description (1-5 bullets, use \n to separate)

SCOPE OPTIONS (at least one required):
  --scope-in <patterns>   Comma-separated in-scope file patterns (e.g., "src/**/*.ts")
  --scope-out <patterns>  Comma-separated out-of-scope areas (e.g., "tests,docs")
  --acceptance <criteria> Measurable acceptance criteria

WAVE OPTIONS (optional, for dependency-based delegation):
  --wave-id <id>         Wave identifier (e.g., wave-1, wave-2)
  --depends-on <ids>      Comma-separated Beads IDs this task depends on
  --wave-order <n>        Position within wave (1-indexed)

OUTPUT OPTIONS:
  --output <path>         Output prompt file (default: /tmp/cc-glm-prompts/<beads-id>.prompt.txt)
  --format <fmt>          Output format: txt (default) or json
  --stdout                Print to stdout instead of file

VALIDATION OPTIONS:
  --validate-cmds <cmds>  Comma-separated validation commands (e.g., "npm run lint,npm test")
  --auto-validate          Run template validation after generation

OTHER:
  --help, -h             Show this help
  --version               Show version

EXAMPLES:
  # Simple independent task
  generate-prompt.sh \\
    --beads bd-3p27.2 \\
    --repo agent-skills \\
    --scope-in "extended/cc-glm/docs/*" \\
    --scope-out "scripts,SKILL.md" \\
    --acceptance "Template document exists with all required sections" \\
    --task "Add strict prompt template specification" \\
    --validate-cmds "bash -n extended/cc-glm/scripts/*.sh"

  # Task with dependencies (wave-based)
  generate-prompt.sh \\
    --beads bd-3p28.1 \\
    --repo agent-skills \\
    --wave-id wave-2 \\
    --depends-on bd-3p27.2 \\
    --wave-order 1 \\
    --scope-in "extended/cc-glm/scripts/*" \\
    --scope-out "cc-glm-headless.sh,cc-glm-job.sh" \\
    --task "Create prompt compiler script" \\
    --validate-cmds "bash -n extended/cc-glm/scripts/*.sh"

  # Multi-bullet task
  generate-prompt.sh \\
    --beads bd-xxx \\
    --repo prime-radiant-ai \\
    --scope-in "backend/api/**/*.ts" \\
    --task "Add error handling to API client\n- Wrap fetch in try/catch\n- Add retry logic for 5xx\n- Log errors to stderr\n- Return typed errors\n- Update type definitions" \\
    --validate-cmds "npm run type-check,npm test"

NOTES:
  - Output prompt is ready for cc-glm-headless.sh or cc-glm-job.sh
  - Use --stdout to pipe directly: generate-prompt.sh ... | cc-glm-headless.sh
  - Wave-based tasks: execute in order of dependency satisfaction
EOF
}

version() {
  echo "generate-prompt.sh v${VERSION}"
  exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

BEADS=""
REPO=""
WORKTREE=""
TASK=""
SCOPE_IN=""
SCOPE_OUT=""
ACCEPTANCE=""
WAVE_ID=""
DEPENDS_ON=""
WAVE_ORDER=""
OUTPUT_FILE=""
OUTPUT_FORMAT="txt"
USE_STDOUT=false
AUTO_VALIDATE=false
VALIDATE_CMDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beads)
      BEADS="${2:-}"
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
    --task)
      TASK="${2:-}"
      shift 2
      ;;
    --scope-in)
      SCOPE_IN="${2:-}"
      shift 2
      ;;
    --scope-out)
      SCOPE_OUT="${2:-}"
      shift 2
      ;;
    --acceptance)
      ACCEPTANCE="${2:-}"
      shift 2
      ;;
    --wave-id)
      WAVE_ID="${2:-}"
      shift 2
      ;;
    --depends-on)
      DEPENDS_ON="${2:-}"
      shift 2
      ;;
    --wave-order)
      WAVE_ORDER="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --format)
      OUTPUT_FORMAT="${2:-}"
      shift 2
      ;;
    --stdout)
      USE_STDOUT=true
      shift
      ;;
    --auto-validate)
      AUTO_VALIDATE=true
      shift
      ;;
    --validate-cmds)
      VALIDATE_CMDS="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --version)
      version
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

# =============================================================================
# VALIDATION
# =============================================================================

validate_required() {
  local missing=()

  [[ -z "$BEADS" ]] && missing+=("--beads")
  [[ -z "$REPO" ]] && missing+=("--repo")
  [[ -z "$TASK" ]] && missing+=("--task")
  [[ -z "$SCOPE_IN" && -z "$SCOPE_OUT" ]] && missing+=("--scope-in or --scope-out")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing required options: ${missing[*]}" >&2
    echo "" >&2
    usage
    exit 2
  fi
}

validate_wave_fields() {
  # If any wave field is set, validate the set
  if [[ -n "$WAVE_ID" || -n "$DEPENDS_ON" || -n "$WAVE_ORDER" ]]; then
    # wave_order requires wave_id
    if [[ -n "$WAVE_ORDER" && -z "$WAVE_ID" ]]; then
      echo "Error: --wave-order requires --wave-id" >&2
      exit 2
    fi
    # depends_on without wave_id is allowed (simple dependency)
  fi

  # Validate wave_order is numeric
  if [[ -n "$WAVE_ORDER" && ! "$WAVE_ORDER" =~ ^[0-9]+$ ]]; then
    echo "Error: --wave-order must be a positive integer" >&2
    exit 2
  fi
}

validate_beads_format() {
  if [[ ! "$BEADS" =~ ^bd-[a-z0-9]+(\.[0-9]+)?$ ]]; then
    echo "Warning: Beads ID format looks non-standard: '$BEADS'" >&2
    echo "  Expected format: bd-xxxx or bd-xxxx.n" >&2
  fi
}

validate_required
validate_wave_fields
validate_beads_format

# Derive worktree if not provided
if [[ -z "$WORKTREE" ]]; then
  WORKTREE="/tmp/agents/$BEADS/$REPO"
fi

# Set default output file
if [[ -z "$OUTPUT_FILE" && "$USE_STDOUT" == false ]]; then
  OUTPUT_DIR="/tmp/cc-glm-prompts"
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/$BEADS.prompt.txt"
fi

# =============================================================================
# TEMPLATE GENERATION
# =============================================================================

escape_task_bullet() {
  local bullet="$1"
  # Remove leading dash if present
  bullet="${bullet#-}"
  # Trim leading whitespace
  bullet="${bullet#"${bullet%%[![:space:]]*}"}"
  echo "$bullet"
}

generate_prompt() {
  cat <<EOF
Beads: $BEADS
Repo: $REPO
Worktree: $WORKTREE
Agent: cc-glm-headless

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common})
- Do NOT run git commit, git push, or open PRs
- Do NOT print secrets, dotfiles, or config files
- Output must be reviewable: diff + validation + risks

Scope:
EOF

  # Add in-scope
  if [[ -n "$SCOPE_IN" ]]; then
    echo "- In-scope: $SCOPE_IN"
  else
    echo "- In-scope: [derived from task]"
  fi

  # Add out-of-scope
  if [[ -n "$SCOPE_OUT" ]]; then
    echo "- Out-of-scope: $SCOPE_OUT"
  else
    echo "- Out-of-scope: [none specified]"
  fi

  # Add acceptance
  if [[ -n "$ACCEPTANCE" ]]; then
    echo "- Acceptance: $ACCEPTANCE"
  else
    echo "- Acceptance: [measurable completion criteria]"
  fi

  # Add wave fields if present
  if [[ -n "$WAVE_ID" || -n "$DEPENDS_ON" || -n "$WAVE_ORDER" ]]; then
    echo ""
    echo "Dependency context:"
    [[ -n "$DEPENDS_ON" ]] && echo "- depends_on: [$DEPENDS_ON]"
    [[ -n "$WAVE_ID" ]] && echo "- wave_id: $WAVE_ID"
    [[ -n "$WAVE_ORDER" ]] && echo "- wave_order: $WAVE_ORDER"
  fi

  # Add task section
  echo ""
  echo "Task:"
  # Handle multi-line task (separated by \n)
  if [[ "$TASK" == *$'\n'* ]]; then
    echo "$TASK" | while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        echo "- $line"
      fi
    done
  else
    # Single bullet or multi-bullet on one line
    if [[ "$TASK" == *";"* ]]; then
      # Semicolon-separated bullets
      IFS=';' read -ra BULLETS <<< "$TASK"
      for bullet in "${BULLETS[@]}"; do
        echo "- $(escape_task_bullet "$bullet")"
      done
    else
      # Single task
      echo "- $TASK"
    fi
  fi

  # Add validation commands if provided
  local validation_section=""
  if [[ -n "$VALIDATE_CMDS" ]]; then
    validation_section="- Validation: ${VALIDATE_CMDS//,/, }"
  else
    validation_section="- Validation: [commands to verify correctness]"
  fi

  # Add expected outputs
  echo ""
  echo "Expected outputs:"
  echo "- Files changed: [list of modified files]"
  echo "- Diff: [unified diff or patch]"
  echo "$validation_section"
  echo "- Risks: [edge cases, gaps, follow-ups]"

  # Add dependency note if applicable
  if [[ -n "$DEPENDS_ON" ]]; then
    echo ""
    echo "Note: This task depends on output from: $DEPENDS_ON"
    echo "      Verify those tasks are complete before starting."
  fi
}

generate_json() {
  # JSON format for programmatic consumption
  local json_deps="null"
  if [[ -n "$DEPENDS_ON" ]]; then
    # Convert comma-separated to JSON array
    IFS=',' read -ra DEPS <<< "$DEPENDS_ON"
    json_deps="["
    local first=true
    for dep in "${DEPS[@]}"; do
      dep="$(echo "$dep" | xargs)" # trim
      if [[ "$first" == true ]]; then
        json_deps+="\"$dep\""
        first=false
      else
        json_deps+=", \"$dep\""
      fi
    done
    json_deps+="]"
  fi

  cat <<EOF
{
  "version": "$VERSION",
  "beads": "$BEADS",
  "repo": "$REPO",
  "worktree": "$WORKTREE",
  "agent": "cc-glm-headless",
  "constraints": [
    "worktree_only",
    "no_commit_push_pr",
    "no_secrets_dotfiles",
    "reviewable_output"
  ],
  "scope": {
    "in": "$SCOPE_IN",
    "out": "$SCOPE_OUT",
    "acceptance": "$ACCEPTANCE"
  },
  "task": "$TASK",
  "wave": {
    "id": ${WAVE_ID:+\"$WAVE_ID\"},
    "depends_on": $json_deps,
    "order": ${WAVE_ORDER:-null}
  },
  "validation": {
    "commands": "$VALIDATE_CMDS"
  },
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# =============================================================================
# OUTPUT
# =============================================================================

main() {
  local content

  case "$OUTPUT_FORMAT" in
    txt)
      content="$(generate_prompt)"
      ;;
    json)
      content="$(generate_json)"
      ;;
    *)
      echo "Error: unsupported format '$OUTPUT_FORMAT'" >&2
      exit 2
      ;;
  esac

  if [[ "$USE_STDOUT" == true ]]; then
    echo "$content"
  else
    echo "$content" > "$OUTPUT_FILE"
    echo "Prompt written to: $OUTPUT_FILE" >&2
    echo "  Beads: $BEADS" >&2
    echo "  Repo: $REPO" >&2
    echo "  Worktree: $WORKTREE" >&2

    # Show wave info if present
    if [[ -n "$WAVE_ID" || -n "$DEPENDS_ON" ]]; then
      echo "  Wave: ${WAVE_ID:-independent}" >&2
      echo "  Depends on: ${DEPENDS_ON:-none}" >&2
    fi
  fi

  # Auto-validate if requested
  if [[ "$AUTO_VALIDATE" == true ]]; then
    echo "" >&2
    echo "Running validation..." >&2

    local validation_errors=0

    # Check required fields in output
    if ! echo "$content" | grep -q "^Beads:"; then
      echo "  ✗ Missing: Beads field" >&2
      ((validation_errors++))
    fi
    if ! echo "$content" | grep -q "^Repo:"; then
      echo "  ✗ Missing: Repo field" >&2
      ((validation_errors++))
    fi
    if ! echo "$content" | grep -q "^Worktree:"; then
      echo "  ✗ Missing: Worktree field" >&2
      ((validation_errors++))
    fi
    if ! echo "$content" | grep -q "^Agent:"; then
      echo "  ✗ Missing: Agent field" >&2
      ((validation_errors++))
    fi

    # Check constraints section
    if ! echo "$content" | grep -q "Hard constraints:"; then
      echo "  ✗ Missing: Hard constraints section" >&2
      ((validation_errors++))
    fi

    # Check scope section
    if ! echo "$content" | grep -q "Scope:"; then
      echo "  ✗ Missing: Scope section" >&2
      ((validation_errors++))
    fi

    # Check task section
    if ! echo "$content" | grep -q "^Task:"; then
      echo "  ✗ Missing: Task section" >&2
      ((validation_errors++))
    fi

    # Check expected outputs
    if ! echo "$content" | grep -q "Expected outputs:"; then
      echo "  ✗ Missing: Expected outputs section" >&2
      ((validation_errors++))
    fi

    if [[ $validation_errors -eq 0 ]]; then
      echo "  ✓ Template validation passed" >&2
    else
      echo "  ✗ Template validation failed: $validation_errors error(s)" >&2
      exit 1
    fi
  fi
}

main
