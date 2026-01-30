# Agent Skills

> Global DX skills, scripts, and configurations for AI agent development workflows.

**Purpose:** Standardize agent environment across all VMs and projects in the Stars-End ecosystem.

---

## Prerequisites

- **OS:** Linux (Ubuntu 22.04+ recommended)
- **Sudo access:** Required for package installation (fresh VM only)
- **Basic git knowledge:** clone, pull, push
- **Estimated setup time:** 15-30 minutes (fresh VM), 2-5 minutes (existing VM)

---

## Quick Start (Choose Your Scenario)

### Scenario A: Fresh VM - No Tools Installed

**You are on a new Linux VM with minimal tools.**

```bash
# 1. Clone this repo
git clone https://github.com/stars-end/agent-skills.git ~/agent-skills

# 2. Run the interactive tool installer
cd ~/agent-skills/infra/vm-bootstrap
./install.sh

# 3. Install DX commands (creates dx-* commands)
~/agent-skills/scripts/dx-hydrate.sh

# 4. Verify installation
dx-check

# 5. Restart shell (for PATH changes)
source ~/.bashrc  # or log out and back in
```

**What this installs:** git, curl, jq, ripgrep, tmux, brew, mise, python, poetry, node, pnpm, gh, bd, op, railway, dcg, ru

**Expected:** Some auth warnings (Railway, gh) - these are fixed in "First Steps" below.

---

### Scenario B: Existing VM - Tools Already Installed

**You have a working system but need agent-skills setup.**

```bash
# One-line bootstrap
curl -fsSL https://raw.githubusercontent.com/stars-end/agent-skills/master/scripts/bootstrap-agent.sh | bash

# Verify
dx-check

# Note: If you get "command not found" errors, restart your shell:
source ~/.bashrc  # or log out and back in
```

---

### Scenario C: Partial Setup - Some Tools Missing

**You're not sure if everything is set up correctly.**

```bash
# Run health check
dx-check

# If tools are missing, re-run installer
cd ~/agent-skills/infra/vm-bootstrap
./install.sh

# Then install DX commands
~/agent-skills/scripts/dx-hydrate.sh
```

---

## Understanding Skills

**Skills** are reusable agent workflows stored in this repo. How you invoke them depends on your AI IDE:

| IDE | Command | Example |
|-----|---------|---------|
| **Claude Code** | `/skill <name>` | `/skill core/beads-workflow` |
| **OpenCode** | `skill <name>` | `skill core/beads-workflow` |
| **Codex CLI** | Native auto-discovery | Automatically loads from `~/agent-skills` |
| **Antigravity** | Native auto-discovery | Automatically loads from `~/agent-skills` |

**Beads (bd)** is the issue tracking system. Common commands:
```bash
bd list              # Show all issues
bd create "title"    # Create new issue
bd start bd-xxx      # Start working on issue
bd sync              # Pull latest issue data
```

---

## First Steps After Setup

Once tools are installed, complete your setup:

### 1. Authenticate with Services

```bash
# GitHub CLI (required for PRs)
gh auth login

# Railway (required for deployments)
cd ~/prime-radiant-ai  # or any repo with mise
railway login

# 1Password CLI (optional, for secrets)
op account add
```

### 2. Clone Canonical Repos

```bash
# Main product repos
git clone git@github.com:stars-end/prime-radiant-ai.git ~/prime-radiant-ai
git clone git@github.com:stars-end/affordabot.git ~/affordabot
git clone git@github.com:stars-end/llm-common.git ~/llm-common
```

### 3. Set Up Environment

```bash
# In each repo, install repo-specific tool versions
cd ~/prime-radiant-ai
mise install

# Set up environment variables
railway variables  # Follow prompts
```

**See also:** `docs/SECRET_MANAGEMENT.md` for 1Password setup.

### 4. Your First Task

```bash
cd ~/prime-radiant-ai
bd list                      # Find a good first issue
/skill core/beads-workflow  # Start working
```

---

## Daily Workflow

Once fully set up, your daily workflow is simple:

```bash
cd ~/your-repo
dx-check                    # Verify environment
bd list                     # See current issues
/skill core/beads-workflow  # Start work on an issue
```

---

## What is Agent Skills?

**Agent Skills** is a centralized repository of:

| Component | Purpose |
|-----------|---------|
| **Skills** | Reusable agent workflows (agentskills.io format) |
| **Scripts** | DX commands (dx-check, dx-triage, dx-dispatch) |
| **Configs** | Toolchain versions, env templates, hooks |

