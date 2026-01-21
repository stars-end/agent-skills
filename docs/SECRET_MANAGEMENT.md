# Secret Management Guide (V4.2.1 - Safe CLI Usage)

## Overview

This guide covers safe 1Password CLI usage patterns. **Never pass secret values via CLI arguments** - they can be logged in shell history and process lists.

## Architecture: Per-Service Items (No Mega-Items)

**V4.2.1 Design Principle:** One item per service/IDE with least-privilege access.

**Per-Service Items:**
- `Anthropic-Config` - Anthropic API tokens
- `Slack-Coordinator-Secrets` - Slack bot tokens for coordination service
- `Slack-MCP-Secrets` - Slack tokens for MCP server (IDEs)
- `Railway-Delivery` - Railway deployment tokens
- `GitHub-Delivery` - GitHub automation tokens
- `OpenCode-Config` - OpenCode IDE configuration

**Benefits:**
- **Least-Privilege:** Services only access the secrets they need
- **Labeled Fields:** Each secret has a clear label (e.g., `ANTHROPIC_AUTH_TOKEN`)
- **Scoped Env Files:** One `.env` per service (no global `~/.agent-env`)
- **Safe CLI:** No secret values passed via CLI arguments

## Safe CLI Usage Patterns

### ✅ SAFE: Use op:// References

```bash
# In env files or config files - use op:// references
ANTHROPIC_AUTH_TOKEN=op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN
SLACK_BOT_TOKEN=op://dev/Slack-Coordinator-Secrets/SLACK_BOT_TOKEN
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
op item get --vault dev "Anthropic-Config" --fields label="ANTHROPIC_AUTH_TOKEN"

# Or via op:// reference
op read "op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN"
```

### ❌ UNSAFE: Passing Secrets via CLI Args

```bash
# NEVER DO THIS - secret values logged in shell history
op item edit "Anthropic-Config" --vault dev \
  "ANTHROPIC_AUTH_TOKEN[password]=sk-your-secret-key-here"

# NEVER DO THIS - secret values exposed in process list
export ANTHROPIC_AUTH_TOKEN="sk-your-secret-key-here" && ./script.sh
```

## Managing Secrets (Safe Methods)

### Adding a New Secret

**Option 1: Use 1Password UI (Safest)**
1. Open 1Password desktop app or browser
2. Navigate to the item (e.g., "Anthropic-Config")
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
op item edit "Anthropic-Config" --vault dev \
  "OLD_FIELD[delete]"
```

## Migration from Mega-Items

### Old (Unsafe) Structure
```
Agent-Secrets-Production (mega-item)
├── ANTHROPIC_AUTH_TOKEN
├── SLACK_BOT_TOKEN
├── SLACK_APP_TOKEN
├── RAILWAY_TOKEN
├── GITHUB_TOKEN
└── ... (all secrets in one place)
```

### New (Safe) Structure
```
Anthropic-Config
├── ANTHROPIC_AUTH_TOKEN
└── ANTHROPIC_BASE_URL

Slack-Coordinator-Secrets
├── SLACK_BOT_TOKEN
├── SLACK_APP_TOKEN
└── SLACK_SIGNING_SECRET

Railway-Delivery
├── token
└── project_id
```

### Migration Steps

1. **Create per-service items** (use 1Password UI)
2. **Generate scoped env files**:
   ```bash
   ./scripts/setup-env-opencode.sh
   ./scripts/setup-env-slack-coordinator.sh
   ```
3. **Update systemd services** to use scoped env files
4. **Verify services work** with new items
5. **Retire old mega-item** (archive or delete)

See `./scripts/migrate-secrets-structure.sh` for detailed migration guide.

## Service Account Permissions

**Principle:** Least-privilege access

| Service Account | Access | Purpose |
|-----------------|--------|---------|
| `agent-skills-production` | Read-only: `Anthropic-Config`, `Slack-Coordinator-Secrets`, `OpenCode-Config` | Systemd services |
| `cicd-deployment` | Read-only: `Railway-Delivery`, `GitHub-Delivery` | CI/CD pipelines |

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
2. Verify item exists: `op item list --vault dev --format json | jq -r '.[].title'`
3. Verify field exists: `op item get "Item-Name" --vault dev`

## References

- **1Password CLI:** https://developer.1password.com/docs/cli/
- **op run:** https://developer.1password.com/docs/cli/reference/management-commands/run
- **Service Accounts:** https://developer.1password.com/docs/service-accounts/
- **Migration Guide:** `./scripts/migrate-secrets-structure.sh`
- **Env Sources Contract:** `/home/feng/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
