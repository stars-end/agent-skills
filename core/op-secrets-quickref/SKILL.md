---
name: op-secrets-quickref
description: |
  Quick reference for 1Password service account auth and secret management.
  Use for: API keys, tokens, service accounts, op:// references, or auth failures in non-interactive contexts (cron, systemd, CI).
  Triggers: ZAI_API_KEY, OP_SERVICE_ACCOUNT_TOKEN, 1Password, "where do secrets live", auth failure, 401, permission denied.
tags: [secrets, auth, token, 1password, op-cli, dx, env, railway]
allowed-tools:
  - Bash
---

# op-secrets-quickref

## Goal

Keep secrets out of repos and dotfiles. Use 1Password `op://...` references and runtime resolution (`op read`, `op run --`) with **service account auth** (default, not interactive biometric).

## Critical Rule

- Tool calls do **not** share shell exports reliably. If you need `op read` and `railway` in automation, load `OP_SERVICE_ACCOUNT_TOKEN` and `RAILWAY_API_TOKEN` in the **same command invocation**.
- Prefer the canonical helper:

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
```

## What Lives Where

- **DX/dev workflow secrets** (agent keys, GitHub tokens, Slack tokens): 1Password (`op://...`), resolved at runtime.
- **Deploy/runtime config**: Railway **environment variables** in the Railway project.
- **App runtime secrets** (for example `EODHD_CRON_SHARED_SECRET`, `DATABASE_URL`, service URLs): Railway service env, not guessed 1Password items.
- **Railway CLI automation token**: `RAILWAY_API_TOKEN` exported from 1Password (`Agent-Secrets-Production`).

### Slack token policy for deterministic transport

- Use `SLACK_BOT_TOKEN` as default for Agent Coordination transport.
- Fallback to `SLACK_APP_TOKEN` if needed.
- Both are resolved from `op://dev/Agent-Secrets-Production/...`.
- A valid token does not guarantee channel history access; missing channel membership or `channels:join` scope is a Slack scope issue, not an OP auth failure.

```bash
# Use cached resolution for automation / cron
source scripts/lib/dx-auth.sh
export SLACK_BOT_TOKEN="$(dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/SLACK_BOT_TOKEN")"
export SLACK_APP_TOKEN="$(dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/SLACK_APP_TOKEN")"
```

Implementation uses these tokens via:
[`scripts/lib/dx-slack-alerts.sh`](/private/tmp/agents/bd-3o07/agent-skills/scripts/lib/dx-slack-alerts.sh)

## 1Password Item Reference

| Item | Fields | Purpose |
|------|--------|---------|
| `Agent-Secrets-Production` | `ZAI_API_KEY`, `RAILWAY_API_TOKEN`, `GITHUB_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` | DX/dev workflow secrets (default source) |

**Note:** ZAI_API_KEY is used as ANTHROPIC_AUTH_TOKEN (Z.ai routes to Anthropic-compatible API).

## Service-Account-First Auth (Default)

### Step 1: Verify/Create Service Account Token

Check if credential exists:
```bash
ls -la ~/.config/systemd/user/op-{macmini,homedesktop-wsl,epyc6,epyc12}-token*
```

Create protected service-account token file (requires human to paste token):
```bash
~/agent-skills/scripts/create-op-credential.sh
```

### Step 2: Export Token for Current Shell

Fallback order for service-account credentials:

1. `OP_SERVICE_ACCOUNT_TOKEN_FILE` if explicitly set
2. `~/.config/systemd/user/op-<canonical-host-key>-token`
3. `~/.config/systemd/user/op-<canonical-host-key>-token.cred`
4. legacy fallback: `~/.config/systemd/user/op_token`
5. legacy fallback: `~/.config/systemd/user/op_token.cred`

**Linux/macOS same-invocation helper (recommended):**
```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- op whoami
```

**Linux (systemd-creds encrypted):**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(systemd-creds decrypt ~/.config/systemd/user/op-epyc6-token.cred)"
```

**macOS (plaintext fallback):**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-macmini-token)"
```

### Step 3: Verify Auth

```bash
op whoami
```

Expected output: `ServiceAccount: ...` (not interactive user account)

## Failure Modes: Auth vs Rate Limit

Treat these as different problems:

- `No accounts configured`, `not signed in`, `Unauthorized`
  - service-account auth is missing or the token was not loaded in the same invocation
- `Too many requests`
  - service-account auth succeeded, but 1Password is rate-limiting the client

For rate limits:
- stop repeated `op item list`, `op item get`, `op item create`, and `op read` loops
- batch reads where possible
- wait and retry with backoff instead of assuming auth is broken

Minimal retry pattern:

```bash
for delay in 5 15 30; do
  if op read "op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN" >/dev/null; then
    break
  fi
  sleep "$delay"
done
```

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

### Read a Single Secret (interactive / one-shot)

For occasional manual use, `op read` is fine:

```bash
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"
```

### Cached Secret Resolution (standard for automation / repeated reads)

