#!/bin/bash
# slack-mcp-setup.sh
# Configures Slack MCP server for Claude Code agents.
# Part of the dx-hydrate flow.
#
# Key learnings (2026-01-03):
# - Bot tokens (xoxb-*) use SLACK_MCP_XOXB_TOKEN
# - User tokens (xoxp-*) use SLACK_MCP_XOXP_TOKEN
# - Env vars must be in ~/.zshenv (not just ~/.zshrc) for non-interactive shells
# - Local binary via stdio is more reliable than npx or SSE
# - Build from source using: go build -o ~/bin/slack-mcp-server ./cmd/slack-mcp-server

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${GREEN}🔌 Setting up Slack MCP Server...${RESET}"

# Check for required env vars (support both bot and user tokens)
SLACK_TOKEN="${SLACK_MCP_XOXB_TOKEN:-$SLACK_MCP_XOXP_TOKEN}"
if [ -z "$SLACK_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  No Slack token found. Skipping Slack MCP setup.${RESET}"
    echo "   To enable, add to ~/.zshenv:"
    echo '   export SLACK_MCP_XOXB_TOKEN="xoxb-..."  # For bot tokens'
    echo '   export SLACK_MCP_ADD_MESSAGE_TOOL=true'
    exit 0
fi

# Determine token type for correct variable name
if [ -n "$SLACK_MCP_XOXB_TOKEN" ]; then
    TOKEN_VAR="SLACK_MCP_XOXB_TOKEN"
    echo "   Using bot token (SLACK_MCP_XOXB_TOKEN)"
else
    TOKEN_VAR="SLACK_MCP_XOXP_TOKEN"
    echo "   Using user token (SLACK_MCP_XOXP_TOKEN)"
fi

CLAUDE_CONFIG="$HOME/.claude.json"
SLACK_BINARY="$HOME/bin/slack-mcp-server"

# Check if claude.json exists
if [ ! -f "$CLAUDE_CONFIG" ]; then
    echo -e "${YELLOW}⚠️  ~/.claude.json not found. Ensure Claude Code is installed.${RESET}"
    exit 0
fi

# Build slack-mcp-server if not present
if [ ! -f "$SLACK_BINARY" ]; then
    echo "   Building slack-mcp-server from source..."
    if command -v go &> /dev/null; then
        mkdir -p "$HOME/bin"
        TEMP_DIR=$(mktemp -d)
        (
            cd "$TEMP_DIR"
            git clone --depth 1 https://github.com/korotovsky/slack-mcp-server.git
            cd slack-mcp-server
            go build -o "$SLACK_BINARY" ./cmd/slack-mcp-server
        )
        rm -rf "$TEMP_DIR"
        echo -e "${GREEN}   ✓ Built slack-mcp-server${RESET}"
    else
        echo -e "${YELLOW}   ⚠️  Go not installed. Using npx fallback (slower).${RESET}"
        SLACK_BINARY="npx"
    fi
fi

# Check if slack MCP is already configured
if grep -q '"slack":' "$CLAUDE_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}✓ Slack MCP server already configured.${RESET}"
else
    echo "   Adding slack-mcp-server to ~/.claude.json..."
    python3 << PYEOF
import json
import os

config_path = os.path.expanduser("~/.claude.json")
with open(config_path, "r") as f:
    data = json.load(f)

# Ensure mcpServers exists
if "mcpServers" not in data:
    data["mcpServers"] = {}

# Determine binary path and args
binary_path = os.path.expanduser("~/bin/slack-mcp-server")
if os.path.exists(binary_path):
    # Use pre-built binary
    data["mcpServers"]["slack"] = {
        "type": "stdio",
        "command": binary_path,
        "env": {
            "${TOKEN_VAR}": os.environ.get("${TOKEN_VAR}", ""),
            "SLACK_MCP_ADD_MESSAGE_TOOL": "true"
        }
    }
else:
    # Fallback to npx
    data["mcpServers"]["slack"] = {
        "command": "npx",
        "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"],
        "env": {
            "${TOKEN_VAR}": "\${${TOKEN_VAR}}",
            "SLACK_MCP_ADD_MESSAGE_TOOL": "true"
        }
    }

with open(config_path, "w") as f:
    json.dump(data, f, indent=2)

print("   ✓ Slack MCP server added to ~/.claude.json")
PYEOF
fi

# Ensure env vars are in ~/.zshenv for non-interactive shells
if [ -f "$HOME/.zshenv" ]; then
    if ! grep -q "$TOKEN_VAR" "$HOME/.zshenv" 2>/dev/null; then
        echo "   Adding $TOKEN_VAR to ~/.zshenv for non-interactive shells..."
        echo "" >> "$HOME/.zshenv"
        echo "# Slack MCP (added by dx-hydrate)" >> "$HOME/.zshenv"
        echo "export $TOKEN_VAR=\"$SLACK_TOKEN\"" >> "$HOME/.zshenv"
        echo "export SLACK_MCP_ADD_MESSAGE_TOOL=true" >> "$HOME/.zshenv"
    fi
fi

echo -e "${GREEN}✓ Slack MCP setup complete.${RESET}"
echo "   Remember: Invite your bot to channels with /invite @YourBotName"
