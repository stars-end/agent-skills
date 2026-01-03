#!/bin/bash
# slack-mcp-setup.sh
# Configures Slack MCP server for Claude Code agents.
# Part of the dx-hydrate flow.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${GREEN}🔌 Setting up Slack MCP Server...${RESET}"

# Check for required env vars
if [ -z "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  SLACK_MCP_XOXP_TOKEN not set. Skipping Slack MCP setup.${RESET}"
    echo "   To enable, add to ~/.zshrc:"
    echo '   export SLACK_MCP_XOXP_TOKEN="xoxp-..."'
    echo '   export SLACK_MCP_ADD_MESSAGE_TOOL=true'
    exit 0
fi

CLAUDE_CONFIG="$HOME/.claude.json"

# Check if claude.json exists
if [ ! -f "$CLAUDE_CONFIG" ]; then
    echo -e "${YELLOW}⚠️  ~/.claude.json not found. Ensure Claude Code is installed.${RESET}"
    exit 0
fi

# Check if slack MCP is already configured
if grep -q '"slack":' "$CLAUDE_CONFIG"; then
    echo -e "${GREEN}✓ Slack MCP server already configured.${RESET}"
else
    echo "   Adding slack-mcp-server to ~/.claude.json..."
    python3 << 'PYEOF'
import json
import os

config_path = os.path.expanduser("~/.claude.json")
with open(config_path, "r") as f:
    data = json.load(f)

# Ensure mcpServers exists
if "mcpServers" not in data:
    data["mcpServers"] = {}

# Add slack MCP server (use env var reference)
data["mcpServers"]["slack"] = {
    "command": "npx",
    "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"],
    "env": {
        "SLACK_MCP_XOXP_TOKEN": "${SLACK_MCP_XOXP_TOKEN}",
        "SLACK_MCP_ADD_MESSAGE_TOOL": "true"
    }
}

with open(config_path, "w") as f:
    json.dump(data, f, indent=2)

print("   ✓ Slack MCP server added to ~/.claude.json")
PYEOF
fi

echo -e "${GREEN}✓ Slack MCP setup complete.${RESET}"
