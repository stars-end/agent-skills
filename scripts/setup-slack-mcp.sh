#!/bin/bash
# Slack MCP Server Setup - Run on each machine
# Supports: macmini, epyc6, homedesktop-wsl

set -e

echo "=== Slack MCP Server Setup ==="

# 1. Check if already installed
if command -v slack-mcp-server &> /dev/null; then
    echo "✅ slack-mcp-server already installed: $(which slack-mcp-server)"
else
    echo "Installing slack-mcp-server via go..."
    go install github.com/korotovsky/slack-mcp-server/mcp@latest
    echo "✅ Installed slack-mcp-server"
fi

# 2. Verify environment variables
if [ -z "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo "❌ ERROR: SLACK_MCP_XOXP_TOKEN not set"
    echo "Add to ~/.zshenv: export SLACK_MCP_XOXP_TOKEN='xoxp-...'"
    exit 1
else
    echo "✅ SLACK_MCP_XOXP_TOKEN set: ${SLACK_MCP_XOXP_TOKEN:0:15}..."
fi

if [ -z "$SLACK_MCP_ADD_MESSAGE_TOOL" ]; then
    echo "⚠️  SLACK_MCP_ADD_MESSAGE_TOOL not set, adding..."
    echo 'export SLACK_MCP_ADD_MESSAGE_TOOL=true' >> ~/.zshenv
    export SLACK_MCP_ADD_MESSAGE_TOOL=true
fi

echo "✅ SLACK_MCP_ADD_MESSAGE_TOOL=$SLACK_MCP_ADD_MESSAGE_TOOL"

# 3. Configure Claude Code (~/.claude.json)
CLAUDE_CONFIG="$HOME/.claude.json"
if [ -f "$CLAUDE_CONFIG" ]; then
    if ! grep -q '"slack"' "$CLAUDE_CONFIG"; then
        echo "Adding Slack MCP to Claude Code config..."
        # Use jq if available, otherwise warn
        if command -v jq &> /dev/null; then
            jq '.mcpServers.slack = {"type": "stdio", "command": "slack-mcp-server", "args": ["--transport", "stdio"]}' "$CLAUDE_CONFIG" > /tmp/claude.json.tmp && mv /tmp/claude.json.tmp "$CLAUDE_CONFIG"
            echo "✅ Added Slack MCP to Claude Code"
        else
            echo "⚠️  jq not found, manually add to ~/.claude.json mcpServers:"
            echo '    "slack": {"type": "stdio", "command": "slack-mcp-server", "args": ["--transport", "stdio"]}'
        fi
    else
        echo "✅ Slack MCP already in Claude Code config"
    fi
fi

# 4. Configure Antigravity IDE (~/.gemini/antigravity/mcp_config.json)
# Note: Antigravity uses ~/.gemini/ config path (gemini-cli is deprecated but antigravity still uses this path)
AG_CONFIG="$HOME/.gemini/antigravity/mcp_config.json"
mkdir -p "$HOME/.gemini/antigravity"
if [ ! -f "$AG_CONFIG" ] || ! grep -q '"slack"' "$AG_CONFIG" 2>/dev/null; then
    echo "Setting up Antigravity IDE config..."
    cat > "$AG_CONFIG" << 'EOF'
{
  "mcpServers": {
    "slack": {
      "command": "slack-mcp-server",
      "args": ["--transport", "stdio"]
    }
  }
}
EOF
    echo "✅ Created Antigravity IDE config with Slack MCP"
else
    echo "✅ Antigravity IDE already has Slack MCP"
fi

echo ""
echo "=== Setup Complete ==="
echo "Restart your IDE/CLI sessions for changes to take effect."
echo ""
echo "Test with: slack-mcp-server --transport stdio"
