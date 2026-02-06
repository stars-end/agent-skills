# Universal Baseline — Agent Skills
<!-- AUTO-GENERATED -->
<!-- Source SHA: 6f9b3353a68abfa78f3f0883d1fa271678ac7ddd -->
<!-- Last updated: 2026-02-06T05:56:19-08:00 -->
<!-- Regenerate: make publish-baseline -->

## Operating Contract (Layer A — Curated)

## Nakomi Agent Protocol

### Role
Support a startup founder balancing high-leverage technical work and family responsibilities.

### Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

### Decision Autonomy

| Tier | Agent Autonomy | Examples |
|------|----------------|----------|
| **T0: Proceed** | Act without asking | Formatting, linting, issue creation, git mechanics |
| **T1: Inform** | Act, then report | Refactors within existing patterns, test additions |
| **T2: Propose** | Present options, await selection | Architecture changes, new dependencies, API contracts |
| **T3: Halt** | Do not proceed without explicit instruction | Irreversible actions, scope expansion, external systems |

When uncertain, escalate one tier up.

## Canonical Repository Rules

**Canonical repositories** (read-mostly clones):
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

### Enforcement

**Primary**: Git pre-commit hook blocks commits when not in worktree

**Safety net**: Daily sync to origin/master (non-destructive)
- Runs: 3am daily on all VMs
- Purpose: Ensure canonical clones stay aligned
- Note: Does NOT reset uncommitted changes

### V7.6: Sweeper Enforcement

The **dx-sweeper** handles dirty canonicals automatically:
- Creates rolling rescue PR per host+repo (bounded)
- Resets canonical to clean master after preserving work
- See: `fragments/v7.6-mechanisms.md`

### Workflow

Always use worktrees for development:

```bash
dx-worktree create bd-xxxx repo-name
cd /tmp/agents/bd-xxxx/repo-name
# Work here
```

### Recovery

If you accidentally commit to canonical:

```bash
cd ~/repo
git reflog | head -20
git show <commit-hash>

# Recover to worktree
dx-worktree create bd-recovery repo
cd /tmp/agents/bd-recovery/repo
git cherry-pick <commit-hash>
git push origin bd-recovery
```

**Or**: Let dx-sweeper handle it (rescue PR will be created automatically)

## External Beads Database (CRITICAL)

### Requirement

ALL agents MUST use centralized external beads database:

```bash
export BEADS_DIR="$HOME/bd/.beads"
```

### Verification

Every session:

```bash
echo $BEADS_DIR
# Expected: /home/fengning/bd/.beads

# If not set:
cd ~/agent-skills
./scripts/migrate-to-external-beads.sh
source ~/.zshrc
```

### Architecture

```
~/bd/.beads/              (Central database)
├── beads.db              (SQLite)
├── issues.jsonl          (Export)
├── config.yaml           (Config)
└── .git/                 (Multi-VM sync)
```

### Why External DB

| Problem | Solution |
|---------|----------|
| `.beads/` causes git conflicts | External DB separate from code |
| Each repo isolated | Single shared database |
| Multi-VM sync complex | One `~/bd` repo via git |
| Agent context fragments | All agents see same issues |

### Cross-VM Sync (Required for durability)

- `~/bd` should be a git repo with remote `stars-end/bd`.
- If `bd doctor` reports a **Repo Fingerprint mismatch**, run:
  ```bash
  cd ~/bd
  printf 'y\n' | bd migrate --update-repo-id
  ```
