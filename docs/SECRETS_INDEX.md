# Secrets Index

**Quick reference for where secrets live and how to access them safely.**

---

## 1. Quick Reference Table

| What You Need | Where It Lives | How to Get It |
|---------------|----------------|---------------|
| Dev environment vars | Railway | `railway shell` or `railway run -p <project-id> -e <env> -s <service> -- <cmd>` |
| Frontend URL | Railway | `$RAILWAY_SERVICE_FRONTEND_URL` |
| Backend URL | Railway | `$RAILWAY_SERVICE_BACKEND_URL` |
| API keys | 1Password | `op://dev/Agent-Secrets-Production/<FIELD>` |
| Railway CLI token | 1Password | `op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN` |
| GitHub token | 1Password | `op://dev/Agent-Secrets-Production/GITHUB_TOKEN` |
| Anthropic token | 1Password | `op://dev/Agent-Secrets-Production/ZAI_API_KEY` |
| Slack bot tokens | 1Password | `op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN` |

Cross-reference:
- [Slack Transport Strategy (V8)](/private/tmp/agents/bd-3o07/agent-skills/docs/SLACK_TRANSPORT_STRATEGY_V8.md)

---

## 2. Agent-Secrets-Production (Canonical Source)

### Status: CANONICAL

This is the **canonical source** for all DX/dev workflow secrets. All agents and services reference this item directly.

### Field Listing

| Field Label | Purpose |
|-------------|---------|
| `ZAI_API_KEY` | Primary API key (also used as ANTHROPIC_AUTH_TOKEN via Z.ai) |
| `RAILWAY_API_TOKEN` | Railway CLI authentication |
| `GITHUB_TOKEN` | GitHub CLI / API authentication |
| `SLACK_BOT_TOKEN` | Slack bot token (xoxb-) |
| `SLACK_APP_TOKEN` | Slack app token (xapp-) |

### Reading Secrets (No jq Required)

```bash
# List all field labels (portable, no jq)
op item get --vault dev Agent-Secrets-Production | grep -E "^[A-Z_]+:" | cut -d: -f1

# Read a single secret
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"

# Read Railway token
op read "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN"
```

---

## 3. Railway Environment Variables Section

These variables are available via Railway context (`railway shell` or `railway run -p/-e/-s -- <cmd>`):

| Variable | Description |
|----------|-------------|
| `RAILWAY_SERVICE_FRONTEND_URL` | Public URL of the frontend service |
| `RAILWAY_SERVICE_BACKEND_URL` | Public URL of the backend service |
| `TEST_AUTH_BYPASS_SECRET` | Secret for bypassing auth in E2E tests |
| `DATABASE_URL` | PostgreSQL connection string |
| `RAILWAY_ENVIRONMENT` | Current Railway environment (production/staging) |

### Usage in Railway Context

```bash
# Option A: Connect interactive Railway shell
railway shell

# Option B: Worktree-safe one-shot command
railway run -p <project-id> -e dev -s backend -- env | grep RAILWAY_SERVICE

# Variables are automatically available
echo $RAILWAY_SERVICE_FRONTEND_URL
echo $DATABASE_URL
```

### Non-Interactive Railway Access

For CI/CD or automated scripts, export the Railway token:

```bash
# Load token from 1Password
export RAILWAY_API_TOKEN="$(op read 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN')"

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

## 5. Service Mapping

All services use `Agent-Secrets-Production` as their secrets source:

| Service | Fields Used |
|---------|-------------|
| opencode.service | ZAI_API_KEY, SLACK_APP_TOKEN |
| slack-coordinator.service | ZAI_API_KEY, SLACK_BOT_TOKEN, SLACK_APP_TOKEN |
| CI/CD pipelines | RAILWAY_API_TOKEN, GITHUB_TOKEN |

---

## Rules Summary

1. **Never hardcode secrets** in repos or dotfiles
2. **Use `op://` references** in config files, resolve at runtime
3. **Service account auth** for all agent/headless contexts
4. **Railway vars** for deploy-time configuration only
5. **Least-privilege**: Each service only accesses the secrets it needs

---

## Related Documentation

- **ENV_SOURCES_CONTRACT.md** - Three sources of truth (op-only, Railway CLI, Railway context)
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
echo "${RAILWAY_API_TOKEN:0:10}..."  # Shows first 10 chars only

# Re-load from 1Password
export RAILWAY_API_TOKEN="$(op read 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN')"
```
