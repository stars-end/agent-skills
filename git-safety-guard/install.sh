#!/usr/bin/env bash
#
# install.sh
# Installs Claude Code hook to block destructive git/filesystem commands
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

# Write the guard script
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
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\$TMPDIR/",    # $TMPDIR/...
    r"rm\s+-[a-z]*r[a-z]*f[a-z]*\s+\\\${TMPDIR",   # ${TMPDIR}/... or ${TMPDIR:-...}
    r'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+"\$TMPDIR/',   # "$TMPDIR/..."
    r'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+"\\\${TMPDIR',  # "${TMPDIR}/..." or "${TMPDIR:-...}"
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

# Make executable
chmod +x "$INSTALL_DIR/hooks/git_safety_guard.py"
echo -e "${GREEN}✓${NC} Created $INSTALL_DIR/hooks/git_safety_guard.py"

# Handle settings.json - merge if exists, create if not
SETTINGS_FILE="$INSTALL_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if hooks.PreToolUse already exists
    if python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); exit(0 if 'hooks' in d and 'PreToolUse' in d['hooks'] else 1)" 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC}  $SETTINGS_FILE already has PreToolUse hooks configured."
        echo -e "    Please manually add this to your existing PreToolUse array:"
        echo ""
        echo '    {'
        echo '      "matcher": "Bash",'
        echo '      "hooks": ['
        echo '        {'
        echo '          "type": "command",'
        echo "          \"command\": \"$HOOK_PATH\""
        echo '        }'
        echo '      ]'
        echo '    }'
        echo ""
    else
        # Merge hooks into existing settings
        python3 << MERGE_SCRIPT
import json

with open("$SETTINGS_FILE", "r") as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

settings["hooks"]["PreToolUse"] = [
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

with open("$SETTINGS_FILE", "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
MERGE_SCRIPT
        echo -e "${GREEN}✓${NC} Updated $SETTINGS_FILE with hook configuration"
    fi
else
    # Create new settings.json
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

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "The following destructive commands are now blocked:"
echo "  • git checkout -- <files>"
echo "  • git restore <files>"
echo "  • git reset --hard"
echo "  • git clean -f"
echo "  • git push --force / -f"
echo "  • git branch -D"
echo "  • rm -rf (except /tmp, /var/tmp, \$TMPDIR)"
echo "  • git stash drop/clear"
echo ""
echo -e "${YELLOW}⚠  IMPORTANT: Restart Claude Code for the hook to take effect.${NC}"
echo ""

# Test the hook
echo "Testing hook..."
TEST_RESULT=$(echo '{"tool_name": "Bash", "tool_input": {"command": "git checkout -- test.txt"}}' | \
    python3 "$INSTALL_DIR/hooks/git_safety_guard.py" 2>/dev/null || true)

if echo "$TEST_RESULT" | grep -q "permissionDecision.*deny" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Hook test passed - destructive commands will be blocked"
else
    echo -e "${RED}✗${NC} Hook test failed - check Python installation"
    exit 1
fi
