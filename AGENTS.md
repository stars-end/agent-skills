# Nakomi Agent Protocol

> This protocol applies to all agents (Claude Code, Antigravity, Gemini CLI, Codex CLI).

## Role
This agent supports a startup founder balancing high-leverage technical work and family responsibilities. The agent's purpose is not to maximize output, but to maximize *correct progress* while preserving the founder's agency and cognitive bandwidth.

## Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

## Decision Autonomy

| Tier | Agent Autonomy | Examples |
|------|----------------|----------|
| **T0: Proceed** | Act without asking | Formatting, linting, issue creation, git mechanics |
| **T1: Inform** | Act, then report | Refactors within existing patterns, test additions |
| **T2: Propose** | Present options, await selection | Architecture changes, new dependencies, API contracts |
| **T3: Halt** | Do not proceed without explicit instruction | Irreversible actions, scope expansion, external systems |

When uncertain, escalate one tier up.

## Intervention Rules
Act only when: task is blocking, founder is looping, hidden complexity exists, or small clarification unlocks progress.

## Cognitive Load Principles
1. **Continuity over correctness** — If resuming context takes >30s of reading, you've written too much
2. **One decision surface** — Consolidate related choices into a single ask
3. **State, don't summarize** — "Tests pass" not "I ran the test suite which verified..."
4. **Handoff-ready** — Assume another agent will pick up this thread

## Founder Commitments
> Reminder: At session start, remind founder if not addressed.
- Provide priority signal (P0-P4)
- State time/energy constraints upfront
- Explicitly close decision loops ("go with option 2", "not now")

---

# AGENTS.md — Agent Skills V3 DX

**Start Here**
1. **Initialize**: `source ~/.bashrc && dx-check || curl -fsSL https://raw.githubusercontent.com/stars-end/agent-skills/master/scripts/dx-hydrate.sh | bash`
2. **Check Environment**: `dx-check` checks git, Beads, and Skills.

**Core Tools**:
- **Beads**: Issue tracking. Use `bd` CLI.
- **Skills**: Automated workflows.

**Daily Workflow**:
1. `start-feature bd-xxx` - Start work.
2. Code...
3. `sync-feature "message"` - Save work.
4. `finish-feature` - Verify & PR.

---

## Quick Start (5 Commands)

Every agent session starts here:

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `dx-check` | Verify environment |
| 2 | `bd list` | See current issues |
| 3 | `bd create "title" --type task` | Create tracking issue |
| 4 | `/skill core/sync-feature-branch` | Save work |
| 5 | `/skill core/create-pull-request` | Create PR |

### Example: Fix a Bug

```bash
# 1. Check environment
dx-check

# 2. Create tracking issue
bd create "Fix auth timeout bug" --type bug --priority 2

# 3. Start work (creates branch)
/skill core/beads-workflow
# Select: start-feature bd-xxx

# 4. Make your changes...

# 5. Save work
/skill core/sync-feature-branch
# Enter: sync-feature "fixed auth timeout"

# 6. Create PR when done
/skill core/create-pull-request
```

---

## Session Start Bootstrap (Mandatory Sequence)

**Every agent session MUST execute these steps in order:**

### 1. Git Sync
```bash
cd ~/your-repo
git pull origin master
```

**Purpose**: Ensure working directory matches latest team state
**Failure mode**: If pull fails, resolve conflicts before proceeding

### 2. DX Check
```bash
# Canonical baseline check (all repos)
dx-check

# Optional: Full diagnostics
dx-doctor
```

**Purpose**: Preflight check for:
- Canonical clones on trunk + clean (where required)
- Toolchain presence (mise, gh, railway, op, etc.)
- Optional MCP configuration — warn-only

**Failure mode**:
- ❌ Missing REQUIRED items → fix before proceeding
- ⚠️ Missing OPTIONAL items → note but continue

---

## Beads Integration

### Beads State Sync

**Before starting work**:
```bash
bd sync --dry-run  # Check for remote changes
bd sync            # Pull latest JSONL from remote
```

**Failure mode**: Merge conflicts in `.beads/*.jsonl`
- Use `beads-guard` skill for conflict prevention
- Resolve manually if conflicts occur

### Feature-Key Trailers

**All commits MUST include**:
```
Feature-Key: {beads-id}
Agent: {routing-name or DX_AGENT_ID}
Role: {engineer-type}
```

**Examples**:
- `Feature-Key: bd-3871.5`
- `Agent: epyc6-codex-cli` (recommended: use `$DX_AGENT_ID`)
- `Role: backend-engineer`

### Beads CLI Reference

| Command | Purpose |
|---------|---------|
| `bd list` | Show all issues |
| `bd create "title" --type task` | Create new issue |
| `bd start bd-xxx` | Start working on issue |
| `bd sync` | Pull latest JSONL from remote |
| `bd export -o .beads/issues.jsonl` | Export to JSONL |

