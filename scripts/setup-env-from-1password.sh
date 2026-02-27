#!/bin/bash
# ============================================================
# HISTORICAL - Migration complete 2026-02-18
# Do not use. Kept for migration record only.
# ============================================================

#!/bin/bash
# ============================================================
# DEPRECATED: V4.2.1 - Use scoped env files instead
# ============================================================
#
# This script is DEPRECATED in V4.2.1 because it uses the
# monolithic "Agent-Secrets-Production" approach.
#
# CURRENT STATE (2026-02-27):
# - Agent-Secrets-Production is still the source of truth
# - All secrets live in this single item
# - Per-service items (Railway-Delivery, Slack-*) are planned but not yet created
#
# To generate env files for current state:
# - See: scripts/setup-env-opencode.sh, scripts/setup-env-slack-coordinator.sh
# - See: docs/SECRETS_INDEX.md
# ============================================================

set -euo pipefail

echo "⚠️  WARNING: This script is DEPRECATED in V4.2.1"
echo "   Use per-service setup scripts instead:"
echo "   - scripts/setup-env-opencode.sh"
echo "   - scripts/setup-env-slack-coordinator.sh"
echo
echo "🔐 Generating ~/.agent-env from 1Password (V2 Structure - DEPRECATED)..."
echo

# Check 1Password CLI version
required_version="2.18.0"
current_version=$(op --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")

if [ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]; then
    echo "❌ 1Password CLI version $required_version or later required"
    exit 1
fi

# Cache vault ID
VAULT_ID=$(op vault list --format json 2>/dev/null | jq -r '.[] | select(.name=="dev") | .id' || echo "")

if [ -z "$VAULT_ID" ]; then
    echo "❌ Could not find 'dev' vault in 1Password"
    exit 1
fi

# Find the new V2 item
ITEM_TITLE="Agent-Secrets-Production"
ITEM_ID=$(op item list --vault "$VAULT_ID" --format json 2>/dev/null | jq -r --arg title "$ITEM_TITLE" '.[] | select(.title==$title) | .id' || echo "")

if [ -z "$ITEM_ID" ]; then
    echo "❌ Could not find '$ITEM_TITLE' item in vault"
    echo "Run scripts/migrate-secrets-structure.sh first"
    exit 1
fi

echo "✅ Found item: $ITEM_TITLE ($ITEM_ID)"

# Backup existing
if [ -f ~/.agent-env ]; then
    cp ~/.agent-env ~/.agent-env.backup
fi

# Generate new ~/.agent-env using LABEL lookups
# This is much more robust than ID lookups
cat > ~/.agent-env <<EOF
# 1Password Environment (V2 Structure)
# Generated: $(date -Iseconds)
# DO NOT commit to git

# 1Password IDs
OP_VAULT_ID="$VAULT_ID"
OP_AGENT_SECRETS_ID="$ITEM_ID"

# 1Password secret references (by Label)
SLACK_BOT_TOKEN="op://$VAULT_ID/$ITEM_TITLE/SLACK_BOT_TOKEN"
SLACK_APP_TOKEN="op://$VAULT_ID/$ITEM_TITLE/SLACK_APP_TOKEN"
ZAI_API_KEY="op://$VAULT_ID/$ITEM_TITLE/ZAI_API_KEY"
SUPERMEMORY_API_KEY="op://$VAULT_ID/$ITEM_TITLE/SUPERMEMORY_API_KEY"
RAILWAY_API_TOKEN="op://$VAULT_ID/$ITEM_TITLE/RAILWAY_API_TOKEN"
GITHUB_TOKEN="op://$VAULT_ID/$ITEM_TITLE/GITHUB_TOKEN"
OPENROUTER_API_KEY="op://$VAULT_ID/$ITEM_TITLE/OPENROUTER_API_KEY"

# Compatibility aliases
SLACK_MCP_XOXB_TOKEN="\$SLACK_BOT_TOKEN"

# OpenCode configuration
OPENCODE_MODEL="zai-coding-plan"
SLACK_MCP_ADD_MESSAGE_TOOL="true"

# PATH
PATH="/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin"
EOF

echo "✅ Generated ~/.agent-env (V2)"
echo "   Uses labeled fields from '$ITEM_TITLE'"