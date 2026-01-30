# START HERE

This repo standardizes your agent environment across canonical VMs.

## Quick Start (Choose One)

### Option A: Fresh VM - Need Tools Installed

**Use this for:** New VMs, systems missing required tools

```bash
# Interactive tool installer (prompts before each install)
cd ~/agent-skills/infra/vm-bootstrap
./install.sh
```

**What it installs:** git, curl, jq, ripgrep, tmux, brew, mise, python, poetry, node, pnpm, gh, bd

**Full documentation:** `infra/vm-bootstrap/SKILL.md`

---

### Option B: Quick Bootstrap - Tools Already Installed

**Use this for:** Existing systems, quick refresh

```bash
# One-line bootstrap
curl -fsSL https://raw.githubusercontent.com/stars-end/agent-skills/master/scripts/bootstrap-agent.sh | bash
```

**What it does:** Clones agent-skills, runs dx-hydrate, runs dx-check

---

## One-Time Setup (per VM)

After running either option above:

```bash
# Restart shell or source
source ~/.bashrc  # or source ~/.zshrc

# Verify installation
dx-check
```

`dx-hydrate` installs control-plane commands into `~/bin` and enables **auto-checkpoint** (periodic WIP commits so work is not lost).

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

## Auto-Checkpoint (durability)

Status:
```bash
auto-checkpoint-install --status
```

Run now:
```bash
auto-checkpoint-install --run
```

Disable scheduler (not recommended):
```bash
auto-checkpoint-install --uninstall
```

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
| VM bootstrap details | `infra/vm-bootstrap/SKILL.md` |
| Archived docs | `docs/archive/` |
