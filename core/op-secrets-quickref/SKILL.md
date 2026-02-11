---
name: op-secrets-quickref
description: |
  Quick reference for 1Password (op CLI) secret management used in DX/dev workflows and deployments.
  Use when the user asks about ZAI_API_KEY, Agent-Secrets-Production, OP_SERVICE_ACCOUNT_TOKEN, 1Password service accounts, op:// references, Railway tokens, GitHub tokens, or "where do secrets live".
tags: [secrets, 1password, op-cli, dx, env, railway]
allowed-tools:
  - Bash
---

# op-secrets-quickref

## Goal

Keep secrets out of repos and dotfiles. Use 1Password `op://...` references and runtime resolution (`op read`, `op run --`) with **service account auth** (default, not interactive biometric).

## What Lives Where

- **DX/dev workflow secrets** (agent keys, automation tokens): 1Password (`op://...`), resolved at runtime.
- **Deploy/runtime config**: Railway **environment variables** in the Railway project.
- **Railway CLI automation token**: `RAILWAY_TOKEN` exported from 1Password (`Railway-Delivery`).

## Service-Account-First Auth (Default)

### Step 1: Verify/Create Service Account Token

Check if credential exists:
```bash
ls -la ~/.config/systemd/user/op-$(hostname)-token*
```

Create protected service-account token file (requires human to paste token):
```bash
~/agent-skills/scripts/create-op-credential.sh
```

### Step 2: Export Token for Current Shell

**Linux (systemd-creds encrypted):**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(systemd-creds decrypt ~/.config/systemd/user/op-$(hostname)-token.cred)"
```

**macOS (plaintext fallback):**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-$(hostname)-token)"
```

### Step 3: Verify Auth

```bash
op whoami
```

Expected output: `ServiceAccount: ...` (not interactive user account)

### Interactive Auth (Fallback Only)

Use only when service account unavailable:
```bash
eval $(op signin)
```

## Common Commands (No jq Required)

### List Items (Titles Only)

List items in the `dev` vault:
```bash
op item list --vault dev
```

### List Field Labels (No Secret Values)

Get field labels for an item using grep/cut (no jq needed):
```bash
op item get --vault dev Agent-Secrets-Production --format json | grep -o '"label":"[^"]*"' | cut -d'"' -f4
```

Alternative using op's native field output:
```bash
op item get --vault dev Agent-Secrets-Production --fields label
```

### Read a Single Secret

```bash
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"
```

### Read Multiple Fields at Once

```bash
op item get --vault dev Railway-Delivery --fields token,project_id
```

## Railway Variables

### Railway CLI Token (Non-Interactive)

```bash
export RAILWAY_TOKEN="$(op read 'op://dev/Railway-Delivery/token')"
```

### Railway Service URL Variables

Railway automatically injects these URL variables into services:

| Variable | Description | Example |
|----------|-------------|---------|
| `RAILWAY_SERVICE_FRONTEND_URL` | Public URL for frontend service | `https://myapp.up.railway.app` |
| `RAILWAY_SERVICE_BACKEND_URL` | Public URL for backend service | `https://api.myapp.up.railway.app` |
| `RAILWAY_STATIC_URL` | Static URL (legacy) | `https://myapp.up.railway.app` |

**Usage in services:**
```bash
# In Railway service, these are auto-injected
curl "$RAILWAY_SERVICE_BACKEND_URL/health"
```

**Local development fallback:**
```bash
# Use localhost when not in Railway
BACKEND_URL="${RAILWAY_SERVICE_BACKEND_URL:-http://localhost:3000}"
```

## Rules

- Never hardcode secrets in repos.
- Prefer service account auth over interactive biometric auth.
- Prefer `op://...` references in env templates and resolve at runtime via `op run --env-file=... -- <command>`.
- Avoid printing secrets in logs. If you must verify, do it once and then stop output.
- Use grep/cut instead of jq for field extraction (more portable).

## References

- **Comprehensive Index**: `~/agent-skills/docs/SECRETS_INDEX.md` - Full secrets and env variables catalog
- **Related Docs**:
  - `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md` - Environment source mapping
  - `~/agent-skills/docs/SECRET_MANAGEMENT.md` - Detailed secret management guide
  - `~/agent-skills/docs/SERVICE_ACCOUNTS.md` - Service account architecture
