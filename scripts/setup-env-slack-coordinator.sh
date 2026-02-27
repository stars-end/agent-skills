#!/usr/bin/env bash
# setup-env-slack-coordinator.sh
# Generate ~/.config/slack-coordinator/.env from 1Password (per-service, no mega-item)
# Usage: ./scripts/setup-env-slack-coordinator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/env/slack-coordinator.env.template"
OUTPUT_DIR="$HOME/.config/slack-coordinator"
OUTPUT_FILE="$OUTPUT_DIR/.env"

echo "=== Generating Slack Coordinator Environment from 1Password ==="
echo "Source: Agent-Secrets-Production"
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

# Verify required item exists (fail fast if missing)
REQUIRED_ITEM="Agent-Secrets-Production"
ITEM_ID=$(op item list --vault "$VAULT_ID" --format json 2>/dev/null | jq -r --arg title "$REQUIRED_ITEM" '.[] | select(.title==$title) | .id' || echo "")
if [[ -z "$ITEM_ID" ]]; then
    echo "❌ Required 1Password item not found: $REQUIRED_ITEM"
    echo ""
    echo "Please verify the item exists in the 'dev' vault with fields:"
    echo "  - ZAI_API_KEY"
    echo "  - SLACK_BOT_TOKEN"
    echo "  - SLACK_APP_TOKEN"
    exit 1
fi
echo "✅ Found item: $REQUIRED_ITEM"

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
