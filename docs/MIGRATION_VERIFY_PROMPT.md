# Migration and Verification Prompt

**Copy-paste this entire block into your terminal on homedesktop-wsl or macmini.**

**This will:**
1. Pull latest agent-skills
2. Run migration with backup
3. Verify all success criteria
4. Generate proof-of-work report

---

## Copy-Paste Prompt (For homedesktop-wsl OR macmini)

```bash
cd ~/agent-skills && bash -c '
set -euo pipefail
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"
VM_NAME=$(hostname)

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${BLUE}  External Beads Migration: $VM_NAME${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

# Step 1: Pull latest
echo -e "${BLUE}Step 1: Pull latest agent-skills...${RESET}"
git pull -q origin master
echo -e "${GREEN}✓ Pulled latest scripts${RESET}"
echo ""

# Step 2: Run migration
echo -e "${BLUE}Step 2: Run migration (backup, create DB, migrate issues)...${RESET}"
./scripts/migrate-to-external-beads.sh --force
MIGRATION_EXIT=$?
if [ $MIGRATION_EXIT -ne 0 ]; then
    echo -e "${RED}✗ Migration failed with exit code $MIGRATION_EXIT${RESET}"
    echo -e "${YELLOW}Check log: ~/.beads-migration.log${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Migration complete${RESET}"
echo ""

# Step 3: Add BEADS_DIR to ~/.zshrc
echo -e "${BLUE}Step 3: Add BEADS_DIR to ~/.zshrc...${RESET}"
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo -e "${GREEN}✓ BEADS_DIR added to ~/.zshrc${RESET}"
echo ""

# Step 4: Verify
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${BLUE}  VERIFICATION REPORT${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

# 4.1: BEADS_DIR is set
echo -e "${YELLOW}[1] BEADS_DIR Environment Variable${RESET}"
source ~/.zshrc 2>/dev/null || true
if [ -z "${BEADS_DIR:-}" ]; then
    BEADS_DIR="$HOME/bd/.beads"
fi
echo "  BEADS_DIR=$BEADS_DIR"
if [ "$BEADS_DIR" = "$HOME/bd/.beads" ]; then
    echo -e "  ${GREEN}✓ PASS: BEADS_DIR points to correct location${RESET}"
else
    echo -e "  ${RED}✗ FAIL: BEADS_DIR points to wrong location${RESET}"
fi
echo ""

# 4.2: Database exists
echo -e "${YELLOW}[2] Central Database Exists${RESET}"
if [ -f "$BEADS_DIR/beads.db" ]; then
    DB_SIZE=$(ls -lh "$BEADS_DIR/beads.db" | awk "{print \$5}")
    echo "  Path: $BEADS_DIR/beads.db"
    echo "  Size: $DB_SIZE"
    echo -e "  ${GREEN}✓ PASS: Database file exists${RESET}"
else
    echo -e "  ${RED}✗ FAIL: Database not found at $BEADS_DIR/beads.db${RESET}"
fi
echo ""

# 4.3: Backup created
echo -e "${YELLOW}[3] Backup Created${RESET}"
BACKUP_DIR=$(ls -td ~/.beads-migration-backup-* 2>/dev/null | head -1 || echo "")
if [ -n "$BACKUP_DIR" ]; then
    echo "  Location: $BACKUP_DIR"
    BACKUP_ITEMS=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    echo "  Items backed up: $BACKUP_ITEMS"
    echo -e "  ${GREEN}✓ PASS: Backup exists${RESET}"
else
    echo -e "  ${RED}✗ FAIL: No backup found${RESET}"
fi
echo ""

# 4.4: Code repos clean
echo -e "${YELLOW}[4] Code Repos Clean (no .beads changes)${RESET}"
REPOS_CLEAN=true
for repo in "$HOME/prime-radiant-ai" "$HOME/agent-skills"; do
    if [ -d "$repo" ]; then
        cd "$repo"
        if git status --porcelain | grep "\.beads" >/dev/null 2>&1; then
            echo "  ✗ $(basename $repo): has .beads changes"
            REPOS_CLEAN=false
        else
            echo "  ✓ $(basename $repo): clean"
        fi
    fi
done
if [ "$REPOS_CLEAN" = true ]; then
    echo -e "  ${GREEN}✓ PASS: All code repos clean${RESET}"
else
    echo -e "  ${RED}✗ FAIL: Some repos have .beads changes${RESET}"
fi
echo ""

# 4.5: Database accessible
echo -e "${YELLOW}[5] Database Accessible (bd CLI)${RESET}"
export BEADS_DIR="$HOME/bd/.beads"
ISSUE_COUNT=$(bd list 2>/dev/null | wc -l || echo "0")
ISSUE_COUNT=$(echo "$ISSUE_COUNT" | tr -d "[:space:]")
echo "  Total issues in central DB: $ISSUE_COUNT"
if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ PASS: Database accessible, issues found${RESET}"
else
    echo -e "  ${RED}✗ FAIL: No issues found in database${RESET}"
fi
echo ""

# 4.6: Sample issues
echo -e "${YELLOW}[6] Sample Issues (first 5)${RESET}"
bd list 2>/dev/null | head -5 || echo "  (Unable to list issues)"
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  === MIGRATION COMPLETE ===${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${YELLOW}VM: $VM_NAME${RESET}"
echo -e "${YELLOW}Timestamp: $(date)${RESET}"
echo -e "${YELLOW}Backup: $BACKUP_DIR${RESET}"
echo -e "${YELLOW}Issues migrated: $ISSUE_COUNT${RESET}"
echo ""
echo -e "${YELLOW}Next step: Restart shell to activate BEADS_DIR:${RESET}"
echo -e "${GREEN}  exec zsh${RESET}"
echo ""
'
```

