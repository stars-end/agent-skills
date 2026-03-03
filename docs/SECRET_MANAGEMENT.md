# Secret Management Guide (V4.2.1 - Safe CLI Usage)

## Overview

This guide covers safe 1Password CLI usage patterns. **Never pass secret values via CLI arguments** - they can be logged in shell history and process lists.

For Agent Coordination Slack transport precedence and when OpenClaw is used for summarization vs transport, see:
- [Slack Transport Strategy (V8)](/private/tmp/agents/bd-3o07/agent-skills/docs/SLACK_TRANSPORT_STRATEGY_V8.md)

## Architecture: Agent-Secrets-Production (Canonical Source)

**Canonical Item:** `Agent-Secrets-Production` in the `dev` vault contains all DX/dev workflow secrets.

**Key Fields:**
- `ZAI_API_KEY` - Primary API key (also used as ANTHROPIC_AUTH_TOKEN via Z.ai)
- `RAILWAY_API_TOKEN` - Railway CLI authentication
- `GITHUB_TOKEN` - GitHub CLI / API authentication
- `SLACK_BOT_TOKEN` - Slack bot token (xoxb-)
- `SLACK_APP_TOKEN` - Slack app token (xapp-)

**Access pattern:**
```bash
op read "op://dev/Agent-Secrets-Production/<FIELD>"
```

**Benefits:**
- **Simplicity:** One item to manage, one path pattern to remember
- **Labeled Fields:** Each secret has a clear label
- **Safe CLI:** No secret values passed via CLI arguments

## Safe CLI Usage Patterns

### ✅ SAFE: Use op:// References

```bash
# In env files or config files - use op:// references
ANTHROPIC_AUTH_TOKEN=op://dev/Agent-Secrets-Production/ZAI_API_KEY
SLACK_BOT_TOKEN=op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN
```

### ✅ SAFE: Use op run -- for Runtime Resolution

```bash
# Resolve secrets at runtime only (never logged or exposed)
op run --env-file=.env -- python3 script.py
op run -- -- your-command-here
```

### ✅ SAFE: Read Individual Secrets (for verification only)

```bash
# Read a single secret value (outputs to stdout only)
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"

# Or get all fields
op item get --vault dev "Agent-Secrets-Production"
```

### ❌ UNSAFE: Passing Secrets via CLI Args

```bash
# NEVER DO THIS - secret values logged in shell history
op item edit "Agent-Secrets-Production" --vault dev \
  "ZAI_API_KEY[password]=sk-your-secret-key-here"

# NEVER DO THIS - secret values exposed in process list
export ZAI_API_KEY="sk-your-secret-key-here" && ./script.sh
```

## Managing Secrets (Safe Methods)

### Adding a New Secret

**Option 1: Use 1Password UI (Safest)**
1. Open 1Password desktop app or browser
2. Navigate to `Agent-Secrets-Production` in the `dev` vault
3. Click "Add Field" or edit existing field
4. Paste secret value directly (never touches CLI)

**Option 2: Use JSON Template via stdin**
```bash
# Create a JSON template with secret placeholders
cat > secret_template.json <<EOF
{
  "title": "New-Service-Secrets",
  "vault": "dev",
  "category": "api_credential",
  "fields": [
    {
      "label": "API_KEY",
      "type": "password",
      "value": "PASTE_YOUR_SECRET_HERE"
    }
  ]
}
EOF

# Then edit the JSON in a secure editor to add the real value
${EDITOR:-vi} secret_template.json

# Create item via stdin (safer than CLI args)
op item create < secret_template.json

# Shred the template file
shred -u secret_template.json
```

### Updating an Existing Secret

**Option 1: Use 1Password UI (Recommended)**
1. Open 1Password
2. Find the item
3. Edit the field value
4. Save

**Option 2: Use Environment Variable + op run**
```bash
# Load secret into environment (from secure source)
export API_KEY="$(op read "op://dev/Item/SECRET")"

# Edit with op run (resolves op:// but doesn't log value)
echo "API_KEY[password]=$API_KEY" | op item edit "Item" --vault dev -

# Clear environment variable
unset API_KEY
```

### Removing a Secret

**Option 1: Use 1Password UI**
1. Open 1Password
2. Find the item
3. Delete the field
4. Save

**Option 2: Use CLI (field deletion only)**
```bash
# This is safe - only field label is passed, not value
op item edit "Agent-Secrets-Production" --vault dev \
  "OLD_FIELD[delete]"
```

## Migration to Per-Service Items (Future)

### Current Structure
```
Agent-Secrets-Production (mega-item)
├── ZAI_API_KEY (used as ANTHROPIC_AUTH_TOKEN)
├── RAILWAY_API_TOKEN
├── GITHUB_TOKEN
├── SLACK_BOT_TOKEN
├── SLACK_APP_TOKEN
└── ... (all secrets in one place)
```

### Future Target Structure
```
Railway-Delivery
├── token
└── project_id

Slack-Coordinator-Secrets
├── SLACK_BOT_TOKEN
├── SLACK_APP_TOKEN
└── SLACK_SIGNING_SECRET
```

### Migration Steps (When Ready)

1. **Create per-service items** (use 1Password UI)
2. **Copy relevant fields** from Agent-Secrets-Production
3. **Update env templates** to use new paths
4. **Verify services work** with new items
5. **Grant service account read access** to new items

See `./scripts/migrate-secrets-structure.sh` for detailed migration guide.

## Service Account Permissions

**Service account:** `agent-skills-production`
**Access:** Read-only to the `dev` vault

This provides access to `Agent-Secrets-Production` for all agent and service workflows.

**To configure:**
1. Log in to 1Password.com
2. Go to **Developer Tools** > **Service Accounts**
3. Select the service account
4. Edit vault permissions (Read-only, no Write/Delete)
5. Save

## Verification

### Check for Secrets in Shell History

```bash
# Search bash history for leaked secrets
grep -i "password\|token\|secret" ~/.bash_history | grep -v "op://" | head -20

# Search zsh history
grep -i "password\|token\|secret" ~/.zsh_history | grep -v "op://" | head -20
```

If you find actual secret values (not op:// references), clear your history:

```bash
echo "SECRET CLEANUP" > ~/.bash_history  # or ~/.zsh_history
```

### Verify No Hardcoded Secrets

```bash
# Run secret scan on agent-skills
./scripts/guardrails/secret-scan.sh --fail
```

## Troubleshooting

### "Permission Denied" on Secret Access

**Cause:** Service account lacks read access to the item
**Fix:** Update service account permissions in 1Password.com

### "Field Not Found" Error

**Cause:** Field label doesn't match (case-sensitive)
**Fix:** Verify field labels in 1Password UI match your op:// references

### Services Fail to Start

**Cause:** op:// references can't be resolved (missing item or field)
**Fix:**
1. Check journalctl: `journalctl --user -u opencode -n 50`
2. Verify item exists: `op item list --vault dev`
3. Verify field exists: `op item get "Agent-Secrets-Production" --vault dev`

## References

- **1Password CLI:** https://developer.1password.com/docs/cli/
- **op run:** https://developer.1password.com/docs/cli/reference/management-commands/run
- **Service Accounts:** https://developer.1password.com/docs/service-accounts/
- **Env Sources Contract:** `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
