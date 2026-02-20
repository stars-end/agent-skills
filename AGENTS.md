# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED -->
<!-- Source SHA: eedddf5739ec3994c451ba90d31dccd31fc6bdaa -->
<!-- Last updated: 2026-02-20 02:19:16 UTC -->
<!-- Regenerate: make publish-baseline -->

## Nakomi Agent Protocol
### Role
Support a startup founder balancing high-leverage technical work and family responsibilities.
### Core Constraints
- Do not make irreversible decisions without explicit instruction
- Do not expand scope unless asked
- Do not optimize for cleverness or novelty
- Do not assume time availability

## 1) Canonical Repository Rules
**Canonical repositories** (read-mostly clones):
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

### Enforcement
**Primary**: Git pre-commit hook blocks commits when not in worktree
**Safety net**: Daily sync to origin/master (non-destructive)

### Workflow
Always use worktrees for development:
```bash
dx-worktree create bd-xxxx repo-name
cd /tmp/agents/bd-xxxx/repo-name
# Work here
```

## 2) V8 DX Automation Rules
1. **No auto-merge**: never enable auto-merge on PRs — humans merge
2. **No PR factory**: one PR per meaningful unit of work
3. **No canonical writes**: always use worktrees
4. **Feature-Key mandatory**: every commit needs `Feature-Key: bd-<beads-id>`

## 3) PR Metadata Rules (Blocking In CI)
- **PR title must include a Feature-Key**: include `bd-<beads-id>` somewhere in the title (e.g. `bd-f6fh: ...`)
- **PR body must include Agent**: add a line like `Agent: <agent-id>`

## 4) Delegation Rule (V8.3 - Batch by Outcome)
- **Primary rule**: batch by outcome, not by file. One agent per coherent change set.
- **Default parallelism**: 2 agents, scale to 3-4 only when independent and stable.
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, commit/push with required trailers.
- **See Section 6** for detailed parallel orchestration patterns.

## 5) Secrets + Env Sources (V8.3 - Railway Context Mandatory)
- **Railway shell is MANDATORY for dev work**: provides `RAILWAY_SERVICE_FRONTEND_URL`, `RAILWAY_SERVICE_BACKEND_URL`, and all env vars.
- **API keys**: `op://dev/Agent-Secrets-Production/<FIELD>` (transitional, see SECRETS_INDEX.md).
- **Railway CLI token**: `op://dev/Railway-Delivery/token` for CI/automation.
- **Quick reference**: use the `op-secrets-quickref` skill.

## 6) Parallel Agent Orchestration (V8.3)

### Pattern: Plan-First, Batch-Second, Commit-Only

1. **Create plan** (file for large/cross-repo, Beads notes for small)
2. **Batch by outcome** (1 agent per repo or coherent change set)
3. **Execute in waves** (parallel where dependencies allow)
4. **Commit-only** (agents commit, orchestrator pushes once per batch)

### Task Batching Rules

| Files | Approach | Plan Required |
|-------|----------|---------------|
| 1-2, same purpose | Single agent | Mini-plan in Beads |
| 3-5, coherent change | Single agent | Plan file recommended |
| 6+ OR cross-repo | Batched agents | Full plan file required |

### Dispatch Method

**Canonical: dx-runner (governed multi-provider runner)**

```bash
# OpenCode throughput lane
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt

# Shared monitoring/reporting
dx-runner status --json
dx-runner check --beads bd-xxx --json
```

**Direct OpenCode lane (advanced, non-governed)**

```bash
# Headless single-run lane
opencode run -m zai-coding-plan/glm-5 "Implement task T1 from plan.md"

# Server lane for parallel clients
opencode serve --hostname 127.0.0.1 --port 4096
opencode run --attach http://127.0.0.1:4096 -m zai-coding-plan/glm-5 "Implement task T2 from plan.md"
```

**Reliability backstop: cc-glm via dx-runner**

```bash
# Start governed fallback job
dx-runner start --provider cc-glm --beads bd-xxx --prompt-file /tmp/p.prompt

# Monitor fallback jobs
dx-runner status --json
dx-runner check --beads bd-xxx --json
```

**Optional: Task tool (Codex runtime only)**

