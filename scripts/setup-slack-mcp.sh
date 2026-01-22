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
echo ""
echo "NOTE: This script does NOT write to shell rc files."
echo "Provide environment variables per-session (recommended) or via your secret manager."
echo ""

# Prefer npx-based execution to avoid needing a globally installed binary.
# This matches repo docs that use: npx -y slack-mcp-server@latest --transport stdio
if command -v npx >/dev/null 2>&1; then
    echo "✅ npx found: $(command -v npx)"
else
    echo "⚠️  npx not found"
    echo "   Install Node.js/npm (e.g., via Homebrew/Linuxbrew), then re-run."
    echo "   Fallback: build a slack-mcp-server binary (see scripts/slack-mcp-setup.sh)."
fi

# 2. Verify environment variables
if [ -z "${SLACK_MCP_XOXP_TOKEN:-}" ]; then
    echo "⚠️  SLACK_MCP_XOXP_TOKEN not set (optional for config setup)"
    echo "   Set in your shell profile: export SLACK_MCP_XOXP_TOKEN='xoxp-...'"
    echo "   Or load from 1Password:"
    echo "   export SLACK_MCP_XOXP_TOKEN=\$(op item get --vault dev Slack-MCP-Secrets --fields label=xoxp_token)"
else
    echo "✅ SLACK_MCP_XOXP_TOKEN is set"
fi

if [ -z "${SLACK_MCP_ADD_MESSAGE_TOOL:-}" ]; then
    echo "ℹ️  SLACK_MCP_ADD_MESSAGE_TOOL not set (optional)"
    echo "   Set in your shell profile: export SLACK_MCP_ADD_MESSAGE_TOOL=true"
else
    echo "✅ SLACK_MCP_ADD_MESSAGE_TOOL=$SLACK_MCP_ADD_MESSAGE_TOOL"
fi

# Function to configure Claude Code
configure_claude_code() {
    echo "Configuring Claude Code..."
    local CLAUDE_CONFIG="$HOME/.claude.json"
    if [ -f "$CLAUDE_CONFIG" ]; then
        if ! grep -q '"slack"' "$CLAUDE_CONFIG"; then
            echo "Adding Slack MCP to Claude Code config..."
            if command -v jq &> /dev/null; then
                jq '.mcpServers.slack = {"type": "stdio", "command": "npx", "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"]}' "$CLAUDE_CONFIG" > /tmp/claude.json.tmp && mv /tmp/claude.json.tmp "$CLAUDE_CONFIG"
                echo "✅ Added Slack MCP to Claude Code"
            else
                echo "⚠️  jq not found, manually add to ~/.claude.json mcpServers:"
                echo '    "slack": {"type": "stdio", "command": "npx", "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"]}'
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
        echo "Setting up Antigravity IDE config (no secrets written)..."
        cat > "$AG_CONFIG" << 'EOF'
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"]
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
command = "npx"
args = ["-y", "slack-mcp-server@latest", "--transport", "stdio"]
EOF
            echo "✅ Created Codex CLI config with Slack MCP"
        else
            # Append slack MCP config
            if ! grep -q "^\[mcpServers\]" "$CODEX_CONFIG"; then
                echo "" >> "$CODEX_CONFIG"
                echo "[mcpServers.slack]" >> "$CODEX_CONFIG"
                echo 'command = "npx"' >> "$CODEX_CONFIG"
                echo 'args = ["-y", "slack-mcp-server@latest", "--transport", "stdio"]' >> "$CODEX_CONFIG"
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
      "command": "npx",
      "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"]
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
echo "=== Environment Variables ==="
echo "Provide these per-session (recommended):"
echo "  export SLACK_MCP_XOXP_TOKEN=...          # load from 1Password"
echo "  export SLACK_MCP_ADD_MESSAGE_TOOL=true   # optional"
echo ""
echo "Load from 1Password (recommended):"
echo "  export SLACK_MCP_XOXP_TOKEN=\$(op item get --vault dev Slack-MCP-Secrets --fields label=xoxp_token)"
echo ""
echo "=== Verification Commands ==="
echo "After restarting your IDE/CLI session, verify Slack MCP is configured:"
echo ""
echo "  claude-code:  claude mcp list | grep slack"
echo "  antigravity: antigravity mcp list | grep slack"
echo "  codex-cli:   codex mcp list | grep slack"
echo "  opencode:    opencode mcp list | grep slack"
echo ""
echo "=== Test Slack MCP Server Directly ==="
echo "  npx -y slack-mcp-server@latest --transport stdio"
echo ""
echo "For more information, see: ~/agent-skills/docs/slack-mcp-setup.md"
