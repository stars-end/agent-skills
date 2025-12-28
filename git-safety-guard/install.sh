#!/usr/bin/env bash
#
# install.sh
# Installs Claude Code hook to block destructive git/filesystem commands
# and a pre-push hook to enforce ci-lite.
#
# Usage:
#   ./install.sh          # Install in current project (.claude/)
#   ./install.sh --global # Install globally (~/.claude/)
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

# Create directories
mkdir -p "$INSTALL_DIR/hooks"

# --- 1. Write the guard script (Claude Hook) ---
# We use a python script for the main guard logic
GUARD_SCRIPT="$INSTALL_DIR/hooks/git_safety_guard.py"
cat > "$GUARD_SCRIPT" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
Git/filesystem safety guard for Claude Code.
Blocks destructive commands that can lose uncommitted work or delete files.
"""
import json
import re
import sys

# Destructive patterns to block - tuple of (regex, reason)
DESTRUCTIVE_PATTERNS = [
    (r"git\s+checkout\s+--\s+", "git checkout -- discards uncommitted changes permanently. Use 'git stash' first."),
    (r"git\s+checkout\s+(?!-b\b)(?!--orphan\b)[^\s]+\s+--\s+", "git checkout <ref> -- <path> overwrites working tree."),
    (r"git\s+restore\s+(?!--staged\b)[^\s]*\s*$", "git restore discards uncommitted changes."),
    (r"git\s+restore\s+--worktree", "git restore --worktree discards uncommitted changes permanently."),
    (r"git\s+reset\s+--hard", "git reset --hard destroys uncommitted changes. Use 'git stash' first."),
    (r"git\s+clean\s+-[a-z]*f", "git clean -f removes untracked files permanently."),
    (r"git\s+push\s+.*--force(?!-with-lease)", "Force push can destroy remote history. Use --force-with-lease."),
    (r"git\s+push\s+-f\b", "Force push (-f) can destroy remote history."),
    (r"rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r", "rm -rf is destructive. List files first."),
    (r"git\s+stash\s+drop", "git stash drop permanently deletes stashed changes."),
    (r"git\s+stash\s+clear", "git stash clear permanently deletes ALL stashed changes."),
]

SAFE_PATTERNS = [
    r"git\s+checkout\s+-b\s+",
    r"git\s+checkout\s+--orphan\s+",
    r"git\s+restore\s+--staged\s+",
    r"git\s+clean\s+-n",
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+/tmp/",
]

def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    if tool_name != "Bash" or not command:
        sys.exit(0)

    for pattern in SAFE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            sys.exit(0)

    for pattern, reason in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"BLOCKED: {reason}\nCommand: {command}"
                }
            }
            print(json.dumps(output))
            sys.exit(0)
    sys.exit(0)

if __name__ == "__main__":
    main()
PYTHON_SCRIPT
chmod +x "$GUARD_SCRIPT"

# --- 2. Write the hooks (The Physics) ---

# 2.1 Pre-push: Enforce ci-lite
PRE_PUSH="$INSTALL_DIR/hooks/pre-push"
echo '#!/bin/bash' > "$PRE_PUSH"
echo 'if [ -f Makefile ] && grep -q "ci-lite:" Makefile; then' >> "$PRE_PUSH"
echo '    echo "🧪 Running make ci-lite before push..."' >> "$PRE_PUSH"
echo '    if ! make ci-lite; then' >> "$PRE_PUSH"
echo '        echo "❌ PUSH BLOCKED: CI-Lite failed."' >> "$PRE_PUSH"
echo '        echo "🚨 Fix errors before pushing or use --no-verify."' >> "$PRE_PUSH"
echo '        exit 1' >> "$PRE_PUSH"
echo '    fi' >> "$PRE_PUSH"
echo 'fi' >> "$PRE_PUSH"
echo 'exit 0' >> "$PRE_PUSH"

# 2.2 State Recovery
STATE_REC="$INSTALL_DIR/hooks/state-recovery"
echo '#!/bin/bash' > "$STATE_REC"
echo 'echo "🔄 [dx-hooks] Checking environment integrity..."' >> "$STATE_REC"
echo '[ -f .beads/issues.jsonl ] && command -v bd &> /dev/null && bd import --no-auto-sync 2>/dev/null || true' >> "$STATE_REC"
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

# 2.3 Permission Sentinel
PERM_SENTINEL="$INSTALL_DIR/hooks/permission-sentinel"
echo '#!/bin/bash' > "$PERM_SENTINEL"
echo "git diff --cached --name-only --diff-filter=ACM | grep -E '\\.(sh|py)$' | xargs -I {} chmod +x {} 2>/dev/null || true" >> "$PERM_SENTINEL"
echo 'git add . 2>/dev/null || true' >> "$PERM_SENTINEL"
echo 'exit 0' >> "$PERM_SENTINEL"

chmod +x "$INSTALL_DIR/hooks/"*
echo -e "${GREEN}✓${NC} Installed hooks to $INSTALL_DIR/hooks/"

# --- 3. Handle settings.json (Claude Integration) ---
SETTINGS_FILE="$INSTALL_DIR/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "${YELLOW}⚠${NC} $SETTINGS_FILE exists. Verify hook config manually."
else
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

# --- 4. Install Native Git Hooks (if project local) ---
if [[ "$INSTALL_TYPE" == "project" ]]; then

    mkdir -p .git/hooks

    ln -sf"../../.claude/hooks/pre-push" .git/hooks/pre-push

    ln -sf"../../.claude/hooks/state-recovery" .git/hooks/post-merge

    ln -sf"../../.claude/hooks/state-recovery" .git/hooks/post-checkout

    ln -sf"../../.claude/hooks/permission-sentinel" .git/hooks/pre-commit

    echo -e "${GREEN}✓${NC} Linked hooks to .git/hooks/"

fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"

echo ""
echo "Enforced via Claude Hooks & Native Git Hooks:"
echo "  • Destructive commands (git checkout --, rm -rf) are BLOCKED."
echo "  • Pushes are BLOCKED if 'make ci-lite' fails."

echo -e "${YELLOW}⚠ IMPORTANT: Restart Claude Code for tool changes to take effect.${NC}"

