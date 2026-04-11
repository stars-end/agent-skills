# START HERE

This repo standardizes your agent environment across canonical VMs.

## Current Status

The fresh-device bootstrap surface is under cleanup. Do not use
`scripts/bootstrap-agent.sh` or `scripts/dx-hydrate.sh` as a fresh-device
one-liner until they are converted into role-aware shims.

Use the active contract in `docs/FRESH_DEVICE_BOOTSTRAP_AUDIT.md` when setting
up a new host.

## Quick Start (Current Safe Path)

### Linux VM - Need Tools Installed

**Use this for:** Linux VMs missing required tools. This is not the macOS
bootstrap path.

```bash
# Interactive tool installer (prompts before each install)
cd ~/agent-skills/infra/vm-bootstrap
./install.sh
```

**What it installs:** git, curl, jq, ripgrep, tmux, brew, mise, python, poetry, node, pnpm, gh, bd

**Full documentation:** `infra/vm-bootstrap/SKILL.md`

---

### Existing Host - Verify, Then Repair Explicitly

```bash
~/agent-skills/health/bd-doctor/check.sh
~/agent-skills/health/mcp-doctor/check.sh
~/agent-skills/scripts/dx-fleet-check.sh --local-only --json
```

Run targeted repair scripts only for the failed surface. Do not source shell RC
files as part of bootstrap.

---

## One-Time Setup (per VM)

After running setup or repair:

```bash
# Verify installation
bd dolt test --json
```

DX command contract:
- `dx-check` is the default health + fix entrypoint.
- `dx-status` is read-only diagnostics.
- `dx-hydrate` is legacy broad bootstrap/repair and should not be used as a
  fresh-device one-liner.
- There is no separate `dx-health` command.

---

## Daily Workflow

```bash
cd ~/your-repo
dx-check
```

Then use your agent IDE (Claude Code / Codex CLI / Antigravity) as normal.

### Manual Save (when in doubt)

Use the repo workflow skill if available (preferred), otherwise:

```bash
git add -A
git commit -m "WIP: save progress"
git push
```

---

## Durability

V8 uses worktree discipline, canonical sync, and scheduled DX hygiene jobs.
Auto-checkpoint is not part of the active bootstrap contract.

---

## Troubleshooting

### If `dx-check` fails

```bash
dx-check
```

### If tools are missing

```bash
# Re-run tool installer
cd ~/agent-skills/infra/vm-bootstrap
./install.sh
```

---

## Documentation Index

| Topic | Location |
|--------|----------|
| Full tool reference | `AGENTS.md` |
| Fresh-device bootstrap audit | `docs/FRESH_DEVICE_BOOTSTRAP_AUDIT.md` |
| VM bootstrap details | `infra/vm-bootstrap/SKILL.md` |
| Archived docs | `docs/archive/` |
