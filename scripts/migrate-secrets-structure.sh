#!/usr/bin/env bash
# ============================================================
# DEPRECATED - 2026-02-27
# ============================================================
# Per-service item migration was NOT adopted.
#
# Decision: Agent-Secrets-Production remains the canonical source.
# Rationale: Solo founder + agents = single-item approach is simpler
# and provides adequate security.
#
# This script is kept for historical reference only.
# ============================================================

#!/usr/bin/env bash
# migrate-secrets-structure.sh (V4.2.1 - SAFE VERSION)
# Migrate from monolithic "Agent Secrets" to per-service items
#
# CURRENT STATE (2026-02-27):
# - Agent-Secrets-Production contains all secrets
# - Per-service items are NOT NEEDED (decision made)
# - This script remains as historical reference only
#
# Usage: ./scripts/migrate-secrets-structure.sh

set -euo pipefail

cat <<'EOF'
================================================================================
HISTORICAL REFERENCE - Per-Service Items (NOT ADOPTED)
================================================================================

DECISION: 2026-02-27
Agent-Secrets-Production remains the canonical source for all DX/dev secrets.

RATIONALE:
- Solo founder + agents = no multi-team security boundary needed
- Single item = simpler maintenance and onboarding
- Per-service items add overhead without meaningful security benefit

CURRENT ARCHITECTURE:

All secrets are in Agent-Secrets-Production (dev vault):
  - ZAI_API_KEY (also used as ANTHROPIC_AUTH_TOKEN via Z.ai)
  - RAILWAY_API_TOKEN
  - GITHUB_TOKEN
  - SLACK_BOT_TOKEN
  - SLACK_APP_TOKEN

Access pattern:
  source ~/agent-skills/scripts/lib/dx-auth.sh
  DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/<FIELD>" "<field_name>"

================================================================================
BELOW IS HISTORICAL CONTENT - NOT APPLICABLE
================================================================================

================================================================================
1PASSWORD MIGRATION GUIDE (FUTURE - Per-Service Items)
================================================================================

CURRENT STATE: All secrets are in Agent-Secrets-Production item.
GOAL: Migrate to per-service items for least-privilege access.
SAFE APPROACH: Use 1Password UI (no CLI args with secret values)

================================================================================
STEP 1: Create Per-Service Items in 1Password UI (WHEN READY)
================================================================================

Open 1Password (desktop app or browser) and create the following items:

--- Item 1: Railway-Delivery ---
Type: Password
Fields:
  • token (password) - copy from Agent-Secrets-Production/RAILWAY_API_TOKEN
  • project_id (text) - your default project ID

--- Item 2: Slack-Coordinator-Secrets ---
Type: API Credential
Fields:
  • SLACK_BOT_TOKEN (password) - copy from Agent-Secrets-Production
  • SLACK_APP_TOKEN (password) - copy from Agent-Secrets-Production

--- Item 3: Slack-MCP-Secrets ---
Type: API Credential
Fields:
  • SLACK_APP_TOKEN (password) - copy from Agent-Secrets-Production
  • SLACK_BOT_TOKEN (password) - copy from Agent-Secrets-Production

NOTE: Anthropic-Config is NOT needed. ZAI_API_KEY is used as ANTHROPIC_AUTH_TOKEN
(via Z.ai's Anthropic-compatible API).

================================================================================
STEP 2: Verify Items Created
================================================================================

Run this command to list all items in the dev vault:

  # HUMAN_RECOVERY_ONLY: raw 1Password item listing is for a human bootstrap terminal.
  op item list --vault dev

You should see:
  - Agent-Secrets-Production (current source of truth)
  - Railway-Delivery (future)
  - Slack-Coordinator-Secrets (future)
  - Slack-MCP-Secrets (future)

================================================================================
STEP 3: Update Env Templates (AFTER ITEMS CREATED)
================================================================================

Update scripts/env/*.env.template files to use new item paths.

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
