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
