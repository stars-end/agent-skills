# DX Global Constraints (V8.3)
<!-- AUTO-GENERATED - DO NOT EDIT -->

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
