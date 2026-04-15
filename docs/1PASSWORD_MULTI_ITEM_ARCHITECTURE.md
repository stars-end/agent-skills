# 1Password Architecture

## Current State (Canonical)

**Single Item: `Agent-Secrets-Production`** in the `dev` vault contains all DX/dev secrets.

| Field | Purpose |
|-------|---------|
| `ZAI_API_KEY` | Primary API key (also used as ANTHROPIC_AUTH_TOKEN via Z.ai) |
| `RAILWAY_API_TOKEN` | Railway CLI authentication |
| `GITHUB_TOKEN` | GitHub CLI / API authentication |
| `SLACK_BOT_TOKEN` | Slack bot token (xoxb-) |
| `SLACK_APP_TOKEN` | Slack app token (xapp-) |

**Access pattern:**
```bash
source ~/agent-skills/scripts/lib/dx-auth.sh
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/ZAI_API_KEY" "zai_api_key"
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" "railway_api_token"
```

**Rationale for single-item approach:**
- Solo founder + agents = no multi-team security boundary needed
- Simplicity: one path pattern, one item to manage
- Service account already has read access
- Per-service items add maintenance overhead without meaningful security benefit

---

## Historical: Per-Service Item Architecture (Not Adopted)

The sections below document a per-service item architecture that was considered but not adopted. This is kept for reference only.

## Historical: Design Principles (Per-Service Items)

These principles were considered for per-service items but not adopted:

1. **No Mega-Items**: FORBIDDEN. One item per service/IDE (maximum 10 fields each)
2. **Least-Privilege**: Service accounts only access items they need
3. **Field Labels**: Use labeled fields (not UUIDs) for maintainability
4. **Scoped Env Files**: One `.env` file per service (not shared, no global ~/.agent-env)
5. **Deferred Resolution**: Keep `op://` references, resolve at runtime via `op run`

## Historical: Item Structure (Per-Service)

### Item 1: `Railway-Delivery` (Future)
**Type**: Password
**Purpose**: Railway deployment tokens
**Fields**:
- `token` (password) - RAILWAY_API_TOKEN for CI/CD
- `project_id` (text) - default Railway project ID

**Access**: CI/CD scripts, deployment workflows

### Item 2: `Slack-Coordinator-Secrets` (Future)
**Type**: API Credential
**Purpose**: Slack bot tokens for slack-coordinator service
**Fields**:
- `SLACK_BOT_TOKEN` (password) - xoxb- token
- `SLACK_APP_TOKEN` (password) - xapp- token
- `SLACK_SIGNING_SECRET` (password) - optional, for events

**Access**: slack-coordinator.service only

### Item 3: `Slack-MCP-Secrets` (Future)
**Type**: API Credential
**Purpose**: Slack tokens for Slack MCP server (used by IDEs)
**Fields**:
- `SLACK_APP_TOKEN` (password) - xapp- token
- `SLACK_BOT_TOKEN` (password) - optional, if bot needs to post

**Access**: IDEs only (claude-code, opencode, codex-cli, antigravity)

### Item 4: `Supermemory-Config` (Future)
**Type**: Password
**Purpose**: Supermemory API integration
**Fields**:
- `api_key` (password)
- `endpoint` (text)

**Access**: Supermemory integration scripts

## Historical: Service Account Permissions (Per-Service Items)

This scoped access pattern was considered but not adopted:

### Service Account: `agent-skills-production` (Existing)
**Current Access**:
- ✅ Read: `dev` vault (all items)
- ❌ Write: None (correct for production)

**Hypothetical Scoped Access**:
- ✅ Read: `Railway-Delivery`
- ✅ Read: `Slack-Coordinator-Secrets`
- ✅ Read: `Slack-MCP-Secrets`
- ❌ All other items: No access

**Why not adopted:** Adds configuration complexity without meaningful security benefit for solo founder + agents use case.

## Current Environment Files

All services use `Agent-Secrets-Production` as the source:

### ~/.config/opencode/.env
```bash
ANTHROPIC_AUTH_TOKEN=op://dev/Agent-Secrets-Production/ZAI_API_KEY
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
SLACK_APP_TOKEN=op://dev/Agent-Secrets-Production/SLACK_APP_TOKEN
OPENCODE_MODEL=glm-5
OPENCODE_PORT=4096
```

### ~/.config/slack-coordinator/.env
```bash
ANTHROPIC_AUTH_TOKEN=op://dev/Agent-Secrets-Production/ZAI_API_KEY
SLACK_BOT_TOKEN=op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN
SLACK_APP_TOKEN=op://dev/Agent-Secrets-Production/SLACK_APP_TOKEN
```

### Railway Context
```bash
source ~/agent-skills/scripts/lib/dx-auth.sh
export RAILWAY_API_TOKEN=$(DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" "railway_api_token")
```

## Migration Guide (To Per-Service Items)

### Step 1: Create 1Password Items (FOUNDER ACTION)
```bash
# Use 1Password UI to create items:
# - Railway-Delivery (copy RAILWAY_API_TOKEN from Agent-Secrets-Production)
# - Slack-Coordinator-Secrets (copy SLACK_BOT_TOKEN, SLACK_APP_TOKEN)
# - Slack-MCP-Secrets (copy SLACK_APP_TOKEN, SLACK_BOT_TOKEN)
```

### Step 2: Update Env Templates
```bash
# Update scripts/env/*.env.template to use new item paths
```

---

## Decision Record

**Date:** 2026-02-27
**Decision:** Keep `Agent-Secrets-Production` as canonical single source
**Rationale:**
- Solo founder + agents = no multi-team security boundary
- Single item = simpler maintenance and onboarding
- Per-service items add overhead without meaningful security benefit
- Service account already has appropriate read-only access

## References

- **1Password CLI**: https://developer.1password.com/docs/cli/
- **Service Accounts**: https://developer.1password.com/docs/service-accounts/
- **op run**: https://developer.1password.com/docs/cli/reference/management-commands/run
- **Related Docs**:
  - `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
  - `~/agent-skills/docs/SECRETS_INDEX.md`
