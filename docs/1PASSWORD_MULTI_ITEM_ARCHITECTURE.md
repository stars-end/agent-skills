# 1Password Multi-Item Architecture (V4.2.1)

## Purpose

**NO MEGA-ITEMS**: Migrate from monolithic "Agent Secrets" or "Agent-Secrets-Production" to **scoped items per service** with least-privilege access patterns and field-label-based lookups.

## Design Principles

1. **No Mega-Items**: FORBIDDEN. One item per service/IDE (maximum 10 fields each)
2. **Least-Privilege**: Service accounts only access items they need
3. **Field Labels**: Use labeled fields (not UUIDs) for maintainability
4. **Scoped Env Files**: One `.env` file per service (not shared, no global ~/.agent-env)
5. **Deferred Resolution**: Keep `op://` references, resolve at runtime via `op run`

## Item Structure (Per-Service)

### Item 1: `Anthropic-Config`
**Type**: API Credential (or Password item with custom fields)
**Purpose**: Anthropic API configuration for any service that needs it
**Fields**:
- `ANTHROPIC_AUTH_TOKEN` (password)
- `ANTHROPIC_BASE_URL` (text)
- `ANTHROPIC_DEFAULT_OPUS_MODEL` (text) - optional
- `ANTHROPIC_DEFAULT_SONNET_MODEL` (text) - optional
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` (text) - optional

**Access**: All systemd services (opencode, slack-coordinator), any agent code

### Item 2: `Slack-Coordinator-Secrets`
**Type**: API Credential
**Purpose**: Slack bot tokens for slack-coordinator service
**Fields**:
- `SLACK_BOT_TOKEN` (password) - xoxb- token
- `SLACK_APP_TOKEN` (password) - xapp- token
- `SLACK_SIGNING_SECRET` (password) - optional, for events

**Access**: slack-coordinator.service only

### Item 3: `Slack-MCP-Secrets`
**Type**: API Credential
**Purpose**: Slack tokens for Slack MCP server (used by IDEs)
**Fields**:
- `SLACK_APP_TOKEN` (password) - xapp- token
- `SLACK_BOT_TOKEN` (password) - optional, if bot needs to post

**Access**: IDEs only (claude-code, opencode, codex-cli, antigravity)

### Item 4: `Railway-Delivery`
**Type**: Password
**Purpose**: Railway deployment tokens
**Fields**:
- `token` (password) - RAILWAY_TOKEN for CI/CD
- `project_id` (text) - default Railway project ID

**Access**: CI/CD scripts, deployment workflows

### Item 3: `GitHub-Delivery`
**Type**: Password
**Purpose**: GitHub automation tokens
**Fields**:
- `gh_token` (password) - GitHub token for gh CLI
- `webhook_secret` (password) - optional, for webhook validation

**Access**: GitHub Actions, automation scripts

### Item 4: `OpenCode-Config`
**Type**: Secure Note (or custom fields in Password item)
**Purpose**: OpenCode IDE-specific configuration
**Fields**:
- `model` (text) - default model to use
- `port` (text) - server port
- `slack_mcp_enabled` (text) - "true"/"false"
- `slack_mcp_add_message_tool` (text) - "true"/"false"

**Access**: opencode.service only

### Item 5: `Antigravity-Config`
**Type**: Secure Note
**Purpose**: Antigravity IDE configuration (future)
**Fields**:
- `api_endpoint` (text)
- `model` (text)
- Any antigravity-specific settings

**Access**: antigravity.service (when implemented)

### Item 6: `Codex-CLI-Config`
**Type**: Secure Note
**Purpose**: Codex CLI configuration (future)
**Fields**:
- TBP when codex-cli is implemented

**Access**: codex-cli wrapper scripts

### Item 7: `Supermemory-Config` (Future)
**Type**: Password
**Purpose**: Supermemory API integration
**Fields**:
- `api_key` (password)
- `endpoint` (text)

**Access**: Supermemory integration scripts

## Service Account Permissions

### Service Account: `agent-skills-production` (Existing)
**Current Access**:
- ✅ Read: `dev` vault (all items)
- ❌ Write: None (correct for production)

**Proposed Scoped Access** (V4.2.1):
- ✅ Read: `Anthropic-Config` (for Anthropic API access)
- ✅ Read: `Slack-Coordinator-Secrets` (for slack-coordinator.service)
- ✅ Read: `Slack-MCP-Secrets` (for IDEs)
- ✅ Read: `Railway-Delivery` (for deployment scripts)
- ✅ Read: `OpenCode-Config` (for opencode.service)
- ❌ All other items: No access

**Rationale**: Least-privilege - if opencode.service is compromised, attacker cannot access Railway tokens.

### Service Account: `cicd-deployment` (New, Optional)
**Access**:
- ✅ Read: `Railway-Delivery`
- ✅ Read: `GitHub-Delivery`
- ❌ All other items: No access

**Rationale**: Isolate CI/CD secrets from systemd service secrets.

## Scoped Environment Files

### ~/.agent-env (Shared - Deprecated)
**Status**: V4.1 (monolithic) - DEPRECATED in V4.2.1

### ~/.config/opencode/.env (V4.2.1)
**Source**: `Anthropic-Config` + `Slack-MCP-Secrets` + `OpenCode-Config`
**Usage**: opencode.service only
**Contents**:
```bash
# Load from Anthropic-Config
ANTHROPIC_AUTH_TOKEN=op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN
ANTHROPIC_BASE_URL=op://dev/Anthropic-Config/ANTHROPIC_BASE_URL

