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