```

## Session Start Bootstrap

Every agent session MUST execute these steps:

### 1. Git Sync

```bash
cd ~/your-repo
git pull origin master
```

### 2. DX Check

```bash
dx-check  # Baseline check
dx-doctor  # Full diagnostics (optional)
```

### 3. Verify BEADS_DIR

```bash
echo $BEADS_DIR
# Expected: /home/$USER/bd/.beads
```

### 4. Create a Workspace (V7.6)

Before making **any** file changes, you MUST work in a workspace (worktree), not a canonical clone:

```bash
dx-worktree create <beads-id> <repo>
cd /tmp/agents/<beads-id>/<repo>
```

**Rule:** If you find yourself editing `~/<repo>` (canonical), STOP and create a worktree.

See: `fragments/v7.6-mechanisms.md`

## Landing the Plane (Session Completion)

When ending a work session, MUST complete ALL steps:

1. **File issues** for remaining work
2. **Run quality gates** (if code changed)
3. **Update issue status**
4. **PUSH TO REMOTE** (MANDATORY):
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Verify canonicals are clean** (V7.6):
   ```bash
   ~/agent-skills/scripts/dx-verify-clean.sh
   ```
6. **Clean up** - Clear stashes, prune branches
7. **Verify** - All changes committed AND pushed
8. **Hand off** - Provide context for next session

**CRITICAL**: Work is NOT complete until `git push` succeeds.

### PR-or-It-Didn't-Happen (V7.6)

After landing the plane:
- Canonical work → Sweeper creates rescue PR automatically
- Worktree work → Ensure PR exists (Janitor will create draft if missing)
- No PR visibility = Work is invisible and at risk

See: `fragments/v7.6-mechanisms.md` for sweeper/janitor details

## DX Fleet V7.6 Mechanisms

Fleet automation for bounded, visible work with minimal cognitive load.

### Reality Check (Why V7.6 Exists)

Agents will sometimes violate the “no writes in canonicals” rule (even capable agents), especially during complex multi-repo work.

V7.6 is **mechanical self-healing**:
- Move hidden local state → visible PRs (bounded)
- Restore canonicals → clean trunk
- Remove “archaeology” (stashes/branches) as the default recovery path

### Sweeper vs Janitor

| Aspect | Sweeper (dx-sweeper) | Janitor (dx-janitor) |
|--------|---------------------|---------------------|
| **Scope** | Canonical repos only | Worktrees only |
| **Trigger** | Dirty OR branch≠master | Unpushed commits OR no PR |
| **Action** | Rescue branch + PR + reset canonical | Push commits + create draft PR |
| **Safety** | Index.lock check; preserve-before-reset | Non-destructive; never closes PRs |
| **Destructive** | Yes (resets canonical after rescue) | No (never delete/close) |

### Canonical Sweeper (dx-sweeper)

**Purpose:** Convert dirty canonical state to rescue PR, restore clean master.

**Rescue Branch Naming (Rolling):**
```
canonical-rescue-<host>-<repo>
```

**Rolling Rescue PR Contract (Bounded Inbox):**
- Exactly one open rescue PR per `<host>,<repo>` pair
- Title: `chore: [RESCUE] canonical rescue (<host> <repo>)`
- Labels: `wip/rescue`, `host/<host>`, `repo/<repo>`
- PR head branch is the rolling rescue branch above
- Body updated with: "Latest rescue commit: `<sha>` @ `<time>`"

**Safety Gates:**
1. Skip if `.git/index.lock` exists
2. Preserve before reset:
   - If canonical is on a feature branch with commits, push that branch first (even if it has no upstream)
3. Only reset after rescue push succeeds

**Recovery Process:**
```
Dirty canonical → Create rescue branch → Commit changes → Push → 
Update/create rescue PR → Reset canonical to origin/master
```

### Worktree Janitor (dx-janitor)

**Purpose:** Ensure worktree durability (pushed + PR exists).

**Quiet Mode Principles:**
- No duplicate PRs for same branch
- Minimal notification churn
- Label-only updates for existing PRs

**Abandonment Detection (Optional, Manual-First):**
- Trigger: PR has `wip:abandon` label
- Threshold: >72 hours old AND still draft
- Action: Inform only (no automatic closure)

**Labels:**
- `wip/worktree` - Auto-applied to all worktree PRs
- `wip:abandon` - Manual marker for stale work

### Baseline Sync

**Product Repos:** Self-update via GitHub Actions
- `baseline-sync.yml` - Daily rolling PR for baseline updates
- `verify-agents-md.yml` - Fail if AGENTS.md is stale
- No per-VM cron required
- No cross-repo tokens needed

**Fragment Architecture:**
```
fragments/
├── v7.6-mechanisms.md     (this file)
├── canonical-rules.md     (updated for V7.6)
├── session-start.md       (worktree-first)
├── landing-the-plane.md   (dx-verify-clean)
└── universal-baseline.md  (generated)
```

### Deterministic Automation

**Sweeper/Janitor:** Pure bash, no LLM
- Deterministic logic
- Predictable outcomes
- Fast execution

**LLM Triage (Optional):** GitHub Actions only
- Classifies PRs: `SAFE_TO_MERGE`, `NEEDS_REVIEW`, `ABANDON_CANDIDATE`
- Applies labels and comments only
- Never touches branches or pushes

### Rollout Schedule

| Week | Phase | Scope |
|------|-------|-------|
| 1 | Manual runs | homedesktop-wsl only |
| 2 | Sweeper cron | Daily 2am (before 3am canonical-sync) |
| 3 | Janitor cron | Business hours |
| 4 | Multi-VM + abandon | macmini, epyc6; wip:abandon automation |

### Commands

```bash
# Manual sweeper (dry-run)
dx-sweeper --dry-run --verbose

# Manual janitor (dry-run)
dx-janitor --dry-run --verbose

