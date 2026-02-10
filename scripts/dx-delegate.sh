#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
dx-delegate.sh

Run a delegated "junior dev" task via cc-glm in headless mode with DX V8.1 guardrails.

This script:
- Hard-stops if invoked from a canonical clone cwd
- Requires a Beads id + repo name
- Ensures the target worktree exists at /tmp/agents/<beads-id>/<repo>
- Injects DX V8.1 constraints into the prompt
- Runs cc-glm headlessly and logs output under /tmp/dx-delegate/<beads-id>/

Usage:
  dx-delegate.sh --beads bd-xxxx --repo repo-name --prompt "..."
  dx-delegate.sh --beads bd-xxxx --repo repo-name --prompt-file /path/to/prompt.txt

Notes:
  - This does NOT create worktrees. If missing, it prints the dx-worktree command to run.
  - This does NOT run git commit/push. The delegate must return a diff + validation commands.
  - Auth is expected via environment (preferred): CC_GLM_AUTH_TOKEN, or ZAI_API_KEY (plain or op:// reference).
EOF
}

BEADS_ID=""
REPO_NAME=""
PROMPT=""
PROMPT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beads) BEADS_ID="${2:-}"; shift 2 ;;
    --repo) REPO_NAME="${2:-}"; shift 2 ;;
    --prompt) PROMPT="${2:-}"; shift 2 ;;
    --prompt-file) PROMPT_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$BEADS_ID" || -z "$REPO_NAME" ]]; then
  echo "Error: --beads and --repo are required" >&2
  usage
  exit 2
fi

if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: --prompt-file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

if [[ -z "$PROMPT" ]]; then
  echo "Error: missing prompt (use --prompt or --prompt-file)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Canonical hard-stop (symlink-safe).
if [[ -x "$AGENTS_ROOT/scripts/lib/canonical-detect.sh" ]]; then
  # shellcheck disable=SC1090
  source "$AGENTS_ROOT/scripts/lib/canonical-detect.sh"
  if _dx_is_canonical_cwd_fast; then
    echo "" >&2
    echo "❌ CANNOT DELEGATE: you are in a CANONICAL repository cwd" >&2
    echo "   CWD: $(pwd -P)" >&2
    echo "" >&2
    echo "Fix:" >&2
    echo "  dx-worktree create $BEADS_ID $REPO_NAME" >&2
    echo "  cd /tmp/agents/$BEADS_ID/$REPO_NAME" >&2
    exit 1
  fi
fi

WORKTREE_DIR="/tmp/agents/$BEADS_ID/$REPO_NAME"
if [[ ! -d "$WORKTREE_DIR" ]]; then
  echo "❌ Missing worktree: $WORKTREE_DIR" >&2
  echo "Fix:" >&2
  echo "  dx-worktree create $BEADS_ID $REPO_NAME" >&2
  echo "  cd $WORKTREE_DIR" >&2
  exit 1
fi

if [[ ! -d "$WORKTREE_DIR/.git" && ! -f "$WORKTREE_DIR/.git" ]]; then
  echo "❌ Not a git repo: $WORKTREE_DIR" >&2
  exit 1
fi

LOG_ROOT="/tmp/dx-delegate/$BEADS_ID"
mkdir -p "$LOG_ROOT"
TS="$(date '+%Y%m%d-%H%M%S')"
LOG_DIR="$LOG_ROOT/$TS"
mkdir -p "$LOG_DIR"

INJECTED_PROMPT_FILE="$LOG_DIR/prompt.txt"
OUT_FILE="$LOG_DIR/output.txt"

cat > "$INJECTED_PROMPT_FILE" <<EOF
You are cc-glm (a junior/mid dev agent) running in headless mode.

Beads: $BEADS_ID
Repo: $REPO_NAME
Worktree: $WORKTREE_DIR
Agent: cc-glm

DX V8.1 invariants (must follow):
- Work ONLY inside the worktree path above. Never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}.
- Do NOT run git commit/push, do NOT open PRs.
- If changes are needed: output a unified diff patch. Keep it minimal. Include file paths.
- Provide validation commands to run (tests/lint). If you didn’t run them, say so.
- Never print dotfiles or configs (tokens/secrets). Do not dump ~/.zshrc or similar.

Task:
1) cd into the worktree
2) perform the requested work
3) return: (a) patch diff (b) validation commands (c) brief risk notes

User request:
${PROMPT}
EOF

echo "Delegating to cc-glm..." >&2
echo "  worktree: $WORKTREE_DIR" >&2
echo "  log dir:  $LOG_DIR" >&2

WRAPPER="$AGENTS_ROOT/extended/cc-glm/scripts/cc-glm-headless.sh"
if [[ ! -x "$WRAPPER" ]]; then
  echo "Error: missing wrapper: $WRAPPER" >&2
  exit 1
fi

set +e
"$WRAPPER" --prompt-file "$INJECTED_PROMPT_FILE" >"$OUT_FILE" 2>&1
rc=$?
set -e

cat "$OUT_FILE"
exit $rc
