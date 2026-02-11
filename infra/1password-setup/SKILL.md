---
name: 1password-setup
description: |
  Setup 1Password Service Account credentials on a new machine. MUST BE USED when "op not authenticated" or setting up a new server/VM.
  Wraps `create-op-credential.sh` to generate hostname-based tokens.
tags: [infrastructure, security, setup, 1password]
allowed-tools:
  - Bash(grep:*)
  - Bash(ls:*)
  - Bash(create-op-credential.sh)
---

# 1Password Setup

Setup 1Password Service Account credentials on a new machine (~2 minutes).

## Purpose
Bootstraps the `op` CLI authentication for headless operations (cron, systemd) using Service Accounts.
Creates the `~/.config/systemd/user/op-<hostname>-token` file used by:
- `founder-briefing-cron.sh`
- `slack-coordinator.service`
- `opencode.service`

## When to Use This Skill
- Setting up a new VM/server (`epyc6`, `macmini`, etc.)
- Fixing "op not authenticated" or "missing OP_SERVICE_ACCOUNT_TOKEN" errors
- Rotating service account tokens

## Workflow

### 1. Check Existing Credential
Verifies if a token already exists for this hostname.
```bash
ls -l ~/.config/systemd/user/op-$(hostname)-token
```

### 2. Run Setup Script
Executes the canonical setup script which handles:
- Prompting for the raw Service Account Token
- Encrypting (if systemd-creds available) or securing file permissions (0600)
- Naming file based on hostname

### 3. Verify
Checks that `op` works with the new token and validates required secrets.

```bash
~/agent-skills/scripts/verify-agent-secrets.sh
```

## Usage

```bash
# 1. Run the setup script (interactive)
~/agent-skills/scripts/create-op-credential.sh

# 2. Verify everything is working
~/agent-skills/scripts/verify-agent-secrets.sh
```

## Troubleshooting
- **Permission Denied**: Ensure scripts are executable (`chmod +x scripts/*.sh`).
- **Systemd not found**: Script automatically falls back to plaintext file with 0600 permissions on macOS/WSL.
- **Missing Secrets**: Use `op item edit` to populate missing fields in `Agent-Secrets-Production` item.