### Why It Exists

- **Consistency:** All VMs work the same way
- **Reusability:** Skills work across repos (prime-radiant-ai, affordabot, llm-common)
- **Safety:** Guards against destructive commands (dcg)
- **Durability:** Auto-checkpoint prevents work loss

---

## Directory Structure

```
agent-skills/
├── core/              # Daily workflow skills (issues, PRs, sync)
├── safety/            # Safety guards (dcg, beads-guard)
├── health/            # Diagnostics (bd-doctor, toolchain-health)
├── infra/             # VM setup (vm-bootstrap, canonical-targets)
├── dispatch/          # Cross-VM coordination (multi-agent-dispatch)
├── railway/           # Railway deployment skills
├── search/            # Session search (cass-search)
├── extended/          # Optional workflows (jules, skill-creator)
├── scripts/           # DX commands (dx-*.sh)
├── docs/              # Documentation (START_HERE.md, archive/)
└── lib/               # Shared libraries (fleet, tools)
```

---

## Key Skills

| Skill | Purpose | Usage |
|-------|---------|-------|
| `core/beads-workflow` | Issue tracking | Start/finish features |
| `core/sync-feature-branch` | Save work | Commit + push progress |
| `core/create-pull-request` | Create PR | Automated PR creation |
| `safety/dcg-safety` | Block dangerous commands | Guards git reset --hard, rm -rf |
| `health/toolchain-health` | Verify tools | Check mise, poetry, versions |
| `infra/vm-bootstrap` | Set up new VM | Install all required tools |

**See `AGENTS.md` for complete skill reference.**

---

## DX Commands

These are installed to `~/bin/` by dx-hydrate:

| Command | Purpose |
|---------|---------|
| `dx-check` | Verify environment health |
| `dx-triage` | Diagnose repo state |
| `dx-dispatch` | Cross-VM task dispatch |
| `dx-doctor` | Deep diagnostics |
| `dx-status` | Show repo/environment status |

---

## Documentation Index

| Document | Purpose |
|----------|---------|
| **`docs/START_HERE.md`** | Quick start guide |
| **`AGENTS.md`** | Full reference (skills, tools, workflows) |
| **`DX_AGENT_ID.md`** | Agent identity standard |
| **`infra/vm-bootstrap/SKILL.md`** | VM setup details |
| **`docs/SECRET_MANAGEMENT.md`** | 1Password and secrets setup |
| **`docs/archive/`** | Deprecated documentation |

---

## Integration with Product Repos

**Global skills** (this repo) + **Context skills** (product repos)

| Location | Purpose | Example |
|----------|---------|---------|
| `~/agent-skills/` | Global workflows | Issue tracking, PR creation |
| `.claude/skills/context-*/` | Repo-specific domain knowledge | API contracts, DB schema |

**Never duplicate global skills in product repos.** They are auto-discovered from `~/agent-skills`.

---

## Updating Skills

1. Edit skill in its directory
2. Test with `/skill <name>` (or your IDE's equivalent)
3. Commit and push
4. Other VMs auto-update on shell start

---

## Canonical Repos

This repo integrates with:

| Repo | Purpose |
|------|---------|
| [prime-radiant-ai](https://github.com/stars-end/prime-radiant-ai) | Main product |
| [affordabot](https://github.com/stars-end/affordabot) | Bot platform |
| [llm-common](https://github.com/stars-end/llm-common) | Shared libraries |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `dx-check: command not found` | Run `~/agent-skills/scripts/dx-hydrate.sh` |
| `bd: command not found` | Install: `npm install -g @beads/bd` |
| `mise: command not found` | Install: `curl https://mise.run \| sh` |
| `gh: not authenticated` | Run: `gh auth login` |
| `railway: not authenticated` | Run: `railway login` (in a mise-enabled repo) |
| Railway env vars missing | Run: `railway variables` (in each repo) |
| "Skills not found" | Check `~/.agent/skills` symlink exists |
| `dx-check` shows auth warnings | Expected! Authenticate in "First Steps" |
| `mise exec` errors | Run: `mise use -g <tool>@latest` |

**Still stuck?** Run `dx-doctor` for deep diagnostics.

---

## Getting Help

1. **Run diagnostics:** `dx-check` or `dx-doctor`
2. **Check health:** `/skill health/toolchain-health` (or your IDE's equivalent)
3. **Read docs:** `AGENTS.md` or `docs/START_HERE.md`
4. **Search past sessions:** `/skill search/cass-search`

---

## License

MIT - See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.
