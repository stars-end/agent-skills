# Self-Contained External Beads Migration Prompt

**Copy-paste this entire block into each VM. One command. No external dependencies.**

---

## For homedesktop-wsl:

```bash
cd ~/agent-skills && git pull && bash -c '
set -euo pipefail
echo "=== External Beads Migration ==="
echo "Step 1: Pull latest scripts..."
git pull -q origin master
echo "Step 2: Run migration..."
./scripts/migrate-to-external-beads.sh
echo "Step 3: Add BEADS_DIR to ~/.zshrc..."
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo "Step 4: Source ~/.zshrc..."
source ~/.zshrc
echo "Step 5: Verify..."
echo "BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo "✅ Database exists" || echo "❌ Database missing"
bd list >/dev/null 2>&1 && echo "✅ bd works" || echo "❌ bd failed"
dx-check >/dev/null 2>&1 && echo "✅ dx-check passes" || echo "⚠️ dx-check has warnings"
echo "=== Migration Complete ==="
' && rm -rf ~/.zshrc.cache && exec zsh
```

---

## For macmini:

```bash
cd ~/agent-skills && git pull && bash -c '
set -euo pipefail
echo "=== External Beads Migration ==="
echo "Step 1: Pull latest scripts..."
git pull -q origin master
echo "Step 2: Run migration..."
./scripts/migrate-to-external-beads.sh
echo "Step 3: Add BEADS_DIR to ~/.zshrc..."
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo "Step 4: Source ~/.zshrc..."
source ~/.zshrc
echo "Step 5: Verify..."
echo "BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo "✅ Database exists" || echo "❌ Database missing"
bd list >/dev/null 2>&1 && echo "✅ bd works" || echo "❌ bd failed"
dx-check >/dev/null 2>&1 && echo "✅ dx-check passes" || echo "⚠️ dx-check has warnings"
echo "=== Migration Complete ==="
' && rm -rf ~/.zshrc.cache && exec zsh
```

---

## For epyc6:

```bash
cd ~/agent-skills && bash -c '
set -euo pipefail
echo "=== External Beads Migration ==="
echo "Step 1: Pull latest scripts..."
git pull -q origin master
echo "Step 2: Run migration..."
./scripts/migrate-to-external-beads.sh
echo "Step 3: Add BEADS_DIR to ~/.zshrc..."
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo "Step 4: Source ~/.zshrc..."
source ~/.zshrc
echo "Step 5: Verify..."
echo "BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo "✅ Database exists" || echo "❌ Database missing"
bd list >/dev/null 2>&1 && echo "✅ bd works" || echo "❌ bd failed"
dx-check >/dev/null 2>&1 && echo "✅ dx-check passes" || echo "⚠️ dx-check has warnings"
echo "Step 6: Restart OpenCode..."
systemctl --user restart opencode && echo "✅ OpenCode restarted"
echo "=== Migration Complete ==="
' && rm -rf ~/.zshrc.cache && exec zsh
```

---

## What This Does (No External Docs Needed)

1. **Pulls latest agent-skills** - Gets migration script
2. **Runs migration** - Creates ~/bd/.beads, migrates issues, sets up backup
3. **Adds BEADS_DIR to ~/.zshrc** - Persisted across sessions
4. **Sources ~/.zshrc** - Activates BEADS_DIR immediately
5. **Verifies** - Confirms everything works
6. **Restarts shell** - Clean environment with BEADS_DIR active
7. **epyc6 only** - Restarts OpenCode service

---

## Expected Output

```
=== External Beads Migration ===
Step 1: Pull latest scripts...
Step 2: Run migration...
2026-01-31 17:00:00 [INFO] === Beads External DB Migration ===
2026-01-31 17:00:01 [SUCCESS] ✓ All pre-flight checks passed
2026-01-31 17:00:02 [SUCCESS] ✓ Backup complete
2026-01-31 17:00:10 [SUCCESS] ✓ Migrated approximately 47 issues
2026-01-31 17:00:12 [SUCCESS] ✓ All post-flight checks passed
Step 3: Add BEADS_DIR to ~/.zshrc...
Step 4: Source ~/.zshrc...
Step 5: Verify...
BEADS_DIR=/home/feng/bd/.beads
✅ Database exists
✅ bd works
✅ dx-check passes
=== Migration Complete ===
```

---

## Verification After Migration

```bash
# Should show:
echo $BEADS_DIR
# /home/feng/bd/.beads

# Should show issues:
bd list

# Should pass all checks:
dx-check
```

---

## Rollback (If Needed)

```bash
# Remove BEADS_DIR from ~/.zshrc
sed -i.bak '/BEADS_DIR.*bd/d' ~/.zshrc
exec zsh

# Restore from backup (find backup dir)
ls -lt ~/.beads-migration-backup-* | head -1
```