# Load from Slack-MCP-Secrets
SLACK_APP_TOKEN=op://dev/Slack-MCP-Secrets/SLACK_APP_TOKEN

# Load from OpenCode-Config
OPENCODE_MODEL=op://dev/OpenCode-Config/model
OPENCODE_PORT=op://dev/OpenCode-Config/port
SLACK_MCP_ENABLED=op://dev/OpenCode-Config/slack_mcp_enabled
```

### ~/.config/slack-coordinator/.env (V4.2.1)
**Source**: `Anthropic-Config` + `Slack-Coordinator-Secrets`
**Usage**: slack-coordinator.service only
**Contents**:
```bash
# Load from Anthropic-Config
ANTHROPIC_AUTH_TOKEN=op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN

# Load from Slack-Coordinator-Secrets
SLACK_BOT_TOKEN=op://dev/Slack-Coordinator-Secrets/SLACK_BOT_TOKEN
SLACK_APP_TOKEN=op://dev/Slack-Coordinator-Secrets/SLACK_APP_TOKEN
```

### ~/.config/railway/.env (V4.2.1)
**Source**: `Railway-Delivery`
**Usage**: Deployment scripts, CI/CD
**Contents**:
```bash
RAILWAY_TOKEN=op://dev/Railway-Delivery/token
RAILWAY_PROJECT_ID=op://dev/Railway-Delivery/project_id
```

## Migration Guide

### Step 1: Create 1Password Items (FOUNDER ACTION)
```bash
# Use 1Password UI or CLI
# Create items with structures defined above

# IMPORTANT: Use 1Password UI to avoid exposing secrets in CLI history/args
# The examples below are for reference only - use the UI for actual secrets

# Example: Anthropic-Config item (created via UI)
# Type: API Credential
# Fields:
#   ANTHROPIC_AUTH_TOKEN (password) - paste your token
#   ANTHROPIC_BASE_URL (text) - https://api.z.ai/api/anthropic

# Example: Slack-Coordinator-Secrets item (created via UI)
# Type: API Credential
# Fields:
#   SLACK_BOT_TOKEN (password) - xoxb- token
#   SLACK_APP_TOKEN (password) - xapp- token
```

### Step 2: Create Scoped Env Templates
```bash
# Create per-service env templates in agent-skills/scripts/env/
# - opencode.env.template
# - slack-coordinator.env.template
# - railway.env.template
```

### Step 3: Update Systemd Services
```bash
# Update service files to use LoadCredentialEncrypted
# Point EnvironmentFile to scoped location
# See: systemd/ opencode.service (updated)
```

### Step 4: Update Setup Scripts
```bash
# Create setup-env-opencode.sh
# Create setup-env-slack-coordinator.sh
# Each script generates scoped .env from corresponding 1Password item
```

### Step 5: Verify
```bash
# Test each service independently
systemctl --user restart opencode.service
systemctl --user restart slack-coordinator.service

# Check logs for op:// resolution failures
journalctl --user -u opencode.service -n 50
```

## Verification Checklist

### Pre-Migration
- [ ] Confirm current monolithic "Agent Secrets" item exists
- [ ] Document all field IDs/labels in use
- [ ] Backup current ~/.agent-env

### Post-Migration
- [ ] All scoped env files generated (opencode, slack-coordinator, railway)
- [ ] Systemd services use LoadCredentialEncrypted
- [ ] Services start without errors
- [ ] `op run --` successfully resolves `op://` references
- [ ] Service account has least-privilege access (test with missing item)

## Rollback Plan

If migration fails:
```bash
# Restore monolithic env file
cp ~/.agent-env.backup.YYYYMMDD_HHMMSS ~/.agent-env

# Revert systemd services to use EnvironmentFile=%h/.agent-env
# systemctl --user daemon-reload
# systemctl --user restart opencode.service slack-coordinator.service
```

## References

- **1Password CLI**: https://developer.1password.com/docs/cli/
- **Service Accounts**: https://developer.1password.com/docs/service-accounts/
- **op run**: https://developer.1password.com/docs/cli/reference/management-commands/run
- **Related Docs**:
  - `/home/feng/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
  - `/home/feng/agent-skills/docs/SERVICE_ACCOUNTS.md`
- **Beads Issues**:
  - `agent-skills-zkg` - 1Password architecture spec
  - `agent-skills-k6k` - 1Password migration
