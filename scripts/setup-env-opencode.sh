#!/usr/bin/env bash
# setup-env-opencode.sh
# Generate ~/.config/opencode/.env from 1Password (per-service, no mega-item)
# Usage: ./scripts/setup-env-opencode.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/env/opencode.env.template"
OUTPUT_DIR="$HOME/.config/opencode"
OUTPUT_FILE="$OUTPUT_DIR/.env"

echo "=== Generating OpenCode Environment from 1Password ==="
echo "Source: Per-service items (no mega-item)"
echo ""

# Check 1Password CLI version
REQUIRED_VERSION="2.18.0"
OP_VERSION=$(op --version 2>/dev/null || echo "0.0.0")

if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$OP_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
    echo "❌ 1Password CLI version $OP_VERSION < $REQUIRED_VERSION (required for service accounts)"
    echo "Update: brew upgrade op"
    exit 1
fi

echo "✅ 1Password CLI version: $OP_VERSION"

# Get vault ID
VAULT_ID=$(op vault list --format json 2>/dev/null | jq -r '.[] | select(.name=="dev") | .id' || echo "")

if [[ -z "$VAULT_ID" ]]; then
    echo "❌ Could not find 'dev' vault in 1Password"
    exit 1
fi

echo "✅ Vault ID: $VAULT_ID"

# Verify required items exist (fail fast if missing)
REQUIRED_ITEMS=("Anthropic-Config" "Slack-MCP-Secrets" "OpenCode-Config")
for item in "${REQUIRED_ITEMS[@]}"; do
    ITEM_ID=$(op item list --vault "$VAULT_ID" --format json 2>/dev/null | jq -r --arg title "$item" '.[] | select(.title==$title) | .id' || echo "")
    if [[ -z "$ITEM_ID" ]]; then
        echo "❌ Required 1Password item not found: $item"
        echo ""
        echo "Please create the following items in 1Password:"
        echo "  1. Anthropic-Config (ANTHROPIC_AUTH_TOKEN, ANTHROPIC_BASE_URL)"
        echo "  2. Slack-MCP-Secrets (SLACK_APP_TOKEN)"
        echo "  3. OpenCode-Config (model, port, slack_mcp_enabled, slack_mcp_add_message_tool)"
        exit 1
    fi
    echo "✅ Found item: $item"
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Backup existing
if [[ -f "$OUTPUT_FILE" ]]; then
    BACKUP_FILE="$OUTPUT_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$OUTPUT_FILE" "$BACKUP_FILE"
    echo "✅ Backed up existing env to: $BACKUP_FILE"
fi

# Copy template directly (op:// references will be resolved at runtime)
cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

# Add metadata header
sed -i "1a# Generated: $(date -Iseconds)" "$OUTPUT_FILE"
sed -i "1a# Vault ID: $VAULT_ID" "$OUTPUT_FILE"
sed -i "1a# Per-service env file (NO mega-item)" "$OUTPUT_FILE"

chmod 600 "$OUTPUT_FILE"

echo ""
echo "✅ Generated: $OUTPUT_FILE"
echo ""
echo "Contents (secrets masked):"
grep -E "^[^#].*=" "$OUTPUT_FILE" 2>/dev/null | sed 's/=.*/=***masked***/' || true
echo ""
echo "=== Setup complete ==="
echo "Note: op:// references will be resolved at runtime by systemd via 'op run --'"