For cron, systemd, scripts, or any path that reads secrets repeatedly, use the
cached helpers from `scripts/lib/dx-auth.sh`.  These avoid hitting 1Password on
every invocation by maintaining a local file cache (`~/.cache/dx/op-secrets/`,
24h TTL) refreshed via the service account token.

**General-purpose cached read:**

```bash
source scripts/lib/dx-auth.sh
token="$(dx_auth_read_secret_cached "op://dev/Agent-Secrets-Production/ZAI_API_KEY")"
```

**Named loaders for common secrets:**

| Helper | Env var set | Source ref |
|--------|-------------|------------|
| `dx_auth_load_zai_api_key` | `ZAI_API_KEY` | `op://dev/Agent-Secrets-Production/ZAI_API_KEY` |
| `dx_auth_load_railway_api_token` | `RAILWAY_API_TOKEN` | `op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN` |
| `dx_auth_load_github_token` | `GH_TOKEN` | `op://dev/Agent-Secrets-Production/GITHUB_TOKEN` |
| `dx_auth_load_op_service_account_token` | `OP_SERVICE_ACCOUNT_TOKEN` | host credential files |

**Example — cron / automation:**

```bash
# Nightly enrichment (uses cached ZAI_API_KEY)
0 3 * * * /path/to/agent-skills/scripts/enrichment/enrichment-cron-wrapper.sh >> /tmp/enrichment.log 2>&1
```

**Example — script preamble:**

```bash
#!/usr/bin/env bash
source scripts/lib/dx-auth.sh
dx_auth_load_zai_api_key || { echo "BLOCKED: ZAI_API_KEY" >&2; exit 1; }
# $ZAI_API_KEY is now exported and ready
```

**How the cache works:**

1. If the target env var is already set (and not an `op://` reference), return immediately.
2. Check the local cache file (`~/.cache/dx/op-secrets/`). If fresh (within TTL), read from it.
3. On cache miss, load the OP service account token and refresh the cache via `op item get`.
4. Export the resolved value.

### Export for CLI Usage (cron/CI)

```bash
# GitHub CLI — use cached loader
source scripts/lib/dx-auth.sh && dx_auth_load_github_token
gh auth status  # Should show: ✓ Logged in to github.com (GH_TOKEN)

# Railway CLI auth (same invocation recommended)
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway status
```

### Read Multiple Fields at Once

```bash
op item get --vault dev Agent-Secrets-Production --fields ZAI_API_KEY,RAILWAY_API_TOKEN,GITHUB_TOKEN
```

## Railway Variables

### Railway CLI Token (Non-Interactive)

```bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
```

If you must do it manually, keep both steps in the same shell invocation:

```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-epyc6-token)" && \
export RAILWAY_API_TOKEN="$(op read 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN')" && \
railway whoami
```

### App Runtime Secrets: Use Railway Context, Not `op read`

If a secret belongs to the deployed app or service runtime, do **not** invent a 1Password path for it.

Wrong:

```bash
op read "op://dev/prime-radiant-dev/EODHD_CRON_SHARED_SECRET"
```

Right:

```bash
# Verify the secret exists in the service runtime without printing it
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- sh -lc 'test -n "$EODHD_CRON_SHARED_SECRET" && echo configured'

# Use the secret inside Railway context so it never needs to be echoed locally
~/agent-skills/scripts/dx-load-railway-auth.sh -- \
  ~/agent-skills/scripts/dx-railway-run.sh -- sh -lc '
    curl -sS -X POST \
      -H "Content-Type: application/json" \
      -H "X-PR-CRON-SECRET: $EODHD_CRON_SHARED_SECRET" \
      "$BACKEND_INTERNAL_URL/api/v2/internal/eodhd/cron/eod"
  '
```

For Prime Radiant dev investigations, the active orchestrator is Railway-hosted Windmill on the canonical unsuffixed Railway stack. Check the Windmill workspace assets under `f/eodhd/*` before assuming the deprecated `eodhd-cron` service is the primary runtime surface.

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
- **Prefer cached secret helpers** (`dx_auth_read_secret_cached`, `dx_auth_load_zai_api_key`, etc.) for cron, systemd, automation, and any repeated secret reads. Use raw `op read` only for occasional manual one-shot use.
- Prefer `op://...` references in env templates and resolve at runtime via `op run --env-file=... -- <command>`.
- Avoid printing secrets in logs. If you must verify, do it once and then stop output.
- Use grep/cut instead of jq for field extraction (more portable).
- Do not put `OP_SERVICE_ACCOUNT_TOKEN` or `RAILWAY_API_TOKEN` in `~/.zshrc` or `~/.zshenv`.
- Do not guess 1Password item names for app runtime secrets. If the value belongs to a deployed service, fetch it from Railway context.
- Do not diagnose OP rate limits as sign-in failures without checking `op whoami` first.

## References

- **Comprehensive Index**: `~/agent-skills/docs/SECRETS_INDEX.md` - Full secrets and env variables catalog
- **Related Docs**:
  - `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md` - Environment source mapping
  - `~/agent-skills/docs/SECRET_MANAGEMENT.md` - Detailed secret management guide
  - `~/agent-skills/docs/SERVICE_ACCOUNTS.md` - Service account architecture
