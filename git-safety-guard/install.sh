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

# --- 1. Python Safety Guard ---
GUARD_SCRIPT="$INSTALL_DIR/hooks/git_safety_guard.py"
cat > "$GUARD_SCRIPT" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
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
PYTHON_SCRIPT
chmod +x "$GUARD_SCRIPT"

# --- 2. Git Hooks ---

# 2.1 Pre-push: Enforce ci-lite
PRE_PUSH="$INSTALL_DIR/hooks/pre-push"
echo '#!/bin/bash' > "$PRE_PUSH"
echo 'if [ -f Makefile ] && grep -q "ci-lite:" Makefile; then' >> "$PRE_PUSH"
echo '    echo "🧪 Running make ci-lite..."' >> "$PRE_PUSH"
echo '    if ! make ci-lite; then' >> "$PRE_PUSH"
echo '        echo "❌ PUSH BLOCKED: CI-Lite failed."' >> "$PRE_PUSH"
echo '        exit 1' >> "$PRE_PUSH"
echo '    fi' >> "$PRE_PUSH"
echo 'fi' >> "$PRE_PUSH"
echo 'exit 0' >> "$PRE_PUSH"

# 2.2 State Recovery (Safe Version)
STATE_REC="$INSTALL_DIR/hooks/state-recovery"
echo '#!/bin/bash' > "$STATE_REC"
echo 'echo "🔄 [dx-hooks] Checking environment integrity..."' >> "$STATE_REC"
echo 'if [ -f .beads/issues.jsonl ] && command -v bd &> /dev/null; then' >> "$STATE_REC"
# Attempt import, ignore errors if db locked
echo '    bd import 2>/dev/null || true' >> "$STATE_REC"
echo 'fi' >> "$STATE_REC"
echo 'if [ -f pnpm-lock.yaml ] && command -v pnpm &> /dev/null; then' >> "$STATE_REC"
echo '    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "pnpm-lock.yaml"; then' >> "$STATE_REC"
echo '        echo "🔄 [dx] pnpm-lock changed. Installing..."' >> "$STATE_REC"
echo '        pnpm install --frozen-lockfile >/dev/null 2>&1 || echo "⚠️ pnpm install failed."' >> "$STATE_REC"
echo '    fi' >> "$STATE_REC"
echo 'fi' >> "$STATE_REC"
echo 'if [ -f .gitmodules ]; then' >> "$STATE_REC"
echo '    if git diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q "packages/llm-common"; then' >> "$STATE_REC"
echo '        echo "🔄 [dx] Submodules changed. Updating..."' >> "$STATE_REC"
echo '        git submodule update --init --recursive >/dev/null 2>&1 || true' >> "$STATE_REC"
echo '    fi' >> "$STATE_REC"
echo 'fi' >> "$STATE_REC"
echo 'exit 0' >> "$STATE_REC"

# 2.3 Permission Sentinel (Safe Version)
PERM_SENTINEL="$INSTALL_DIR/hooks/permission-sentinel"
echo '#!/bin/bash' > "$PERM_SENTINEL"
# Only target scripts/ and bin/ directories
echo '# Only target scripts/ and bin/ directories' >> "$PERM_SENTINEL"

FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E "^(scripts|bin)/.*\.(sh|py)$")
echo 'if [ -n "$FILES" ]; then' >> "$PERM_SENTINEL"
echo '    echo "$FILES" | xargs -I {} chmod +x {}' >> "$PERM_SENTINEL"
    # Only re-add the specific files we changed
    echo '    # Only re-add the specific files we changed' >> "$PERM_SENTINEL"
    echo '    echo "$FILES" | xargs git add' >> "$PERM_SENTINEL"
fi' >> "$PERM_SENTINEL"
echo 'exit 0' >> "$PERM_SENTINEL"

chmod +x "$INSTALL_DIR/hooks/"*
echo -e "${GREEN}✓${NC} Installed hooks to $INSTALL_DIR/hooks/"

# --- 3. Settings JSON ---
SETTINGS_FILE="$INSTALL_DIR/settings.json"
if [[ ! -f "$SETTINGS_FILE" ]]; then
    cat > "$SETTINGS_FILE" << SETTINGS_JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH"
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
    echo -e "${GREEN}✓${NC} Created $SETTINGS_FILE"
fi

# --- 4. Native Links ---
if [[ "$INSTALL_TYPE" == "project" ]]; then
    mkdir -p .git/hooks
    ln -sf"../../.claude/hooks/pre-push" .git/hooks/pre-push
    ln -sf"../../.claude/hooks/state-recovery" .git/hooks/post-merge
    ln -sf"../../.claude/hooks/state-recovery" .git/hooks/post-checkout
    ln -sf"../../.claude/hooks/permission-sentinel" .git/hooks/pre-commit
    echo -e "${GREEN}✓${NC} Linked hooks to .git/hooks/"
fi