```yaml
Task:
  description: "T1: [batch name]"
  prompt: |
    You are implementing task T1 from plan.md.
    ## Context
    - Dependencies: [T1 has none / T2, T3 complete]
    ## Your Task
    - repo: [repo-name]
    - location: [file1, file2, ...]
    ## Instructions
    1. Read all files first
    2. Implement changes
    3. Commit (don't push)
    4. Return summary
  run_in_background: true
```

**Cross-VM: dx-dispatch** (compat wrapper to `dx-runner` for remote execution)

### Monitoring (Simplified)

- **Check interval**: 5 minutes
- **Signals**: 1) Process alive, 2) Log advancing
- **Restart policy**: 1 restart max, then escalate
- **Check**: `ps -p [PID]` and `tail -20 [log]`

### Anti-Patterns

- One agent per file (overhead explosion)
- No plan file for cross-repo work (coordination chaos)
- Push before review (PR explosion)
- Multiple restarts (brittle)

### Fast Path for Small Work

For 1-2 file changes, use Beads notes instead of plan file:

```markdown
## bd-xxx: Task Name
### Approach
- File: path/to/file
- Change: [what]
- Validation: [how]
### Acceptance
- [ ] File modified
- [ ] Validation passed
- [ ] PR merged
```

References:
- `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
- `~/agent-skills/docs/SECRET_MANAGEMENT.md`
- `~/agent-skills/scripts/benchmarks/opencode_cc_glm/README.md`
- `~/agent-skills/extended/dx-runner/SKILL.md`
- `~/agent-skills/extended/cc-glm/SKILL.md`

Notes:
- PR metadata enforcement exists to keep squash merges ergonomic.
- If unsure what to use for Agent, use platform id (see `DX_AGENT_ID.md`).

---

## Core Workflows

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **beads-workflow** | Beads issue tracking and workflow management with automatic git branch creation. MUST BE USED for Beads operations. Handles full epic→branch→work lifecycle, dependencies, and ready task queries. Use when creating epics/features (auto-creates branch), tracking work, finding ready issues, or managing dependencies, or when user mentions "create issue", "track work", "bd create", "find ready tasks", issue management, dependencies, work tracking, or Beads workflow operations. | `bd create --title "Impl: OAuth" --type feature --dep "bd-res` | workflow, beads, issue-tracking, git |
| **create-pull-request** | Create GitHub pull request with atomic Beads issue closure. MUST BE USED for opening PRs. Asks if work is complete - if YES, closes Beads issue BEFORE creating PR (JSONL merges atomically with code). If NO, creates draft PR with issue still open. Automatically links Beads tracking and includes Feature-Key. Use when user wants to open a PR, submit work for review, merge into master, or prepare for deployment, or when user mentions "ready for review", "create PR", "open PR", "merge conflicts", "CI checks needed", "branch ahead of master", PR creation, opening pull requests, deployment preparation, or submitting for team review. | `bd create --title <FEATURE_KEY> --type feature --priority 2 ` | workflow, github, pr, beads, review |
| **database-quickref** | Quick reference for Railway Postgres operations. Use when user asks to check database, run queries, verify data, inspect tables, or mentions psql, postgres, database, "check the db", "validate data". | — | database, postgres, railway, psql |
| **feature-lifecycle** | A suite of skills to manage the full development lifecycle from start to finish. - `start-feature`: Initializes a new feature branch, docs, and story. - `sync-feature`: Saves work with CI checks. - `finish-feature`: Verifies and creates a pull request. | — | workflow, git, feature, beads, dx |
| **finish-feature** | Complete epic with cleanup and archiving, or verify feature already closed. MUST BE USED when finishing epics/features. For epics: Verifies children closed, archives docs, closes epic. For features/tasks/bugs: Verifies already closed (from PR creation), archives docs. Non-epic issues must be closed at PR creation time (atomic merge pattern). Use when user says "I'm done with this epic", "finish the feature", "finish this epic", "archive this epic", or when user mentions epic completion, cleanup, archiving, feature finalization, or closing work. | `bd close bd-abc.2 --reason 'Completed'` | workflow, beads, cleanup, archiving |
| **fix-pr-feedback** | Address PR feedback with iterative refinement. MUST BE USED when fixing PR issues. Supports auto-detection (CI failures, code review) and manual triage (user reports bugs). Creates Beads issues for all problems, fixes systematically. Use when user says "fix the PR", "i noticed bugs", "ci failures", or "codex review found issues", or when user mentions CI failures, review comments, failing tests, PR iterations, bug fixes, feedback loops, or systematic issue resolution. | `bd show <FEATURE_KEY>` | workflow, pr, beads, debugging, iteration |
| **issue-first** | Enforce Issue-First pattern by creating Beads tracking issue BEFORE implementation. MUST BE USED for all implementation work. Classifies work type (epic/feature/task/bug/chore), determines priority (0-4), finds parent in hierarchy, creates issue, then passes control to implementation. Use when starting implementation work, or when user mentions "no tracking issue", "missing Feature-Key", work classification, creating features, building new systems, beginning development, or implementing new functionality. | — | workflow, beads, issue-tracking, implementation |
| **merge-pr** | Prepare PR for merge and guide human to merge via GitHub web UI. MUST BE USED when user wants to merge a PR. Verifies CI passing, verifies Beads issue already closed (from PR creation), and provides merge instructions. Issue closure happens at PR creation time (create-pull-request skill), NOT at merge time. Use when user says "merge the PR", "merge it", "merge this", "ready to merge", "merge to master", or when user mentions CI passing, approved reviews, ready-to-merge state, ready to ship, merge, deployment, PR completion, or shipping code. | `bd sync` | workflow, pr, github, merge, deployment |
| **op-secrets-quickref** | Quick reference for 1Password service account auth and secret management. Use for: API keys, tokens, service accounts, op:// references, or auth failures in non-interactive contexts (cron, systemd, CI). Triggers: ZAI_API_KEY, OP_SERVICE_ACCOUNT_TOKEN, 1Password, "where do secrets live", auth failure, 401, permission denied. | — | secrets, auth, token, 1password, op-cli, dx, env, railway |
| **session-end** | End Claude Code session with Beads sync and summary. MUST BE USED when user says they're done, ending session, or logging off. Guarantees Beads export to git, shows session stats, and suggests next ready work. Handles cleanup and context saving. Use when user says "goodbye", "bye", "done for now", "logging off", or when user mentions end-of-session, session termination, cleanup, context saving, bd sync, or export operations. | `bd sync, or export operations.` | workflow, beads, session, cleanup |
| **sync-feature-branch** | Commit current work to feature branch with Beads metadata tracking and git integration. MUST BE USED for all commit operations. Handles Feature-Key trailers, Beads status updates, and optional quick linting before commit. Use when user wants to save progress, commit changes, prepare work for review, sync local changes, or finalize current work, or when user mentions "uncommitted changes", "git status shows changes", "Feature-Key missing", commit operations, saving work, git workflows, or syncing changes. | `bd create --title <FEATURE_KEY> --type feature --priority 2 ` | workflow, git, beads, commit |
| **tech-lead-handoff** | Create comprehensive handoff for tech lead review with Beads epic sync, committed docs, and self-contained prompt. MUST BE USED when completing investigation, incident analysis, or feature planning that needs tech lead approval. Use when user says "handoff", "tech lead review", "review this", "create handoff", or after completing significant work. | `bd show <epic-id>` | workflow, handoff, review, beads, documentation |


