---
name: ssh-key-doctor
description: |
  Fast, deterministic SSH health check for canonical VMs (no hangs, no secrets).
  Warn-only by default; strict mode is opt-in.

  **DEPRECATED for Tailscale SSH**: Use Tailscale SSH for all canonical VM access.
  This skill remains for legacy SSH key troubleshooting only.
tags: [dx, ssh, verification, deprecated]
allowed-tools:
  - Bash(ssh-key-doctor/check.sh:*)
---

# SSH Key Doctor

> **⚠️ DEPRECATED for canonical VM access (DX V8.3+)**
> All SSH access between canonical VMs MUST use **Tailscale SSH** instead of SSH keys.
> See [AGENTS.md §3](/home/fengning/agent-skills/AGENTS.md) for Tailscale SSH standard.

This skill checks local SSH setup and (optionally) remote reachability for legacy SSH key scenarios.

## Tailscale SSH (Preferred)

```bash
# Enable Tailscale SSH (one-time, requires sudo)
sudo tailscale up --ssh
sudo tailscale set --operator=$USER

# Connect to canonical VMs
tailscale ssh fengning@macmini "command"
ssh fengning@100.117.177.18 "command"  # Direct IP also works

# Check Tailscale connectivity
tailscale ping macmini
tailscale status
```

## Legacy SSH Key Usage

Only use this skill for non-Tailscale SSH scenarios (external servers, GitHub, etc.).

```bash
~/agent-skills/health/ssh-key-doctor/check.sh --local-only
DX_SSH_DOCTOR_REMOTE=1 ~/agent-skills/health/ssh-key-doctor/check.sh --remote-only
~/agent-skills/health/ssh-key-doctor/check.sh --strict
```

## Notes

- Never prints private key material.
- Uses `BatchMode=yes` + short timeouts to avoid hangs.
- GitHub SSH check is opt-in: `--check-github` (skips if `timeout` is unavailable).

## Canonical VMs (Tailscale)

| Host | Tailscale Address | SSH User |
|------|-------------------|----------|
| homedesktop-wsl | `100.109.231.123` or `homedesktop-wsl` | `fengning@` |
| macmini | `100.117.177.18` or `macmini` | `fengning@` |
| epyc6 | `100.101.113.91` or `epyc6` | `feng@` |
