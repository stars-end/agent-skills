# START HERE (90% workflow)

This repo standardizes your agent environment across canonical VMs.

## One-time setup (per VM)

```bash
cd ~
git clone git@github.com:stars-end/agent-skills.git
~/agent-skills/scripts/dx-hydrate.sh
dx-check
```

`dx-hydrate` installs the control-plane commands into `~/bin` and enables **auto-checkpoint** (periodic WIP commits so work is not lost).

## Daily workflow (one agent per repo)

```bash
cd ~/your-repo
dx-check
```

Then use your agent IDE (Claude Code / Codex CLI / Antigravity) as normal.

### Manual save (when in doubt)

Use the repo workflow skill if available (preferred), otherwise:

```bash
git add -A
git commit -m "WIP: save progress"
git push
```

## Auto-checkpoint (durability)

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

## If `dx-check` fails

Run:
```bash
dx-check
```

If tools are missing, use:
```bash
dx-toolchain ensure
```

