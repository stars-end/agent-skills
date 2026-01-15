#!/bin/bash
# Fix SSH environment inheritance for Slack MCP tokens
# This moves SLACK_MCP_* exports from .zshrc to .zshenv
# .zshenv is sourced for ALL shells (including non-interactive SSH)

set -e

echo "=== Fixing SSH Environment Inheritance ==="
echo "This moves SLACK_MCP_* vars from .zshrc to .zshenv"
echo ""

# Find SLACK_MCP exports in .zshrc
if [ -f ~/.zshrc ]; then
    SLACK_EXPORTS=$(grep "export SLACK_MCP" ~/.zshrc 2>/dev/null || true)
    if [ -n "$SLACK_EXPORTS" ]; then
        echo "Found in ~/.zshrc:"
        echo "$SLACK_EXPORTS"
        echo ""
        
        # Check if .zshenv exists
        if [ ! -f ~/.zshenv ]; then
            echo "Creating ~/.zshenv..."
            touch ~/.zshenv
        fi
        
        # Check if already in .zshenv
        if grep -q "SLACK_MCP" ~/.zshenv 2>/dev/null; then
            echo "SLACK_MCP vars already in ~/.zshenv"
        else
            echo "Adding to ~/.zshenv..."
            echo "" >> ~/.zshenv
            echo "# Slack MCP tokens (moved from .zshrc for SSH compatibility)" >> ~/.zshenv
            echo "$SLACK_EXPORTS" >> ~/.zshenv
            echo "✅ Added to ~/.zshenv"
        fi
        
        # Optionally remove from .zshrc (commented out for safety)
        # echo "Removing from ~/.zshrc..."
        # grep -v "export SLACK_MCP" ~/.zshrc > ~/.zshrc.tmp && mv ~/.zshrc.tmp ~/.zshrc
        
        echo ""
        echo "⚠️  Consider removing the duplicate exports from ~/.zshrc manually"
    else
        echo "No SLACK_MCP exports found in ~/.zshrc"
    fi
else
    echo "No ~/.zshrc found"
fi

# Verify
echo ""
echo "=== Verification ==="
echo "Testing: source ~/.zshenv && echo SLACK_MCP_XOXP_TOKEN"
source ~/.zshenv 2>/dev/null || true
if [ -n "$SLACK_MCP_XOXP_TOKEN" ]; then
    echo "✅ SLACK_MCP_XOXP_TOKEN: ${SLACK_MCP_XOXP_TOKEN:0:15}..."
else
    echo "❌ SLACK_MCP_XOXP_TOKEN not set"
fi

if [ -n "$SLACK_MCP_ADD_MESSAGE_TOOL" ]; then
    echo "✅ SLACK_MCP_ADD_MESSAGE_TOOL=$SLACK_MCP_ADD_MESSAGE_TOOL"
fi

echo ""
echo "=== Done ==="
echo "Now SSH commands will inherit SLACK_MCP_* environment variables"
