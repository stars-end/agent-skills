# DX Global Constraints (V8.4)
<!-- AUTO-GENERATED - DO NOT EDIT -->

## 1) Canonical Repository Rules
**Canonical repositories** (read-mostly clones):
- \`~/agent-skills\`
- \`~/prime-radiant-ai\`
- \`~/affordabot\`
- \`~/llm-common\`
- \`~/bd-symphony\`

### Enforcement
**Primary**: Git pre-commit hook blocks commits when not in worktree
**Safety net**: Daily sync to the repo's canonical branch (non-destructive)

### Workflow
Always use worktrees for development:
\`\`\`bash
dx-worktree create bd-xxxx repo-name
cd /tmp/agents/bd-xxxx/repo-name
# Work here
\`\`\`

## 1.5) Canonical Beads Contract (V8.6)
- **Active Beads runtime path is always \`~/.beads-runtime/.beads\`**.
- **\`~/beads\` is the Beads CLI source/build checkout, not runtime state**.
- **\`~/bd\` is legacy/rollback Git-backed state, not active runtime truth**.
- **Use \`bdx\` for Beads coordination commands** (\`create\`, \`show\`, \`comments add\`, \`ready\`, \`search\`, memory commands, etc.).
- **Raw \`bd\` is reserved for local diagnostics/bootstrap/path-sensitive operations or explicit override.**
- **Run \`dx-loop\`, lower-level \`dx-runner\`, and compatibility/internal \`dx-batch\` control-plane commands from non-app directories; use \`bdx\` for Beads coordination around those runs.**
- **Set \`BEADS_DIR=~/.beads-runtime/.beads\` in normal agent shells**.
- **Never run mutating Beads commands from app repos** (\`~/prime-radiant-ai\`, \`~/agent-skills\`, etc.) unless explicitly using a documented override.
- **Backend must be Dolt server mode on \`epyc12\`** for multi-VM/multi-agent reliability.
- **\`epyc12\` is the central Dolt server host**.
- **Direct remote Dolt SQL endpoint settings are backend plumbing, not the agent coordination interface.**
- **Client hosts must not rely on local \`~/bd/.beads/dolt\` data directories**.
- **Legacy macOS \`io.agentskills.ru\` LaunchAgent is disabled by policy** (use cron/systemd schedules only).
- **Before dispatch**: verify \`bdx dolt test --json\` and \`bdx show <known-beads-id> --json\` succeed.
- **\`beads.role\` self-heal**: if local diagnostic \`bd\` commands warn \`beads.role not configured\` while \`bdx dolt test --json\` passes, run \`bd config set beads.role maintainer\`; if that fails outside a Git repo, run \`git config --global beads.role maintainer\` before escalating. This is local config drift, not a hub outage.
- **Do not infer runtime health from \`~/bd\` git cleanliness or Git sync**; use live Beads checks.
- **Host service contract**:
  - Linux canonical VMs: \`systemctl --user is-active beads-dolt.service\`
  - macOS canonical host: \`launchctl print gui/\$(id -u)/com.starsend.beads-dolt\`
- **Source-of-truth runbook**: \`~/agent-skills/docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md\`
- **Agent-facing runbook**: \`~/agent-skills/docs/BEADS_COORDINATION_WRAPPER_RUNBOOK.md\`

## 2) V8 DX Automation Rules
1. **No auto-merge**: never enable GitHub auto-merge on PRs. Direct agent-executed merges are allowed only after explicit current-session HITL approval and passing merge gates.
2. **No PR factory**: one PR per meaningful unit of work
3. **No canonical writes**: always use worktrees
4. **Feature-Key mandatory**: every commit needs \`Feature-Key: bd-<beads-id>\`

## 3) PR Metadata Rules (Blocking In CI)
- **PR title must include a Feature-Key**: include \`bd-<beads-id>\` somewhere in the title (e.g. \`bd-f6fh: ...\`)
- **PR body must include Agent**: add a line like \`Agent: <agent-id>\`

## 4) Delegation Rule (V8.6 - Batch by Outcome)
- **Primary rule**: batch by outcome, not by file. One agent per coherent change set.
- **Default parallelism**: 2 agents, scale to 3-4 only when independent and stable.
- **Default orchestration rule**: use \`dx-loop\` for chained Beads work, multi-step outcomes, implement/review baton flow, PR-aware follow-up, or "keep going until reviewed or blocked."
- **Execution substrate rule**: use \`dx-runner\` as the lower-level provider runner when directly dispatching a single governed task or when \`dx-loop\` instructs it.
- **Compatibility rule**: \`dx-batch\` remains installed as a legacy/compatibility/internal batch substrate, but it is not the default surface agents should reach for first.
- **Direct/manual fallback**: implement directly only for isolated single-task work or when the orchestration surface itself is the active blocker.
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, commit/push with required trailers.
- **See Section 6** for detailed parallel orchestration patterns.

## 5) Secrets + Env Sources (V8.4 - Railway Context Mandatory)
- **Railway context is MANDATORY for dev work**:
  - interactive: \`railway shell\`
  - worktree/automation-safe: \`railway run -p <project-id> -e <env> -s <service> -- <cmd>\`
- **Do not require canonical repo cwd for Railway context**; worktrees are first-class.
- **API keys**: \`op://dev/Agent-Secrets-Production/<FIELD>\` (see SECRETS_INDEX.md).
- **Railway CLI token**: \`op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN\` for CI/automation.
- **Quick reference**: use the \`op-secrets-quickref\` skill.

### 5.0) Agent Secret-Auth Invariant (Always-On)

- For routine agent secret access, raw \`op read\`, \`op item get\`, \`op item list\`, and \`op whoami\` are forbidden.
- Human GUI-backed OP is bootstrap/recovery only; it is not an acceptable fallback for autonomous agent tasks.
- Agents must use cache/service-account helpers, preferably \`DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached ...\`.
- On cache/service-account miss, fail closed with a blocker. Do not fall back to GUI OP.
- Do not run OP retry loops unless the task is explicitly auth repair.

### 5.1) Agent Onboarding SOP (Required First Steps)

New agents MUST complete these steps before any other work:

**Step 1: Verify Agent-Safe 1Password Auth**
\`\`\`bash
# Classifies local auth without printing secrets.
~/agent-skills/scripts/dx-bootstrap-auth.sh --json

# Accept for agents/cron:
#   mode=agent_ready_cache
#   mode=agent_ready_service_account
#
# macOS-only human bootstrap:
#   mode=human_interactive_only means 1Password GUI-backed op works for a
#   person, but agents/cron still need synced cache or a service-account
#   artifact.
#   If op whoami says "no account found" after unlocking 1Password, run
#   op signin once for that unlock/session.

# Fallback search order if manual recovery is needed:
#   1. ~/.config/systemd/user/op-<canonical-host-key>-token
#   2. ~/.config/systemd/user/op-<canonical-host-key>-token.cred
#   3. ~/.config/systemd/user/op_token
#   4. ~/.config/systemd/user/op_token.cred
\`\`\`

**Step 2: Authenticate Railway CLI**
\`\`\`bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
\`\`\`

**Step 3: Verify Full Stack**
\`\`\`bash
~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami
railway status  # Should show project context when run in a linked repo/context
\`\`\`

**Common Issues:**
- \`dx-op-auth-status.sh\` returns \`human_interactive_only\` → macOS GUI is linked, but agent-safe cache/service-account auth is still missing
- \`dx-op-auth-status.sh\` returns \`blocked\` → sync OP cache from \`epyc12\` or create a service-account credential
- \`op whoami\` says \`no account found\` on macOS → unlock 1Password, run \`op signin\`, and verify CLI integration; this is human bootstrap only
- \`railway whoami\` shows "Unauthorized" → Load OP + Railway auth in the same invocation (not separate tool calls)
- repeated auth failures across shell/tool calls → Use \`~/agent-skills/scripts/dx-load-railway-auth.sh -- <command>\`
- cache missing on a consumer host → sync OP cache artifacts from \`epyc12\` before retrying

### 5.2) Railway Link Non-Interactive Usage (CRITICAL)

Agents can ONLY use `railway link` with ALL required flags:

Required flags: `--project <id-or-name>`, `--environment <name>`
Optional flags| `--service <name>`
Recommended  | `--json`

```bash
# CORRECT - Fully non-interactive
railway link --project <project-id> --environment <env> --service <service> --json

