# Beads Operations

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bd create --title "X" --type feature` | Create issue |
| `bd list --status ready` | Find ready tasks |
| `bd show bd-xxx` | View issue |
| `bd close bd-xxx -r "reason"` | Close issue |
| `bd dolt test --json` | Verify Dolt connection |

## Workflow Pattern

```bash
# 1. Find work
bd list --status ready --limit 5

# 2. Create worktree
dx-worktree create bd-xxx agent-skills

# 3. Work in worktree
cd /tmp/agents/bd-xxx/agent-skills
# ... make changes ...

# 4. Commit with Feature-Key
git commit -m "Change description

Feature-Key: bd-xxx
Agent: all-stars-end"

# 5. Create PR
# Use: create-pull-request skill
```

## Canonical Contract
- Beads repo: `~/bd` (Dolt server mode)
- Run mutations from `~/bd`
- Verify before dispatch: `bd dolt test --json`

## See Also
- `core/beads-workflow/SKILL.md` - Full workflow guide
- `docs/BEADS_RECOVERY_RUNBOOK.md` - Troubleshooting
