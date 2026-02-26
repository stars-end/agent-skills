# AGENTS.md — Agent Skills

Skills repository for AI coding agents. Provides workflow skills, health checks, and infrastructure tooling.

## What

**Tech Stack**: Python 3.11+, Node.js 22+, mise, pnpm, Poetry

**Structure**:
- `core/` — Essential workflow skills (beads-workflow, create-pull-request, etc.)
- `extended/` — Enhanced capabilities (dx-runner, impeccable, etc.)
- `health/` — Diagnostics (mcp-doctor, dx-cron, etc.)
- `infra/` — Infrastructure (fleet-deploy, vm-bootstrap)
- `railway/` — Deployment skills
- `scripts/` — Automation scripts
- `lib/` — Shared Python utilities

## Why

Enable consistent DX across:
- `~/prime-radiant-ai` — Main application
- `~/affordabot` — Discord bot
- `~/llm-common` — Shared library

## How

```bash
# Build (regenerate skill index)
make publish-baseline

# Test
pytest tests/ -v

# Lint
ruff check . && ruff format --check .

# Install pre-commit hooks
mise install
```

## Canonical Rules

1. **Worktrees required** — Never commit directly to canonical repos
   ```bash
   dx-worktree create bd-xxx agent-skills
   cd /tmp/agents/bd-xxx/agent-skills
   ```

2. **Feature-Key mandatory** — Every commit needs `Feature-Key: bd-xxx`

3. **No auto-merge** — Humans merge PRs, never enable auto-merge

4. **Secrets from 1Password** — `op://dev/Agent-Secrets-Production/<FIELD>`

5. **Railway shell for dev** — Provides `RAILWAY_SERVICE_*_URL` and all env vars

## Delegation

- **Batch by outcome**, not by file
- **Default**: 2 parallel agents max
- **Dispatch threshold**: <60 min = implement directly, >=60 min = dispatch
- **Primary runner**: `dx-runner` (governed multi-provider)
- **Fallback**: `cc-glm` via dx-runner for critical waves

## Progressive Disclosure

Task-specific guides (read when relevant):
- `agent_docs/running_tests.md` — Test execution patterns
- `agent_docs/dispatch_workflows.md` — Parallel dispatch with dx-runner
- `agent_docs/secrets_management.md` — 1Password + Railway secrets
- `agent_docs/beads_operations.md` — Beads command reference

## Skill Discovery

Auto-loaded from: `{core,extended,health,infra,railway,dispatch}/*/SKILL.md`

To add a skill:
1. Create `<category>/<skill-name>/SKILL.md`
2. Run `make publish-baseline`

## Key Skills

| Skill | When to Use |
|-------|-------------|
| `beads-workflow` | Issue tracking, finding ready tasks |
| `create-pull-request` | Opening PRs (closes Beads atomically) |
| `issue-first` | Before any implementation work |
| `dx-runner` | Dispatching parallel agent tasks |
| `mcp-doctor` | Diagnosing MCP issues |
| `fleet-deploy` | Deploying to canonical VMs |

## References

- `docs/ENV_SOURCES_CONTRACT.md` — Environment variable sources
- `docs/SECRET_MANAGEMENT.md` — Secrets architecture
- `docs/DX_FLEET_SPEC_V7.7.md` — Fleet coordination spec
