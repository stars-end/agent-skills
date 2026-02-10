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

Keep secrets out of repos and dotfiles. Use 1Password `op://...` references and runtime resolution (`op read`, `op run --`) with service account auth.

## What Lives Where

- **DX/dev workflow secrets** (agent keys, automation tokens): 1Password (`op://...`), resolved at runtime.
- **Deploy/runtime config**: Railway **environment variables** in the Railway project.
- **Railway CLI automation token**: `RAILWAY_TOKEN` exported from 1Password (`Railway-Delivery`).

## Common Commands (Safe Defaults)

Verify op auth:
```bash
op whoami
```

Create a protected service-account token file (HITL paste required):
```bash
~/agent-skills/scripts/create-op-credential.sh
```

If needed, export token for this shell (mac-friendly plaintext case):
```bash
export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.config/systemd/user/op-$(hostname)-token)"
op whoami
```

List items in the `dev` vault (titles only, no secrets):
```bash
op item list --vault dev
```

List field labels for `Agent-Secrets-Production` without printing values:
```bash
op item get --vault dev Agent-Secrets-Production --format json | jq -r '.fields[].label'
```

Read a single secret value (verification only; prints to stdout):
```bash
op read "op://dev/Agent-Secrets-Production/ZAI_API_KEY"
```

## Railway Automation Token (Non-Interactive)

```bash
export RAILWAY_TOKEN="$(op read 'op://dev/Railway-Delivery/token')"
```

## Rules

- Never hardcode secrets in repos.
- Prefer `op://...` references in env templates and resolve at runtime via `op run --env-file=... -- <command>`.
- Avoid printing secrets in logs. If you must verify, do it once and then stop output.

References:
- `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
- `~/agent-skills/docs/SECRET_MANAGEMENT.md`