---

## Skills (agentskills.io Format)

Skills are stored in `~/agent-skills/*/SKILL.md` using the [agentskills.io](https://agentskills.io) open standard.

## Skill Categories

Skills are organized into categories for easy discovery:

| Category | Purpose | When to Use |
|----------|---------|-------------|
| `core/` | Daily workflow | Every session - creating issues, syncing work, PRs |
| `safety/` | Safety guards | Auto-loaded - prevents destructive commands |
| `health/` | Diagnostics | When something isn't working right |
| `infra/` | VM/environment | Setting up new VMs or debugging environment |
| `dispatch/` | Cross-VM work | When task needs another VM (GPU, macOS) |
| `railway/` | Railway deployment | Deploying to Railway |
| `search/` | Context/history | Finding past solutions or building context |
| `extended/` | Advanced workflows | Optional - parallelization, planning, etc. |

### Finding Skills by Need

| Need | Skill | Category |
|------|-------|----------|
| Create/track issues | `/skill core/beads-workflow` | core/ |
| Save work | `/skill core/sync-feature-branch` | core/ |
| Create PR | `/skill core/create-pull-request` | core/ |
| Dispatch to another VM | `/skill dispatch/multi-agent-dispatch` | dispatch/ |
| Deploy to Railway | `/skill railway/deploy` | railway/ |
| Search past sessions | `/skill search/cass-search` | search/ |
| Debug environment | `/skill health/bd-doctor` | health/ |
| Set up new VM | `/skill infra/vm-bootstrap` | infra/ |

**Agent Skill Discovery:**

| Agent | Discovery Method |
|-------|------------------|
| Claude Code | Native `/skill <name>` command |
| OpenCode | Native `skill <name>` tool |
| Codex CLI | Native skill loading |
| Antigravity | Native slash commands |
| Gemini CLI | Native skill loading |

**Available Skills:**
- `multi-agent-dispatch` - Cross-VM task dispatch
- `beads-workflow` - Issue tracking with dependency management
- `sync-feature-branch` - Git workflows
- `fix-pr-feedback` - PR iteration
- `dcg-safety` - Destructive command guard (blocks dangerous git/rm commands)
- `bv-integration` - Beads Viewer and robot-plan API
- `cass-search` - Search past agent sessions

---

## Safety Tools

**DCG (Destructive Command Guard)**: Blocks dangerous commands before execution.

```bash
# Test DCG blocking
dcg explain "git reset --hard"

# What it blocks: git reset --hard, rm -rf /, git push --force
# What it allows: git status, git diff, rm temp files
```

**Installed on**: homedesktop-wsl, macmini (epyc6 uses fallback)

---

## Smart Task Selection

Use **BV** for intelligent task prioritization:

```bash
# Get next highest-impact task
bv --robot-plan | jq '.summary.highest_impact'

# Or via lib/fleet:
python3 -c "from lib.fleet import FleetDispatcher; print(FleetDispatcher().auto_select_task('affordabot'))"
```

---

## Session Search

Use **CASS** to search past agent work:

```bash
# Find how something was solved before
cass search "authentication oauth"

# Check indexed sessions
cass stats
```

**Installed on**: homedesktop-wsl, macmini (epyc6 blocked by GLIBC)


## When You Need More

### Cross-VM Dispatch

Use when task needs specific VM capabilities:

```bash
# SSH dispatch to canonical VMs
dx-dispatch epyc6 "Run GPU tests in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch homedesktop-wsl "Run integration tests"

# Check VM status
dx-dispatch --list

# Jules Cloud dispatch (async)
dx-dispatch --jules --issue bd-123
```

### Environment Issues

```bash
# Quick health check
dx-check

# Full diagnostics
/skill health/bd-doctor
/skill health/mcp-doctor
/skill health/toolchain-health
```

### Fleet Operations

```bash
# Finalize PR for a session
dx-dispatch --finalize-pr ses_abc123 --beads bd-123

# Abort a running session
dx-dispatch --abort ses_abc123
```

---

## Multi-Agent Dispatch

`dx-dispatch` is the canonical tool for cross-VM and cloud dispatch.

### SSH Dispatch (default)

```bash
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch --list  # Check VM status
```

### Jules Cloud Dispatch

```bash
dx-dispatch --jules --issue bd-123
dx-dispatch --jules --issue bd-123 --dry-run  # Preview prompt
```

### Canonical VMs

| VM | User | Capabilities |
|----|------|--------------|
| homedesktop-wsl | fengning | Primary dev, DCG, CASS |
| macmini | fengning | macOS builds, iOS |
| epyc6 | feng | GPU work, ML training |

**Add Slack notifications** to long tasks:
```
After completing, use slack_conversations_add_message
to post summary to channel C09MQGMFKDE.
```

📖 **Full guide**: [docs/MULTI_AGENT_COMMS.md](docs/MULTI_AGENT_COMMS.md)



## Claude CLI: Always Use `cc-glm`

**`cc-glm`** is a pre-configured Claude Code alias (defined in `~/.zshrc`) that:
- Uses the correct model configuration
- Handles authentication automatically
- Supports all standard `claude` flags

```bash
# Interactive session
cc-glm

# Non-interactive (one-shot)
cc-glm -p "Your prompt here"

# With output format
cc-glm -p "Prompt" --output-format text

# Resume session
cc-glm --resume <session-id>
```

**RULE:** Always use `cc-glm` instead of raw `claude` command.

---

**Repo Context: Skills Registry**
- **Purpose**: Central store for all agent skills, scripts, and configurations.
- **Rules**:
  - Scripts must be idempotent.
  - `dx-hydrate.sh` is the single source of truth for setup.

## dx-* Commands Reference

### Core Commands (use frequently)

| Command | Purpose |
|---------|---------|
| `dx-check` | Verify environment (git, Beads, skills) |
| `dx-triage` | Diagnose repo state + safe recovery (see below) |
| `dx-dispatch` | Cross-VM and cloud dispatch |
| `dx-status` | Show repo and environment status |

### Optional Commands (use when needed)

| Command | Purpose |
|---------|---------|
| `dx-doctor` | Deep environment diagnostics |
| `dx-toolchain` | Verify toolchain consistency |
| `dx-worktree` | Manage git worktrees |
| `dx-fleet-status` | Check all VMs at once |

### dx-triage: Repo State Diagnosis

When repos are in mixed states (different branches, uncommitted work, staleness), use `dx-triage`:

```bash
# Show current state of all repos
dx-triage

# Apply safe fixes only (pull stale, reset merged branches)
dx-triage --fix

# Force reset ALL to trunk (DANGEROUS - stashes WIP first)
dx-triage --force
```

**States detected:**
| State | Meaning | Action |
|-------|---------|--------|
| OK | On trunk, clean, up-to-date | None needed |
| STALE | On trunk, behind origin | Safe to pull |
| DIRTY | Uncommitted changes | Review first |
| FEATURE-MERGED | On merged feature branch | Safe to reset |
| FEATURE-ACTIVE | On unmerged feature branch | Finish or discard |

**Key principle:** `dx-triage --fix` only does SAFE operations. It never touches DIRTY or FEATURE-ACTIVE repos.


---

## Product Repo Integration

The agent-skills repo provides global workflow skills, while each product repo has repo-specific context skills.

### Skill Architecture

| Location | Purpose | Managed By |
|----------|---------|------------|
| `~/agent-skills/` | Global workflows and automation | Centrally |
| `.claude/skills/context-*/` | Repo-specific domain knowledge | Per repo |

### Product Repos

| Repo | Context Location | Skills | Auto-Update |
|------|-----------------|--------|-------------|
| [prime-radiant-ai](https://github.com/stars-end/prime-radiant-ai) | `.claude/skills/context-*/` | 16 | ✅ |
| [affordabot](https://github.com/stars-end/affordabot) | `.claude/skills/context-*/` | 12 | ✅ |
| [llm-common](https://github.com/stars-end/llm-common) | `.claude/skills/context-*/` | 3 | ✅ |

### Key Principle

**Global skills in `~/agent-skills`** are for workflows that apply to all repos (issue tracking, PR creation, git operations).

**Context skills in `.claude/skills/context-*`** are for repo-specific domain knowledge (API contracts, database schema, infrastructure patterns).

Never duplicate global skills in product repos. They are auto-discovered from `~/agent-skills`.

---

## Platform-Specific Session Start Hooks

For automated bootstrap at session start, configure these hooks in your IDE:

### Claude Code

**SessionStart hook** (`.claude/hooks/SessionStart/dx-bootstrap.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Git sync
git pull origin master || echo "⚠️  git pull failed (resolve conflicts)"

# 2. DX check
dx-check || true

# 3. Optional coordinator stack checks
dx-doctor || true

echo "✅ DX bootstrap complete"
```

### Codex CLI

**Config** (`~/.codex/config.toml`):
```toml
[session]
on_start = "bash ~/.agent/skills/session-start-hooks/dx-bootstrap.sh"
```

### Antigravity

**Config** (`~/.antigravity/config.yaml`):
```yaml
session:
  on_start:
    - git pull origin master
    - dx-check || true
    - dx-doctor || true
```

**See also**: `docs/IDE_SPECS.md` for full IDE configuration details.

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
