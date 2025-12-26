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
cat > "$INSTALL_DIR/hooks/git_safety_guard.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
Git/filesystem safety guard for Claude Code.

Blocks destructive commands that can lose uncommitted work or delete files.
This hook runs before Bash commands execute and can deny dangerous operations.

Exit behavior:
  - Exit 0 with JSON {"hookSpecificOutput": {"permissionDecision": "deny", ...}} = block
  - Exit 0 with no output = allow
"""
import json
import re
import sys

# Destructive patterns to block - tuple of (regex, reason)
DESTRUCTIVE_PATTERNS = [
    # Git commands that discard uncommitted changes
    (
        r"git\s+checkout\s+--\s+",
        "git checkout -- discards uncommitted changes permanently. Use 'git stash' first."
    ),
    (
        r"git\s+checkout\s+(?!-b\b)(?!--orphan\b)[^\s]+\s+--\s+",
        "git checkout <ref> -- <path> overwrites working tree. Use 'git stash' first."
    ),
    (
        r"git\s+restore\s+(?!--staged\b)[^\s]*\s*$",
        "git restore discards uncommitted changes. Use 'git stash' or 'git diff' first."
    ),
    (
        r"git\s+restore\s+--worktree",
        "git restore --worktree discards uncommitted changes permanently."
    ),
    # Git reset variants
    (
        r"git\s+reset\s+--hard",
        "git reset --hard destroys uncommitted changes. Use 'git stash' first."
    ),
    (
        r"git\s+reset\s+--merge",
        "git reset --merge can lose uncommitted changes."
    ),
    # Git clean
    (
        r"git\s+clean\s+-[a-z]*f",
        "git clean -f removes untracked files permanently. Review with 'git clean -n' first."
    ),
    # Force operations
    (
        r"git\s+push\s+.*--force(?!-with-lease)",
        "Force push can destroy remote history. Use --force-with-lease if necessary."
    ),
    (
        r"git\s+push\s+-f\b",
        "Force push (-f) can destroy remote history. Use --force-with-lease if necessary."
    ),
    (
        r"git\s+branch\s+-D\b",
        "git branch -D force-deletes without merge check. Use -d for safety."
    ),
    # Destructive filesystem commands
    (
        r"rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r",
        "rm -rf is destructive. List files first, then delete individually with permission."
    ),
    (
        r"rm\s+-rf\s+[/~]",
        "rm -rf on root or home paths is extremely dangerous."
    ),
    # Git stash drop/clear without explicit permission
    (
        r"git\s+stash\s+drop",
        "git stash drop permanently deletes stashed changes. List stashes first."
    ),
    (
        r"git\s+stash\s+clear",
        "git stash clear permanently deletes ALL stashed changes."
    ),
]

# Patterns that are safe even if they match above (allowlist)
SAFE_PATTERNS = [
    r"git\s+checkout\s+-b\s+",           # Creating new branch
    r"git\s+checkout\s+--orphan\s+",     # Creating orphan branch
    r"git\s+restore\s+--staged\s+",      # Unstaging (safe)
    r"git\s+clean\s+-n",                 # Dry run
    r"git\s+clean\s+--dry-run",          # Dry run
    # Allow rm -rf on temp directories (these are designed for ephemeral data)
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+/tmp/",        # /tmp/...
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+/var/tmp/",    # /var/tmp/...
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\\$TMPDIR/",    # $TMPDIR/...
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\\\\\${TMPDIR",   # ${TMPDIR}/... or ${TMPDIR:-...}
    r'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\"$TMPDIR/",   # "$TMPDIR/..."
    r'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\\\"\\\\\${TMPDIR',  # "${TMPDIR}/..." or "${TMPDIR:-...}"
]


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Can't parse input, allow by default
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    # Only check Bash commands
    if tool_name != "Bash" or not command:
        sys.exit(0)

    # Check if command matches any safe pattern first
    for pattern in SAFE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            sys.exit(0)

    # Check if command matches any destructive pattern
    for pattern, reason in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"BLOCKED by git_safety_guard.py\n\n"
                        f"Reason: {reason}\n\n"
                        f"Command: {command}\n\n"
                        f"If this operation is truly needed, ask the user for explicit "
                        f"permission and have them run the command manually."
                    )
                }
            }
            print(json.dumps(output))
            sys.exit(0)

    # Allow all other commands
    sys.exit(0)


if __name__ == "__main__":
    main()
PYTHON_SCRIPT

chmod +x "$INSTALL_DIR/hooks/git_safety_guard.py"
echo -e "${GREEN}✓${NC} Created $INSTALL_DIR/hooks/git_safety_guard.py"

# --- 2. Write the pre-push hook (The Physics) ---
# This hook runs 'make ci-lite' before any push.
cat > "$INSTALL_DIR/hooks/pre-push" << 'HOOK_SCRIPT'
#!/bin/bash
# pre-push hook enforced by agent-skills
# Runs ci-lite before code leaves the machine.

if [ -f Makefile ]; then
    if grep -q "ci-lite:" Makefile;
    then
        echo "🧪 Running 'make ci-lite' before push..."
        if ! make ci-lite;
        then
            echo "❌ PUSH BLOCKED: CI-Lite failed."
            echo "🚨 Fix errors before pushing or use --no-verify (not recommended)."
            exit 1
        fi
        echo "✅ CI-Lite passed."
    fi
fi
exit 0
HOOK_SCRIPT

chmod +x "$INSTALL_DIR/hooks/pre-push"
echo -e "${GREEN}✓${NC} Created $INSTALL_DIR/hooks/pre-push"

# --- 3. Handle settings.json (Claude Integration) ---
SETTINGS_FILE="$INSTALL_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    if python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); exit(0 if 'hooks' in d and 'PreToolUse' in d['hooks'] else 1)" 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} $SETTINGS_FILE already has PreToolUse hooks. Add $HOOK_PATH manually."
    else
        python3 << MERGE_SCRIPT
import json
with open("$SETTINGS_FILE", "r") as f: settings = json.load(f)
if "hooks" not in settings: settings["hooks"] = {}
settings["hooks"]["PreToolUse"] = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOOK_PATH"}]}]
with open("$SETTINGS_FILE", "w") as f: json.dump(settings, f, indent=2); f.write("\n")
MERGE_SCRIPT
        echo -e "${GREEN}✓${NC} Updated $SETTINGS_FILE"
    fi
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
    ln -sf "../../.claude/hooks/pre-push" .git/hooks/pre-push
    echo -e "${GREEN}✓${NC} Linked pre-push hook to .git/hooks/"
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
echo ""
echo -e "${YELLOW}⚠ IMPORTANT: Restart Claude Code for tool changes to take effect.${NC}"
echo ""