# DX Global Constraints (V8)
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

## 4) Delegation Rule (cc-glm)
- **Default**: delegate mechanical tasks estimated \< 2 hours to `cc-glm` headless mode.
- **Background-first for backlogs**: when there are multiple independent tasks, run `cc-glm` in detached background workers.
- **Concurrency target**: use the highest safe parallelism for the backlog (start at `2`, scale to `3-4` as soon as risk/monitoring allow).
- **Mandatory monitoring**: every running worker must be checked on a fixed cadence (recommended: every 5 minutes) using PID state + log growth.
- **Required tracking artifacts** (per delegated task):
  - PID file: `/tmp/cc-glm-jobs/<beads-id>.pid`
  - Log file: `/tmp/cc-glm-jobs/<beads-id>.log`
  - Metadata file: `/tmp/cc-glm-jobs/<beads-id>.meta`
- **Stall handling**: if a worker is alive but log output is stale for 20+ minutes, restart once and record retry count in metadata.
- **Do not delegate**: security-sensitive changes, architectural decisions, or high-blast-radius refactors.
- **Orchestrator owns outcomes**: review diffs, run validation, request revisions, commit/push with required trailers.
- **Never fire-and-forget**: starting background jobs without follow-up checks is a policy violation.

## 5) Secrets + Env Sources (1Password vs Railway)
- **DX/dev workflow secrets** (agent keys, automation tokens): source from 1Password (`op://...`) and resolve at runtime via `op read` or `op run --`.
- **Deploy/runtime secrets** (service config): live in Railway environment variables; for automated Railway CLI use, export `RAILWAY_TOKEN` from 1Password (see `Railway-Delivery`).
- **Service account auth for op CLI**: use `~/agent-skills/scripts/create-op-credential.sh` (never commit tokens).
- **Quick reference**: use the `op-secrets-quickref` skill for safe commands (listing items/fields, op auth, Railway token export).

References:
- `~/agent-skills/docs/ENV_SOURCES_CONTRACT.md`
- `~/agent-skills/docs/SECRET_MANAGEMENT.md`

Notes:
- PR metadata enforcement exists to keep squash merges ergonomic (don’t rely on commit messages).
- If you’re unsure what to use for Agent, use your platform id (see `DX_AGENT_ID.md`).