## Extended Workflows

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **bv-integration** | Beads Viewer (BV) integration for visual task management and smart task selection. Use for Kanban views, dependency graphs, and the robot-plan API for auto-selecting next tasks. Keywords: beads, viewer, kanban, dependency graph, robot-plan, task selection, bottleneck | `bd show "$NEXT_TASK"` | workflow, beads, visualization, task-selection |
| **cc-glm** | Use cc-glm as the reliability/quality backstop provider via dx-runner for batched delegation with plan-first execution. Batch by outcome (not file). Primary dispatch is OpenCode; dx-runner --provider cc-glm is governed fallback for critical waves and OpenCode failures. Trigger when user mentions cc-glm, fallback lane, critical wave reliability, or batch execution. | `dx-runner start --provider cc-glm --beads bd-xxx --prompt-fi` | workflow, delegation, automation, claude-code, glm, parallel, fallback, reliability, opencode |
| **cli-mastery** | **Tags:** #tools #cli #railway #github #env | — |  |
| **coordinator-dx** | Coordinator playbook for multi-repo, multi-VM parallel execution with dx-runner as canonical governance surface, OpenCode as primary execution lane, and cc-glm as reliability backstop. dx-dispatch is break-glass only. | — |  |
| **dirty-repo-bootstrap** | Safe recovery procedure for dirty/WIP repositories. This skill provides a standardized workflow for: - Snapshotting uncommitted work to a WIP branch | `bd sync` |  |
| **dx-runner** | Canonical unified runner for multi-provider dispatch with shared governance. Routes to cc-glm, opencode, or gemini providers with unified preflight, gates, and failure taxonomy. Use when dispatching agent tasks, running headless jobs, or managing parallel agent sessions. | `dx-runner start --beads bd-xxx --provider cc-glm --prompt-fi` | workflow, dispatch, governance, multi-provider, automation |
| **grill-me** | Relentless product interrogation before planning or implementation. Use when the user wants exhaustive discovery, blind-spot identification, assumption stress-testing, edge-case analysis, or hard pushback on vague problem framing. | — | product, strategy, interrogation, discovery |
| **jules-dispatch** | Dispatches work to Jules agents via the CLI. Automatically generates context-rich prompts from Beads issues and spawns async sessions. Use when user says "send to jules", "assign to jules", "dispatch task", or "run in cloud". | — | workflow, jules, cloud, automation, dx |
| **lint-check** | Run quick linting checks on changed files. MUST BE USED when user wants to check code quality. Fast validation (<5s) following V3 trust-environments philosophy. Use when user says "lint my code", "check formatting", or "run linters", or when user mentions uncommitted changes, pre-commit state, formatting issues, code quality, style checks, validation, prettier, eslint, pylint, or ruff. | — | workflow, quality, linting, validation |
| **opencode-dispatch** | OpenCode-first dispatch workflow for parallel delegation. Use `opencode run` for headless jobs and `opencode serve` for shared server workflows; pair with governance harness for baseline/integrity/report gates. Trigger when user asks for parallel dispatch, throughput lane execution, or OpenCode benchmarking. | `dx-runner start --provider opencode --beads bd-xxx --prompt-` | workflow, dispatch, opencode, parallel, governance, benchmark, glm5 |
| **parallelize-cloud-work** | Delegate independent work to Claude Code Web cloud sessions for parallel execution. Generates comprehensive session prompts with context exploration guidance, verifies Beads state, provides tracking commands. Use when user says "parallelize work to cloud", "start cloud sessions", or needs to execute multiple independent tasks simultaneously, or when user mentions cloud sessions, cloud prompts, delegate to cloud, Claude Code Web, generate session prompts, parallel execution, or asks "how do I use cloud sessions". | `bd show <issue-id>` | workflow, cloud, parallelization, dx |
| **plan-refine** | Iteratively refine implementation plans using the "Convexity" pattern. Simulates a multi-round architectural critique to converge on a secure, robust specification. Use when you have a draft plan that needs deep architectural review or "APR" style optimization. | — | architecture, planning, review, refinement, apr |
| **prompt-writing** | Drafts robust, low-cognitive-load prompts for other agents that enforce the DX invariants: worktree-first, no canonical writes, and a "done gate" (dx-verify-cle | — |  |
| **skill-creator** | Create new Claude Code skills following V3 DX patterns with Beads/Serena integration. MUST BE USED when creating skills. Follows tech lead proven patterns from 300k LOC case study. Use when user wants to create a new skill, implement workflow automation, or enhance the skill system, or when user mentions "need a skill for X", "automate this workflow", "create new capability", repetitive manual processes, skill creation, meta-skill, or V3 patterns. | — | meta, skill-creation, automation, v3 |
| **slack-coordination** | Optional coordinator stack: Slack-based coordination loops (inbox polling, post-merge followups, lightweight locking). Uses direct Slack Web API calls and/or the slack-coordinator systemd service. Does not require MCP. | — | slack, coordination, workflow, optional |
| **wooyun-legacy** | WooYun漏洞分析专家系统。提供基于88,636个真实漏洞案例提炼的元思考方法论、测试流程和绕过技巧。适用于漏洞挖掘、渗透测试、安全审计及代码审计。支持SQL注入、XSS、命令执行、逻辑漏洞、文件上传、未授权访问等多种漏洞类型。 | — |  |
| **worktree-workflow** | Create and manage task workspaces using git worktrees (without exposing worktree complexity). Use this when starting work on a Beads ID, when an agent needs a clean workspace, or when a repo is dirty and blocks sync. Provides a single command (`dx-worktree`) for create/cleanup/prune and a recovery path via dirty-repo-bootstrap. | `dx-worktree create <beads-id> <repo>` | dx, git, worktree, workspace, workflow |


## Health & Monitoring

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **bd-doctor** | Check and fix common Beads workflow issues across all repos. | `bd export --force` |  |
| **dx-cron** | Monitor and manage dx-* system cron jobs and their logs. MUST BE USED when user asks "is the cron running", "show me cron logs", or "status of dx jobs". | — | health, auth, audit, cron, monitoring |
| **lockfile-doctor** | Check and fix lockfile drift across Poetry (Python) and pnpm (Node.js) projects. | — |  |
| **mcp-doctor** | Warn-only health check for canonical MCP configuration and related DX tooling. Strict mode is opt-in via MCP_DOCTOR_STRICT=1. | — | dx, mcp, health, verification |
| **railway-doctor** | Pre-flight checks for Railway deployments to catch failures BEFORE deploying. Use when about to deploy, running verify-* commands, or debugging Railway issues. | — | railway, deployment, validation, pre-flight |
| **skills-doctor** | Validate that the current VM has the right `agent-skills` installed for the repo you’re working in. | — |  |
| **ssh-key-doctor** | Fast, deterministic SSH health check for canonical VMs (no hangs, no secrets). Warn-only by default; strict mode is opt-in. **DEPRECATED for canonical VM access**: Use Tailscale SSH instead. This skill remains useful for non-Tailscale SSH (external servers, GitHub, etc.). | — | dx, ssh, verification, deprecated |
| **toolchain-health** | Validate Python toolchain alignment between mise, Poetry, and pyproject. Use when changing Python versions, editing pyproject.toml, or seeing Poetry/mise version solver errors. Invokes /toolchain-health to check: - .mise.toml python tool version - pyproject.toml python constraint - Poetry env python interpreter Keywords: python version, mise, poetry, toolchain, env use, lock, install | — | dx, tooling, python |
| **verify-pipeline** | Run project verification checks using standard Makefile targets. Use when user says "verify pipeline", "check my work", "run tests", or "validate changes". Wraps `make verify-pipeline` (E2E), `make verify-analysis` (Logic), or `make verify-all`. Ensures environment constraints (e.g. Railway Shell) are met. | — | workflow, testing, verification, makefile, railway |


## Infrastructure

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **canonical-targets** | Single source of truth for canonical VMs, canonical IDEs, and canonical trunk branch. Use this to keep dx-status, mcp-doctor, and setup scripts aligned across machines. | — | dx, ide, vm, canonical, targets |
| **devops-dx** | GitHub/Railway housekeeping for CI env/secret management and DX maintenance. Use when setting or auditing GitHub Actions variables/secrets, syncing Railway env → GitHub, or fixing CI failures due to missing env. | — | devops, github, auth, env, secrets, ci, railway |
| **dx-alerts** | Lightweight “news wire” for DX changes and breakages, posted to Slack (no MCP required). | — |  |
| **fleet-deploy** | Deploy changes across canonical VMs (macmini, homedesktop-wsl, epyc6, epyc12). MUST BE USED when deploying scripts, crontabs, or config changes to multiple VMs. Uses configs/fleet_hosts.yaml as authoritative source for SSH targets, with dx-runner governance. | `dx-runner start --provider opencode --beads bd-xyz --prompt-` | fleet, deploy, vm, canonical, dx-runner, ssh, infrastructure |
| **github-runner-setup** | GitHub Actions self-hosted runner setup and maintenance. Use when setting up dedicated runner users, migrating runners from personal accounts, troubleshooting runner issues, or implementing runner isolation. Covers systemd services, environment isolation, and skills plane integration. | — | github-actions, devops, runner, systemd, infrastructure |
| **vm-bootstrap** | Linux VM bootstrap verification skill. MUST BE USED when setting up new VMs or verifying environment. Supports modes: check (warn-only), install (operator-confirmed), strict (CI-ready). Enforces Linux-only + mise as canonical; honors preference brew→npm (with apt fallback). Verifies required tools: mise, node, pnpm, python, poetry, gh, railway, op, bd, dcg, ru, tmux, rg. Handles optional tools as warnings: tailscale, playwright, docker, bv. Never prints/seeds secrets; never stores tokens in repo/YAML; Railway vars only for app runtime env. Safe on dirty repos (refuses and points to dirty-repo-bootstrap skill, or snapshots WIP branch). Keywords: vm, bootstrap, setup, mise, toolchain, linux, environment, provision, verify, new vm | — | dx, tooling, setup, linux |
| **multi-agent-dispatch** | Cross-VM task dispatch with dx-runner as canonical governance runner and OpenCode as primary execution lane. dx-dispatch is a BREAK-GLASS compatibility shim for remote fanout when dx-runner is unavailable. EPYC6 is currently disabled - see enablement gate. | `dx-dispatch is a BREAK-GLASS compatibility shim for remote f` | workflow, dispatch, dx-runner, governance, cross-vm |


## Railway Deployment

| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **database** | This skill should be used when the user wants to add a database (Postgres, Redis, MySQL, MongoDB), says "add postgres", "add redis", "add database", "connect to database", or "wire up the database". For other templates (Ghost, Strapi, n8n, etc.), use the templates skill. | — |  |
| **deploy** | This skill should be used when the user wants to push code to Railway, says "railway up", "deploy", "deploy to railway", "ship", or "push". For initial setup or creating services, use new skill. For Docker images, use environment skill. | — |  |
| **deployment** | This skill should be used when the user wants to manage Railway deployments, view logs, or debug issues. Covers deployment lifecycle (remove, stop, redeploy, restart), deployment visibility (list, status, history), and troubleshooting (logs, errors, failures, crashes, why deploy failed). NOT for deleting services - use environment skill with isDeleted for that. | — |  |
| **domain** | This skill should be used when the user wants to add a domain, generate a railway domain, check current domains, get the URL for a service, or remove a domain. | — |  |
| **environment** | This skill should be used when the user asks "what's the config", "show me the configuration", "what variables are set", "environment config", "service config", "railway config", or wants to add/set/delete variables, change build/deploy settings, scale replicas, connect repos, or delete services. | — |  |
| **metrics** | This skill should be used when the user asks about resource usage, CPU, memory, network, disk, or service performance. Covers questions like "how much memory is my service using" or "is my service slow". | — |  |
| **new** | This skill should be used when the user says "setup", "deploy to railway", "initialize", "create project", "create service", or wants to deploy from GitHub. Handles initial setup AND adding services to existing projects. For databases, use the database skill instead. | — |  |
| **projects** | This skill should be used when the user wants to list all projects, switch projects, rename a project, enable/disable PR deploys, make a project public/private, or modify project settings. | — |  |
| **railway-docs** | This skill should be used when the user asks about Railway features, how Railway works, or shares a docs.railway.com URL. Fetches up-to-date Railway docs to answer accurately. | — |  |
| **service** | This skill should be used when the user asks about service status, wants to rename a service, change service icons, link services, or create services with Docker images. For creating services with local code, prefer the `new` skill. For GitHub repo sources, use `new` skill to create empty service then `environment` skill to configure source. | — |  |
| **status** | This skill should be used when the user asks "railway status", "is it running", "what's deployed", "deployment status", or about uptime. NOT for variables ("what variables", "env vars", "add variable") or configuration queries - use environment skill for those. | — |  |
| **templates** | This skill should be used when the user wants to add a service from a template, find templates for a specific use case, or deploy tools like Ghost, Strapi, n8n, Minio, Uptime Kuma, etc. For databases (Postgres, Redis, MySQL, MongoDB), prefer the database skill. | — |  |


---


## Skill Discovery
**Auto-loaded from:** `~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md`
**Specification**: https://agentskills.io/specification

**Regenerate this index:**
```bash
make publish-baseline
```

**Add new skill:**
1. Create `~/agent-skills/<category>/<skill-name>/SKILL.md`
2. Run `make publish-baseline`
