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
