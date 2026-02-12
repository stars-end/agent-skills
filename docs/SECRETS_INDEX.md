# Secrets Index

**Quick reference for where secrets live and how to access them safely.**

---

## 1. Quick Reference Table

| What You Need | Where It Lives | How to Get It |
|---------------|----------------|---------------|
| Dev environment vars | Railway | `railway shell` (automatic) |
| Frontend URL | Railway | `$RAILWAY_SERVICE_FRONTEND_URL` |
| Backend URL | Railway | `$RAILWAY_SERVICE_BACKEND_URL` |
| API keys | 1Password | `op://dev/Agent-Secrets-Production/<FIELD>` |
| Railway CLI token | 1Password | `op://dev/Railway-Delivery/token` |
| GitHub token | 1Password | `op://dev/GitHub-Delivery/gh_token` |
| Anthropic token | 1Password | `op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN` |
| Slack bot tokens | 1Password | `op://dev/Slack-Coordinator-Secrets/SLACK_BOT_TOKEN` |

---

## 2. Agent-Secrets-Production Section

### Status: CURRENT DEFAULT - Transitional

This is the **current default** source for API keys during the transition period. It is NOT "canonical" or "permanent" - migration to per-service items is planned.

### Migration Target

The goal is to move to scoped per-service 1Password items:
- `Anthropic-Config` - Anthropic API tokens
- `Slack-Coordinator-Secrets` - Slack bot tokens for coordination service
- `Slack-MCP-Secrets` - Slack tokens for MCP server (IDEs)
- `Railway-Delivery` - Railway deployment tokens
- `GitHub-Delivery` - GitHub automation tokens
- `OpenCode-Config` - OpenCode IDE configuration

### Field Listing (Agent-Secrets-Production)

| Field Label | Purpose |
|-------------|---------|
| `ZAI_API_KEY` | Primary API key for agent workflows |
| `ANTHROPIC_AUTH_TOKEN` | Anthropic API authentication |
| `TEST_USER_EMAIL` | Test user email for CI/E2E tests |
| `TEST_USER_PASSWORD` | Test user password for CI/E2E tests |
| `SLACK_BOT_TOKEN` | Slack bot token (xoxb-) |
| `SLACK_APP_TOKEN` | Slack app token (xapp-) |

### Reading Secrets (No jq Required)

```bash
# List all field labels (portable, no jq)
op item get --vault dev Agent-Secrets-Production | grep -E "^[A-Z_]+:" | cut -d: -f1

# Read a single secret
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"

# Read Anthropic token
op read "op://dev/Agent-Secrets-Production/ANTHROPIC_AUTH_TOKEN"
```

---

## 3. Railway Environment Variables Section

These variables are **automatically available** in `railway shell`:

| Variable | Description |
|----------|-------------|
| `RAILWAY_SERVICE_FRONTEND_URL` | Public URL of the frontend service |
| `RAILWAY_SERVICE_BACKEND_URL` | Public URL of the backend service |
| `TEST_AUTH_BYPASS_SECRET` | Secret for bypassing auth in E2E tests |
| `DATABASE_URL` | PostgreSQL connection string |
| `RAILWAY_ENVIRONMENT` | Current Railway environment (production/staging) |

### Usage in Railway Shell

```bash
# Connect to Railway shell
railway shell

# Variables are automatically available
echo $RAILWAY_SERVICE_FRONTEND_URL
echo $DATABASE_URL
```

### Non-Interactive Railway Access

For CI/CD or automated scripts, export the Railway token:

```bash
# Load token from 1Password
export RAILWAY_TOKEN="$(op read 'op://dev/Railway-Delivery/token')"

# Now railway commands use the token
railway status
railway logs
```

---

## 4. Service Account Setup Section

**REQUIRED for agents** - Never use interactive biometric authentication in headless/agent contexts.

### One-Time Setup (Per Machine)

```bash
# Create protected credential (will prompt for token paste)
~/agent-skills/scripts/create-op-credential.sh

# If you need to replace an existing credential
~/agent-skills/scripts/create-op-credential.sh --force
```

This creates:
- **Linux (with systemd-creds)**: `~/.config/systemd/user/op-<hostname>-token.cred` (encrypted)
- **macOS (fallback)**: `~/.config/systemd/user/op-<hostname>-token` (chmod 600)

### Every Session (Before Using op CLI)

```bash
# Export token for current shell
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-$(hostname)-token)"

# Verify authentication
op whoami
# Expected output: User Type: SERVICE_ACCOUNT
```

### Verification

```bash
# Should show SERVICE_ACCOUNT, not biometric user
op whoami

# List available items (confirms read access)
op item list --vault dev
```

---

## 5. Project to Secrets Mapping Table

| Project | Railway Service | API Keys Source | Notes |
|---------|-----------------|-----------------|-------|
| prime-radiant-ai | frontend, backend | Agent-Secrets-Production | Primary app deployment |
| affordabot | affordabot | Agent-Secrets-Production | Bot service |
| agent-skills | N/A | Agent-Secrets-Production | DX tooling (no deployment) |
| llm-common | N/A | N/A | Shared library (no secrets needed) |

### Per-Service Secret Mapping (Migration Target)

| Service | 1Password Item | Fields Used |
|---------|----------------|-------------|
| opencode.service | Anthropic-Config, Slack-MCP-Secrets, OpenCode-Config | ANTHROPIC_AUTH_TOKEN, SLACK_APP_TOKEN |
| slack-coordinator.service | Anthropic-Config, Slack-Coordinator-Secrets | ANTHROPIC_AUTH_TOKEN, SLACK_BOT_TOKEN, SLACK_APP_TOKEN |
| CI/CD pipelines | Railway-Delivery, GitHub-Delivery | token, gh_token |

---

## Rules Summary

1. **Never hardcode secrets** in repos or dotfiles
2. **Use `op://` references** in config files, resolve at runtime
3. **Service account auth** for all agent/headless contexts
4. **Railway vars** for deploy-time configuration only
5. **Least-privilege**: Each service only accesses the secrets it needs

---

## Related Documentation

- **ENV_SOURCES_CONTRACT.md** - Three sources of truth (op-only, Railway CLI, Railway shell)
- **SECRET_MANAGEMENT.md** - Safe CLI usage patterns and migration guide
- **1PASSWORD_MULTI_ITEM_ARCHITECTURE.md** - Per-service item structure
- **SERVICE_ACCOUNTS.md** - Service account configuration

---

## Quick Troubleshooting

### "Permission Denied" on Secret Access

```bash
# Verify service account is active
op whoami

# If not authenticated, export token
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-$(hostname)-token)"
```

### "Field Not Found" Error

Field labels are case-sensitive. Verify exact label name:

```bash
op item get --vault dev Agent-Secrets-Production
```

### Railway Token Not Working

```bash
# Verify token is loaded
echo "${RAILWAY_TOKEN:0:10}..."  # Shows first 10 chars only

# Re-load from 1Password
export RAILWAY_TOKEN="$(op read 'op://dev/Railway-Delivery/token')"
```