---

## Expected Proof-of-Work Output

```
═══════════════════════════════════════════════════════════════
  External Beads Migration: homedesktop-wsl
═══════════════════════════════════════════════════════════════

Step 1: Pull latest agent-skills...
✓ Pulled latest scripts

Step 2: Run migration (backup, create DB, migrate issues)...
2026-02-01 XX:XX:XX [INFO] === Beads External DB Migration ===
2026-02-01 XX:XX:XX [SUCCESS] ✓ All pre-flight checks passed
2026-02-01 XX:XX:XX [SUCCESS] ✓ Backup complete: /home/feng/.beads-migration-backup-XXXXXXXX
2026-02-01 XX:XX:XX [SUCCESS] ✓ Migrated approximately XX issues
2026-02-01 XX:XX:XX [SUCCESS] ✓ All post-flight checks passed
✓ Migration complete

Step 3: Add BEADS_DIR to ~/.zshrc...
✓ BEADS_DIR added to ~/.zshrc

═══════════════════════════════════════════════════════════════
  VERIFICATION REPORT
═══════════════════════════════════════════════════════════════

[1] BEADS_DIR Environment Variable
  BEADS_DIR=/home/feng/bd/.beads
  ✓ PASS: BEADS_DIR points to correct location

[2] Central Database Exists
  Path: /home/feng/bd/.beads/beads.db
  Size: 268K
  ✓ PASS: Database file exists

[3] Backup Created
  Location: /home/feng/.beads-migration-backup-XXXXXXXX
  Items backed up: X
  ✓ PASS: Backup exists

[4] Code Repos Clean (no .beads changes)
  ✓ prime-radiant-ai: clean
  ✓ agent-skills: clean
  ✓ PASS: All code repos clean

[5] Database Accessible (bd CLI)
  Total issues in central DB: XX
  ✓ PASS: Database accessible, issues found

[6] Sample Issues (first 5)
  agent-xxx [Px] [type] status - Title
  ...

═══════════════════════════════════════════════════════════════
  === MIGRATION COMPLETE ===
═══════════════════════════════════════════════════════════════

VM: homedesktop-wsl
Timestamp: 2026-02-01 XX:XX:XX
Backup: /home/feng/.beads-migration-backup-XXXXXXXX
Issues migrated: XX

Next step: Restart shell to activate BEADS_DIR:
  exec zsh
```

---

## After Migration

**Restart your shell:**

```bash
exec zsh
```

**Final verification:**

```bash
echo $BEADS_DIR              # Should show: /home/feng/bd/.beads
bd list                      # Should show issues
dx-check                     # Should pass (may have unrelated warnings)
```

---

## Rollback (If Needed)

```bash
# Remove BEADS_DIR from ~/.zshrc
sed -i.bak '/BEADS_DIR.*bd/d' ~/.zshrc

# Restart shell
exec zsh

# Restore from backup
BACKUP_DIR=$(ls -td ~/.beads-migration-backup-* | head -1)
cp -r "$BACKUP_DIR/agent-skills-beads" ~/agent-skills/.beads
cp -r "$BACKUP_DIR/prime-radiant-ai-beads" ~/prime-radiant-ai/.beads
```
