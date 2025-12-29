#!/usr/bin/env bash
#
# install.sh
# Installs Claude Code hook to block destructive git/filesystem commands
# and a pre-push hook to enforce ci-lite.
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine installation location
if [[ "${1:-}" == "--global" ]]; then
    INSTALL_DIR="$HOME/.claude"
    HOOK_PATH="\$HOME/.claude/hooks/git_safety_guard.py"
    INSTALL_TYPE="global"
    echo -e "${BLUE}Installing globally to ~/.claude/${NC}"
else
    INSTALL_DIR=".claude"
    HOOK_PATH="\$CLAUDE_PROJECT_DIR/.claude/hooks/git_safety_guard.py"
    INSTALL_TYPE="project"
    echo -e "${BLUE}Installing to current project (.claude/)${NC}"
fi

mkdir -p "$INSTALL_DIR/hooks"

# Helper: Write file only if not tracked by git (in project mode)
safe_write() {
    local target="$1"
    local content="$2"
    
    if [[ "$INSTALL_TYPE" == "project" ]]; then
        # Check if file is tracked
        if git ls-files --error-unmatch "$target" >/dev/null 2>&1; then
            echo -e "${YELLOW}ℹ  Skipping tracked file: $target${NC}"
            return
        fi
    fi
    
    echo "$content" > "$target"
    echo -e "${GREEN}✓${NC} Wrote $target"
}

# --- 1. Python Safety Guard ---
GUARD_SCRIPT="$INSTALL_DIR/hooks/git_safety_guard.py"
GUARD_CONTENT='#!/usr/bin/env python3
import json
import re
import sys

# Destructive patterns
DESTRUCTIVE_PATTERNS = [
    (r"git\s+checkout\s+--\s+", "git checkout -- discards changes."),
    (r"git\s+reset\s+--hard", "git reset --hard destroys changes."),
    (r"git\s+clean\s+-[a-z]*f", "git clean -f deletes files."),
    (r"rm\s+-[a-z]*r[a-z]*f", "rm -rf is destructive."),
]

def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)
    
    command = input_data.get("tool_input", {}).get("command", "")
    if input_data.get("tool_name") != "Bash" or not command:
        sys.exit(0)

    for pattern, reason in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"BLOCKED: {reason}\nCommand: {command}"
                }
            }))
            sys.exit(0)
    sys.exit(0)

if __name__ == "__main__":
    main()
'
safe_write "$GUARD_SCRIPT" "$GUARD_CONTENT"
chmod +x "$GUARD_SCRIPT"

# --- 2. Git Hooks ---

# 2.1 Pre-push
PRE_PUSH="$INSTALL_DIR/hooks/pre-push"
PRE_PUSH_CONTENT='#!/bin/bash
if [ -f Makefile ] && grep -q "ci-lite:" Makefile; then
    echo "🧪 Running make ci-lite..."
    if ! make ci-lite; then
        echo "❌ PUSH BLOCKED: CI-Lite failed."
        exit 1
    fi
fi
exit 0'
safe_write "$PRE_PUSH" "$PRE_PUSH_CONTENT"
chmod +x "$PRE_PUSH"

# 2.2 State Recovery
STATE_REC="$INSTALL_DIR/hooks/state-recovery"
STATE_REC_CONTENT='#!/bin/bash
echo "🔄 [dx-hooks] Checking environment integrity..."
if [ -f .beads/issues.jsonl ] && command -v bd &> /dev/null; then
    bd import 2>/dev/null || true
fi
if [ -f pnpm-lock.yaml ] && command -v pnpm &> /dev/null; then
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "pnpm-lock.yaml"; then
        echo "🔄 [dx] pnpm-lock changed. Installing..."
        pnpm install --frozen-lockfile >/dev/null 2>&1 || echo "⚠️ pnpm install failed."
    fi
fi
if [ -f .gitmodules ]; then
    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "packages/llm-common"; then
        echo "🔄 [dx] Submodules changed. Updating..."
        git submodule update --init --recursive >/dev/null 2>&1 || true
    fi
fi
exit 0'
safe_write "$STATE_REC" "$STATE_REC_CONTENT"
chmod +x "$STATE_REC"

# 2.3 Permission Sentinel
PERM_SENTINEL="$INSTALL_DIR/hooks/permission-sentinel"
PERM_SENTINEL_CONTENT='#!/bin/bash
# Only target scripts/ and bin/ directories
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E "^(scripts|bin)/.*\.(sh|py)$")
if [ -n "$FILES" ]; then
    for file in $FILES; do
        if head -n 1 "$file" | grep -q "^#!" 2>/dev/null; then
            chmod +x "$file"
            git add "$file"
        fi
    done
fi
exit 0'
safe_write "$PERM_SENTINEL" "$PERM_SENTINEL_CONTENT"
chmod +x "$PERM_SENTINEL"

# --- 3. Settings JSON ---
SETTINGS_FILE="$INSTALL_DIR/settings.json"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    SETTINGS_CONTENT='{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "'$HOOK_PATH'"
          }
        ]
      }
    ]
  }
}'
    safe_write "$SETTINGS_FILE" "$SETTINGS_CONTENT"
fi

# --- 4. Native Links ---
if [[ "$INSTALL_TYPE" == "project" ]]; then
    mkdir -p .git/hooks
    ln -sf "../../.claude/hooks/pre-push" .git/hooks/pre-push
    ln -sf "../../.claude/hooks/state-recovery" .git/hooks/post-merge
    ln -sf "../../.claude/hooks/state-recovery" .git/hooks/post-checkout
    ln -sf "../../.claude/hooks/permission-sentinel" .git/hooks/pre-commit
    echo -e "${GREEN}✓${NC} Linked hooks to .git/hooks/"
fi
