#!/bin/bash
# Slack MCP Server Setup - V4.2.1 (Canonical IDE Set)
# Supports: claude-code, antigravity, codex-cli, opencode
# Usage: ./setup-slack-mcp.sh [--ide IDE|--all]
#   IDE: claude-code, antigravity, codex-cli, opencode, all (default: all)

set -euo pipefail

# Parse arguments
TARGET_IDE="${1:-all}"

echo "=== Slack MCP Server Setup (V4.2.1) ==="
echo "Target IDE: $TARGET_IDE"

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

# Function to configure Claude Code
configure_claude_code() {
    echo "Configuring Claude Code..."
    local CLAUDE_CONFIG="$HOME/.claude.json"
    if [ -f "$CLAUDE_CONFIG" ]; then
        if ! grep -q '"slack"' "$CLAUDE_CONFIG"; then
            echo "Adding Slack MCP to Claude Code config..."
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
    else
        echo "⚠️  Claude Code config not found (~/.claude.json)"
    fi
}

# Function to configure Antigravity
configure_antigravity() {
    echo "Configuring Antigravity IDE..."
    local AG_CONFIG="$HOME/.gemini/antigravity/mcp_config.json"
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
}

# Function to configure Codex CLI
configure_codex_cli() {
    echo "Configuring Codex CLI..."
    local CODEX_CONFIG="$HOME/.codex/config.toml"
    mkdir -p "$HOME/.codex"
    if [ ! -f "$CODEX_CONFIG" ] || ! grep -q "slack-mcp-server" "$CODEX_CONFIG" 2>/dev/null; then
        echo "Setting up Codex CLI config..."
        # Create or append to config.toml
        if [ ! -f "$CODEX_CONFIG" ]; then
            cat > "$CODEX_CONFIG" << 'EOF'
# Codex CLI MCP Configuration
[mcpServers.slack]
command = "slack-mcp-server"
args = ["--transport", "stdio"]
EOF
            echo "✅ Created Codex CLI config with Slack MCP"
        else
            # Append slack MCP config
            if ! grep -q "^\[mcpServers\]" "$CODEX_CONFIG"; then
                echo "" >> "$CODEX_CONFIG"
                echo "[mcpServers.slack]" >> "$CODEX_CONFIG"
                echo 'command = "slack-mcp-server"' >> "$CODEX_CONFIG"
                echo 'args = ["--transport", "stdio"]' >> "$CODEX_CONFIG"
                echo "✅ Added Slack MCP to Codex CLI config"
            else
                echo "⚠️  Codex CLI config exists, manually add Slack MCP to ~/.codex/config.toml"
            fi
        fi
    else
        echo "✅ Codex CLI already has Slack MCP"
    fi
}

# Function to configure OpenCode
configure_opencode() {
    echo "Configuring OpenCode..."
    local OPENCODE_CONFIG="$HOME/.opencode/config.json"
    mkdir -p "$HOME/.opencode"
    if [ ! -f "$OPENCODE_CONFIG" ] || ! grep -q '"slack"' "$OPENCODE_CONFIG" 2>/dev/null; then
        echo "Setting up OpenCode config..."
        cat > "$OPENCODE_CONFIG" << 'EOF'
{
  "mcpServers": {
    "slack": {
      "command": "slack-mcp-server",
      "args": ["--transport", "stdio"]
    }
  }
}
EOF
        echo "✅ Created OpenCode config with Slack MCP"
    else
        echo "✅ OpenCode already has Slack MCP"
    fi
}

# Configure requested IDE(s)
case "$TARGET_IDE" in
    claude-code)
        configure_claude_code
        ;;
    antigravity)
        configure_antigravity
        ;;
    codex-cli)
        configure_codex_cli
        ;;
    opencode)
        configure_opencode
        ;;
    all)
        configure_claude_code
        configure_antigravity
        configure_codex_cli
        configure_opencode
        ;;
    *)
        echo "❌ ERROR: Unknown IDE: $TARGET_IDE" >&2
        echo "Valid IDEs: claude-code, antigravity, codex-cli, opencode, all" >&2
        exit 1
        ;;
esac

echo ""
echo "=== Setup Complete ==="
echo "Configured IDE(s): $TARGET_IDE"
echo ""
echo "Restart your IDE/CLI sessions for changes to take effect."
echo ""
echo "Verification commands:"
echo "  claude-code: claude mcp list"
echo "  antigravity: antigravity mcp list"
echo "  codex-cli:  codex mcp list"
echo "  opencode:   opencode mcp list"
echo ""
echo "Test server: slack-mcp-server --transport stdio"
