# DX Global Constraints (V8)
<!-- AUTO-GENERATED - DO NOT EDIT -->

## ⚠️ CRITICAL: BEFORE ANY GIT OPERATIONS

**If you are in** `~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, or `~/llm-common`:

1. **STOP** - These are READ-ONLY canonical clones
2. **DO NOT** commit, push, or modify directly
3. **MUST** use worktrees: `dx-worktree create bd-xxxx repo-name`
4. **MUST** create Beads issue first: `bd create --title "..."`

The git pre-commit hook will BLOCK commits if you ignore this.

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
4. **Feature-Key mandatory**: every commit needs `Feature-Key: bd-XXXX`
