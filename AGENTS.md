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

## Skills (agentskills.io Format)

Skills are stored in `~/agent-skills/*/SKILL.md` using the [agentskills.io](https://agentskills.io) open standard.

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



## Multi-Agent Dispatch

**When to use**: Tasks needing specific VMs (GPU work → epyc6, macOS → macmini), parallel execution, or status notifications.

```bash
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch --list   # Check VM status
```

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