railway link --project my-app --environment staging --json

# WRONG - Will block waiting for input
railway link
railway link --project my-project  # missing --environment
```

**Why**: Railway CLI shows visual prompts but completes successfully when all flags are provided.

**Alternative**: Use `railway run` without linking
```bash
# Direct command execution with Railway context
railway run -p <project-id> -e <env> -s <service> -- <command>

# Using context from worktree
dx-railway-run.sh -- <command>
```

**Context files** (created by worktree-setup.sh)
- Location: `/tmp/agents/.dx-context/<beads-id>/<repo>/railway-context.env`
- Contains: `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT`, `RAILWAY_SERVICE`
- Used by: `dx-railway-run.sh` to provide Railway context in worktrees

### 5.3) Blocking Skill Contracts Are Binding

If a named skill contains an explicit `BLOCKED` contract:
- agents MUST return that contract verbatim once the blocker is reached
- agents MUST NOT continue speculative retries after that point
- agents MUST NOT substitute interactive CLI discovery, guessed service names, or ad hoc runtime mutation for the documented blocker response
- `No such file or directory` for a requested binary means the binary/runtime is missing unless the skill explicitly says otherwise
- when Railway execution is required, agents must use explicit non-interactive context (`-p/-e/-s`) or a verified repo-native wrapper
- ambient Railway link state from another repo/project is not sufficient evidence of correct target context

### 5.4) MCP Tool-First Routing Contract (V8.6)

- **Canonical active assistant stack**:
  - \`serena\`: explicit symbol-aware edits
- **Default durable memory surface**:
  - Beads via `bdx remember` and closed `memory` issues
- **Canonical non-default memory surface**:
  - \`cass-memory\`: pilot-only CLI tool; not part of the default assistant loop

### 5.5) Beads Memory Convention (V8.6)

Use existing Beads primitives as the default durable memory layer before adding
any new memory service or wrapper.

- **Short facts**: use \`bdx remember\`, \`bdx memories\`, \`bdx recall\`, and \`bdx forget\`.
- **Structured memory**: create normal Beads issues with \`--type decision\` or an appropriate custom type, plus the \`memory\` label.
- **Memory body**: put the durable fact, decision, gotcha, runbook, or handoff in \`description\` / \`notes\`; use \`bdx comments add\` for provenance and follow-up history.
- **Required metadata for structured memory**: \`mem.kind\`, \`mem.repo\`, \`mem.maturity\`, \`mem.confidence\`, \`mem.source_issue\`, and source grounding such as \`mem.source_commit\`, \`mem.paths\`, or \`mem.stale_if_paths\` when known.
- **Retrieval**: search short facts with \`bdx memories <keyword>\`; search structured records with \`bdx search <keyword> --label memory --status all\` and metadata filters such as \`bdx search memory --label memory --metadata-field mem.repo=agent-skills --status all\`.
- **Source of truth**: memory is a lead, not proof. Verify source-grounded claims with direct source inspection before acting.
- **Wrapper threshold**: add a dedicated \`bd-mem\` helper only if agents repeatedly fail to follow this convention.
- **Detailed convention**: \`~/agent-skills/docs/BEADS_MEMORY_CONVENTION.md\`.

Agents should think in terms of **capability**, not transport:
- discovery/trace -> `rg` + direct file reads
- optional warmed semantic hints -> `scripts/semantic-search query` only when status is `ready`
- explicit symbol operation -> \`serena\`
- ordinary edit -> patch/diff-first CLI workflow

For qualifying tasks, agents SHOULD use this routing:
- exact discovery: `rg` and direct file reads first
- warmed semantic hints (optional): `scripts/semantic-search query` only when `status` is `ready`
- when semantic status is missing/stale/indexing: exit cleanly with `semantic index unavailable; use rg`
- no live query should block on indexing
- rename/refactor, insert-before/after-symbol, replace known symbol body/signature, or symbol lookup directly tied to an edit -> \`serena\`

Transport handling rule:
- semantic-search query is optional and non-blocking; status gates are authoritative
- if status is not `ready`, do not trigger indexing from query path
- fallback is always `rg` + direct reads

## 6) Parallel Agent Orchestration (V8.6)

### Pattern: Plan-First, dx-loop-First, Commit-Only

1. **Create plan** (file for large/cross-repo, Beads notes for small)
2. **Batch by outcome** (1 agent per repo or coherent change set)
3. **Execute with \`dx-loop\` by default** for chained work, multi-step outcomes, implement/review baton flow, and PR-aware follow-up
4. **Commit-only** (agents commit, orchestrator pushes once per batch)

### Task Batching Rules

| Files | Approach | Plan Required |
|-------|----------|---------------|
| 1-2, same purpose | Single agent | Mini-plan in Beads |
| 3-5, coherent change | Single agent | Plan file recommended |
| 6+ OR cross-repo | Batched agents | Full plan file required |

### Dispatch Method

**Default agent-facing orchestrator: dx-loop**

\`\`\`bash
# Chained Beads work / implement-review baton
dx-loop start --epic bd-xxx --repo agent-skills

# Task-oriented status and blocker diagnosis
dx-loop status --beads-id bd-xxx.1
dx-loop explain --beads-id bd-xxx.1
\`\`\`

**Lower-level runner: dx-runner (governed multi-provider runner)**

\`\`\`bash
# OpenCode throughput lane
dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt

# Shared monitoring/reporting
dx-runner status --json
dx-runner check --beads bd-xxx --json
\`\`\`

**Legacy/compatibility/internal batch substrate: dx-batch**

\`\`\`bash
# Compatibility path only; prefer dx-loop for agent-facing orchestration
dx-batch start --items bd-aaa,bd-bbb --max-parallel 2

# Diagnose stuck waves
dx-batch doctor --wave-id <wave-id> --json
\`\`\`

**Direct OpenCode lane (advanced, non-governed)**

\`\`\`bash
# Headless single-run lane
opencode run -m zhipuai/glm-5.1 "Implement task T1 from plan.md"

# Legacy server lane for parallel clients (opt-in only)
opencode serve --hostname 127.0.0.1 --port 4096
opencode run --attach http://127.0.0.1:4096 -m zhipuai/glm-5.1 "Implement task T2 from plan.md"
\`\`\`

**Reliability backstop: cc-glm via dx-runner**

\`\`\`bash
# Start governed fallback job
dx-runner start --provider cc-glm --beads bd-xxx --prompt-file /tmp/p.prompt

# Monitor fallback jobs
dx-runner status --json
dx-runner check --beads bd-xxx --json
\`\`\`

**Optional: Task tool (Codex runtime only)**

\`\`\`yaml
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
\`\`\`

**Cross-VM: dx-dispatch** (compat wrapper to \`dx-runner\` for remote execution)

### dx-runner Best Practices

- Run \`dx-runner preflight --provider <provider>\` before starting a wave.
- Always pass a unique Beads id per run: \`--beads bd-...\`.
- Use \`--prompt-file\` with immutable prompt artifacts, not inline ad hoc prompts.
- Monitor with \`status --json\` + \`check --json\`; automate on \`reason_code\`/\`next_action\`.
- Use \`report --format json\` as the source of truth for outcome and metrics.
- Prefer one controlled restart max; then escalate using failure taxonomy.
- Run \`dx-runner prune\` periodically to clear stale PID ghosts.
- For OpenCode, enforce canonical model \`zhipuai/glm-5.1\`; fallback provider if unavailable.

### Monitoring (Simplified)

- **Check interval**: 5 minutes
- **Signals**: 1) Process alive, 2) Log advancing
- **Restart policy**: 1 restart max, then escalate
- **Check**: \`ps -p [PID]\` and \`tail -20 [log]\`

### Anti-Patterns

- One agent per file (overhead explosion)
- No plan file for cross-repo work (coordination chaos)
- Push before review (PR explosion)
- Multiple restarts (brittle)

### Fast Path for Small Work

For 1-2 file changes, use Beads notes instead of plan file:

\`\`\`markdown
## bd-xxx: Task Name
### Approach
- File: path/to/file
- Change: [what]
- Validation: [how]
### Acceptance
- [ ] File modified
- [ ] Validation passed
- [ ] PR merged
\`\`\`

References:
- \`~/agent-skills/docs/ENV_SOURCES_CONTRACT.md\`
- \`~/agent-skills/docs/SECRET_MANAGEMENT.md\`
- \`~/agent-skills/scripts/benchmarks/opencode_cc_glm/README.md\`
- \`~/agent-skills/extended/dx-loop/SKILL.md\`
- \`~/agent-skills/extended/dx-runner/SKILL.md\`
- \`~/agent-skills/extended/cc-glm/SKILL.md\`

Notes:
 - PR metadata enforcement exists to keep squash merges ergonomic.
 - If unsure what to use for Agent, use platform id (see \`DX_AGENT_ID.md\`).

## 7) Frontend Evidence Contract (Required for UI/UX Claims)

When changing frontend files in \`~/prime-radiant-ai\`, agents MUST follow this workflow:

### Pre-PR Workflow
\`\`\`bash
# 1. Build and verify
pnpm --filter frontend build
pnpm --filter frontend type-check
pnpm --filter frontend lint:css

# 2. Run visual regression (start preview first)
pnpm --filter frontend preview --port 5173 &
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual

# 3. If baselines need update, justify and commit
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual:update
\`\`\`

### Route Matrix Verification
- **no-cookie mode**: \`/\`, \`/sign-in\`, \`/sign-up\`
- **bypass-cookie mode**: \`/v2\`, \`/brokerage\` (if auth bypass available)

### Runtime Health Requirements
- No "Unexpected Application Error" on page
- No console errors containing: \`clerk\`, \`ClerkProvider\`, \`Unhandled\`, \`TypeError\`
- Clean page render for all tested routes

### CI Workflows (Auto-triggered)
- \`.github/workflows/visual-quality.yml\` - Stylelint + Visual Regression
- \`.github/workflows/lighthouse.yml\` - Performance budgets

### Required PR Body Section
\`\`\`markdown
## Frontend Evidence

### Route Matrix
| Route | Desktop | Mobile | Status |
|-------|---------|--------|--------|
| / | ✅ | ✅ | Pass |

### Runtime Health
- Console errors: 0
- Unexpected Application Error: No

### Evidence
- Commit SHA: [hash]
- Visual tests: [X] passed
\`\`\`

**Full Template:** \`~/agent-skills/templates/frontend-evidence-contract.md\`

### Pass/Fail Criteria
- ✅ Visual tests pass (or baselines updated with justification)
- ✅ CI checks green (Stylelint, Visual Regression, Lighthouse)
- ❌ Missing evidence section blocks PR
- ❌ Evidence contradicts claims blocks PR