# Production runs (via cron)
~/agent-skills/scripts/dx-sweeper.sh
~/agent-skills/scripts/dx-janitor.sh
```

---

## Universal Skill Index (Layer B — Generated)

### Core Workflows

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| beads-workflow | Beads issue tracking and workflow management with automatic  | `See SKILL.md` | workflow,beads,issue-tracking,git |
| create-pull-request | Create GitHub pull request with atomic Beads issue closure.  | `See SKILL.md` | workflow,github,pr,beads,review |
| feature-lifecycle | A suite of skills to manage the full development lifecycle f | `See SKILL.md` | workflow,git,feature,beads,dx |
| finish-feature | Complete epic with cleanup and archiving, or verify feature  | `See SKILL.md` | workflow,beads,cleanup,archiving |
| fix-pr-feedback | Address PR feedback with iterative refinement. MUST BE USED  | `See SKILL.md` | workflow,pr,beads,debugging,iteration |
| issue-first | Enforce Issue-First pattern by creating Beads tracking issue | `See SKILL.md` | workflow,beads,issue-tracking,implementation |
| merge-pr | Prepare PR for merge and guide human to merge via GitHub web | `See SKILL.md` | workflow,pr,github,merge,deployment |
| session-end | End Claude Code session with Beads sync and summary. MUST BE | `See SKILL.md` | workflow,beads,session,cleanup |
| sync-feature-branch | Commit current work to feature branch with Beads metadata tr | `See SKILL.md` | workflow,git,beads,commit |

### Extended Workflows

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| bv-integration | Beads Viewer (BV) integration for visual task management and | `See SKILL.md` | workflow,beads,visualization,task-selection |
| coordinator-dx | Coordinator playbook for running multi‑repo, multi‑VM wo | `See SKILL.md` |  |
| jules-dispatch | Dispatches work to Jules agents via the CLI. Automatically g | `See SKILL.md` | workflow,jules,cloud,automation,dx |
| lint-check | Run quick linting checks on changed files. MUST BE USED when | `See SKILL.md` | workflow,quality,linting,validation |
| parallelize-cloud-work | Delegate independent work to Claude Code Web cloud sessions  | `See SKILL.md` | workflow,cloud,parallelization,dx |
| plan-refine | Iteratively refine implementation plans using the "Convexity | `See SKILL.md` | architecture,planning,review,refinement,apr |
| skill-creator | Create new Claude Code skills following V3 DX patterns with  | `See SKILL.md` | meta,skill-creation,automation,v3 |
| slack-coordination | Optional coordinator stack: Slack-based coordination loops ( | `See SKILL.md` | slack,coordination,workflow,optional |
| worktree-workflow | Create and manage task workspaces using git worktrees (witho | `See SKILL.md` | dx,git,worktree,workspace,workflow |

### Health & Monitoring

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| bd-doctor | Check and fix common Beads workflow issues across all repos. | `See SKILL.md` |  |
| lockfile-doctor | Check and fix lockfile drift across Poetry (Python) and pnpm | `See SKILL.md` |  |
| mcp-doctor | Warn-only health check for canonical MCP configuration and r | `See SKILL.md` | dx,mcp,health,verification |
| railway-doctor | Pre-flight checks for Railway deployments to catch failures  | `See SKILL.md` | railway,deployment,validation,pre-flight |
| skills-doctor | Validate that the current VM has the right `agent-skills` in | `See SKILL.md` |  |
| ssh-key-doctor | Fast, deterministic SSH health check for canonical VMs (no h | `See SKILL.md` | dx,ssh,verification |
| toolchain-health | Validate Python toolchain alignment between mise, Poetry, an | `See SKILL.md` | dx,tooling,python |
| verify-pipeline | Run project verification checks using standard Makefile targ | `See SKILL.md` | workflow,testing,verification,makefile,railway |

### Infrastructure

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| canonical-targets | Single source of truth for canonical VMs, canonical IDEs, an | `See SKILL.md` | dx,ide,vm,canonical,targets |
| devops-dx | GitHub/Railway housekeeping for CI env/secret management and | `See SKILL.md` | devops,github,env,ci,railway |
| dx-alerts | Lightweight “news wire” for DX changes and breakages, po | `See SKILL.md` |  |
| github-runner-setup | GitHub Actions self-hosted runner setup and maintenance. Use | `See SKILL.md` | github-actions,devops,runner,systemd,infrastructure |
| vm-bootstrap | Linux VM bootstrap verification skill. MUST BE USED when set | `See SKILL.md` | dx,tooling,setup,linux |

### Railway Deployment

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| database | This skill should be used when the user wants to add a datab | `See SKILL.md` |  |
| deploy | This skill should be used when the user wants to push code t | `See SKILL.md` |  |
| deployment | This skill should be used when the user wants to manage Rail | `See SKILL.md` |  |
| domain | This skill should be used when the user wants to add a domai | `See SKILL.md` |  |
| environment | This skill should be used when the user asks "what's the con | `See SKILL.md` |  |
| metrics | This skill should be used when the user asks about resource  | `See SKILL.md` |  |
| new | This skill should be used when the user says "setup", "deplo | `See SKILL.md` |  |
| projects | This skill should be used when the user wants to list all pr | `See SKILL.md` |  |
| railway-docs | This skill should be used when the user asks about Railway f | `See SKILL.md` |  |
| service | This skill should be used when the user asks about service s | `See SKILL.md` |  |
| status | This skill should be used when the user asks "railway status | `See SKILL.md` |  |
| templates | This skill should be used when the user wants to add a servi | `See SKILL.md` |  |


---

**Discovery**: Skills auto-load from `~/agent-skills/{core,extended,health,infra,railway}/*/SKILL.md`  
**Details**: Each skill's SKILL.md contains full documentation  
**Specification**: https://agentskills.io/specification  
**Source**: Generated from agent-skills commit shown in header
