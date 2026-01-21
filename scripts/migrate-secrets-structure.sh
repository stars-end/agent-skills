#!/usr/bin/env bash
# migrate-secrets-structure.sh (V4.2.1 - SAFE VERSION)
# Migrate from monolithic "Agent Secrets" to per-service items
#
# SAFE APPROACH: This script provides instructions only.
# It does NOT pass secret values in CLI args or read them into shell variables.
# Use the 1Password UI to create items and copy values.
#
# Usage: ./scripts/migrate-secrets-structure.sh

set -euo pipefail

cat <<'EOF'
================================================================================
1PASSWORD MIGRATION GUIDE (V4.2.1 - Per-Service Items)
================================================================================

GOAL: Migrate from monolithic "Agent Secrets" to per-service items
SAFE APPROACH: Use 1Password UI (no CLI args with secret values)

================================================================================
STEP 1: Create Per-Service Items in 1Password UI
================================================================================

Open 1Password (desktop app or browser) and create the following items:

--- Item 1: Anthropic-Config ---
Type: API Credential (or Password with custom fields)
Fields:
  • ANTHROPIC_AUTH_TOKEN (password) - paste your token
  • ANTHROPIC_BASE_URL (text) - https://api.z.ai/api/anthropic

--- Item 2: Slack-Coordinator-Secrets ---
Type: API Credential
Fields:
  • SLACK_BOT_TOKEN (password) - xoxb- token
  • SLACK_APP_TOKEN (password) - xapp- token
  • SLACK_SIGNING_SECRET (password) - optional

--- Item 3: Slack-MCP-Secrets ---
Type: API Credential
Fields:
  • SLACK_APP_TOKEN (password) - xapp- token
  • SLACK_BOT_TOKEN (password) - optional

--- Item 4: Railway-Delivery ---
Type: Password
Fields:
  • token (password) - your Railway token
  • project_id (text) - your default project ID

--- Item 5: GitHub-Delivery ---
Type: Password
Fields:
  • gh_token (password) - GitHub token for gh CLI
  • webhook_secret (password) - optional

--- Item 6: OpenCode-Config ---
Type: Secure Note
Fields:
  • model (text) - zai-coding-plan
  • port (text) - 4105
  • slack_mcp_enabled (text) - true
  • slack_mcp_add_message_tool (text) - true

================================================================================
STEP 2: Verify Items Created
================================================================================

Run this command to list all items in the dev vault:

  op item list --vault dev --format json | jq -r '.[].title'

You should see:
  - Anthropic-Config
  - Slack-Coordinator-Secrets
  - Slack-MCP-Secrets
  - Railway-Delivery
  - GitHub-Delivery
  - OpenCode-Config

================================================================================
STEP 3: Generate Per-Service Env Files
================================================================================

Run these commands to generate scoped env files:

  ./scripts/setup-env-opencode.sh
  ./scripts/setup-env-slack-coordinator.sh

These will create:
  - ~/.config/opencode/.env
  - ~/.config/slack-coordinator/.env

================================================================================
STEP 4: Verify No Secrets in CLI History
================================================================================

After migration, verify your shell history doesn't contain secrets:

  grep -i "password\|token\|secret" ~/.bash_history | grep -v "op://" | head -20
  grep -i "password\|token\|secret" ~/.zsh_history | grep -v "op://" | head -20

If you see actual secret values, clear your history:

  echo "SECRET CLEANUP" > ~/.bash_history  # or ~/.zsh_history

================================================================================
STEP 5: Retire Old "Agent Secrets" Item (Optional)
================================================================================

Once you've verified all services work with new items:

1. Open 1Password UI
2. Find the old "Agent Secrets" item
3. Archive or delete it
4. Verify services still work

================================================================================
WHY THIS APPROACH IS SAFE
================================================================================

❌ UNSAFE (old script):
   # Reads secrets into shell variables (exposed in process lists, logs)
   SLACK_BOT_TOKEN=$(op read "op://dev/Agent Secrets/ua6nlbf6...")
   # Passes secrets via CLI args (logged in shell history)
   op item create "SLACK_BOT_TOKEN[password]=$SLACK_BOT_TOKEN"

✅ SAFE (this guide):
   # Use 1Password UI to create items (secrets never touch CLI/shell)
   # Use op:// references in env files (resolved at runtime only)
   # Use op run --env-file=.env (secrets stay in 1Password until runtime)

================================================================================
NEXT STEPS
================================================================================

After creating items in 1Password UI:

  1. Run: ./scripts/setup-env-opencode.sh
  2. Run: ./scripts/setup-env-slack-coordinator.sh
  3. Restart services: systemctl --user restart opencode slack-coordinator
  4. Verify: journalctl --user -u opencode -n 50

================================================================================
EOF

echo ""
echo "Migration guide complete. Follow the steps above to safely migrate your 1Password items."
