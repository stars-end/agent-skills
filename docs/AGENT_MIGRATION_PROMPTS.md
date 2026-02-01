# External Beads Migration - Self-Contained Agent Prompts

**Copy-paste the entire block for your VM into the terminal.**

**Each prompt is self-contained - no external docs needed.**

---

## For homedesktop-wsl Agent

```bash
cd ~/agent-skills && git pull && bash -c '
set -euo pipefail
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RESET="\033[0m"
echo -e "${BLUE}=== External Beads Migration: homedesktop-wsl ===${RESET}"
echo -e "${BLUE}Step 1: Pull latest agent-skills...${RESET}"
git pull -q origin master
echo -e "${GREEN}✓ Pulled latest scripts${RESET}"
echo -e "${BLUE}Step 2: Run migration (backup, create DB, migrate issues)...${RESET}"
./scripts/migrate-to-external-beads.sh --force
echo -e "${BLUE}Step 3: Add BEADS_DIR to ~/.zshrc...${RESET}"
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo -e "${GREEN}✓ BEADS_DIR added to ~/.zshrc${RESET}"
echo -e "${BLUE}Step 4: Verify...${RESET}"
source ~/.zshrc
echo "  BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo -e "${GREEN}  ✓ Database exists${RESET}" || echo -e "${RED}  ✗ Database missing${RESET}"
cd ~/prime-radiant-ai
git status --porcelain | grep "\.beads" >/dev/null 2>&1 && echo -e "${RED}  ✗ .beads changes found (bad)${RESET}" || echo -e "${GREEN}  ✓ Code repo clean (no .beads changes)${RESET}"
cd ~/agent-skills
ISSUE_COUNT=$(bd list 2>/dev/null | wc -l || echo "0")
echo "  Total issues in central DB: $ISSUE_COUNT"
echo -e "${GREEN}=== Migration Complete - Restart shell to activate: exec zsh ===${RESET}"
'
```

---

## For macmini Agent

```bash
cd ~/agent-skills && git pull && bash -c '
set -euo pipefail
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RESET="\033[0m"
echo -e "${BLUE}=== External Beads Migration: macmini ===${RESET}"
echo -e "${BLUE}Step 1: Pull latest agent-skills...${RESET}"
git pull -q origin master
echo -e "${GREEN}✓ Pulled latest scripts${RESET}"
echo -e "${BLUE}Step 2: Run migration (backup, create DB, migrate issues)...${RESET}"
./scripts/migrate-to-external-beads.sh --force
echo -e "${BLUE}Step 3: Add BEADS_DIR to ~/.zshrc...${RESET}"
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo -e "${GREEN}✓ BEADS_DIR added to ~/.zshrc${RESET}"
echo -e "${BLUE}Step 4: Verify...${RESET}"
source ~/.zshrc
echo "  BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo -e "${GREEN}  ✓ Database exists${RESET}" || echo -e "${RED}  ✗ Database missing${RESET}"
cd ~/prime-radiant-ai
git status --porcelain | grep "\.beads" >/dev/null 2>&1 && echo -e "${RED}  ✗ .beads changes found (bad)${RESET}" || echo -e "${GREEN}  ✓ Code repo clean (no .beads changes)${RESET}"
cd ~/agent-skills
ISSUE_COUNT=$(bd list 2>/dev/null | wc -l || echo "0")
echo "  Total issues in central DB: $ISSUE_COUNT"
echo -e "${GREEN}=== Migration Complete - Restart shell to activate: exec zsh ===${RESET}"
'
```

---

## For epyc6 Agent

```bash
cd ~/agent-skills && bash -c '
set -euo pipefail
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RESET="\033[0m"
echo -e "${BLUE}=== External Beads Migration: epyc6 ===${RESET}"
echo -e "${BLUE}Step 1: Pull latest agent-skills...${RESET}"
git pull -q origin master
echo -e "${GREEN}✓ Pulled latest scripts${RESET}"
echo -e "${BLUE}Step 2: Run migration (backup, create DB, migrate issues)...${RESET}"
./scripts/migrate-to-external-beads.sh --force
echo -e "${BLUE}Step 3: Add BEADS_DIR to ~/.zshrc...${RESET}"
grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null || echo "export BEADS_DIR=\"$HOME/bd/.beads\"" >> ~/.zshrc
echo -e "${GREEN}✓ BEADS_DIR added to ~/.zshrc${RESET}"
echo -e "${BLUE}Step 4: Verify...${RESET}"
source ~/.zshrc
echo "  BEADS_DIR=$BEADS_DIR"
ls -la $BEADS_DIR/beads.db 2>/dev/null && echo -e "${GREEN}  ✓ Database exists${RESET}" || echo -e "${RED}  ✗ Database missing${RESET}"
cd ~/prime-radiant-ai
git status --porcelain | grep "\.beads" >/dev/null 2>&1 && echo -e "${RED}  ✗ .beads changes found (bad)${RESET}" || echo -e "${GREEN}  ✓ Code repo clean (no .beads changes)${RESET}"
cd ~/agent-skills
ISSUE_COUNT=$(bd list 2>/dev/null | wc -l || echo "0")
echo "  Total issues in central DB: $ISSUE_COUNT"
echo -e "${BLUE}Step 5: Restart OpenCode...${RESET}"
systemctl --user restart opencode >/dev/null 2>&1 && echo -e "${GREEN}  ✓ OpenCode restarted${RESET}" || echo -e "${RED}  ✗ OpenCode restart failed${RESET}"
echo -e "${GREEN}=== Migration Complete - Restart shell to activate: exec zsh ===${RESET}"
'
```

---

## What Each Migration Does

1. **Pulls latest agent-skills** - Gets migration script
2. **Runs migration with --force** -
   - Backs up all existing `.beads/` directories to timestamped backup
   - Creates `~/bd/.beads/` central database
   - Exports issues from old databases, imports to central DB
   - Adds `BEADS_DIR` to `~/.zshrc`
3. **Sources ~/.zshrc** - Activates BEADS_DIR
4. **Verifies**:
   - Database exists at `~/bd/.beads/beads.db`
   - Code repos have NO `.beads/` changes (critical validation)
   - `bd list` shows issues from central DB
5. **epyc6 only** - Restarts OpenCode service

---

## Expected Success Output

```
=== External Beads Migration: [VMNAME] ===
Step 1: Pull latest agent-skills...
✓ Pulled latest scripts
Step 2: Run migration (backup, create DB, migrate issues)...
2026-01-31 17:48:51 [INFO] === Beads External DB Migration ===
2026-01-31 17:48:51 [SUCCESS] ✓ All pre-flight checks passed
2026-01-31 17:48:51 [SUCCESS] ✓ Backup complete: /home/feng/.beads-migration-backup-[timestamp]
2026-01-31 17:48:51 [SUCCESS] ✓ Beads database initialized
2026-01-31 17:48:51 [SUCCESS] ✓ Migrated approximately 134 issues
2026-01-31 17:48:51 [SUCCESS] ✓ All post-flight checks passed
Step 3: Add BEADS_DIR to ~/.zshrc...
✓ BEADS_DIR added to ~/.zshrc
Step 4: Verify...
  BEADS_DIR=/home/feng/bd/.beads
  ✓ Database exists
  ✓ Code repo clean (no .beads changes)
  Total issues in central DB: 52
=== Migration Complete - Restart shell to activate: exec zsh ===
```

---

## After Migration - Activate

**Restart your shell to activate BEADS_DIR:**

```bash
exec zsh
```

**Then verify:**

```bash
# Should show: /home/feng/bd/.beads
echo $BEADS_DIR

# Should show issues from central DB
bd list

# Should pass all checks including BEADS_DIR
dx-check
```

---

## Rollback (If Something Goes Wrong)

```bash
# 1. Remove BEADS_DIR from shell config
sed -i.bak '/BEADS_DIR.*bd/d' ~/.zshrc

# 2. Restart shell
exec zsh

# 3. Restore from backup (find latest backup)
ls -lt ~/.beads-migration-backup-* | head -1

# 4. Restore specific repo
BACKUP_DIR=$(ls -td ~/.beads-migration-backup-* | head -1)
cp -r "$BACKUP_DIR/agent-skills-beads" ~/agent-skills/.beads
cp -r "$BACKUP_DIR/prime-radiant-ai-beads" ~/prime-radiant-ai/.beads
```

---

## Key Success Indicators

| Check | Expected Result |
|-------|----------------|
| `echo $BEADS_DIR` | `/home/feng/bd/.beads` |
| `ls -la $BEADS_DIR/beads.db` | File exists, ~274KB |
| `cd ~/prime-radiant-ai && git status | grep .beads` | No output (clean) |
| `bd list \| wc -l` | Shows issue count (not empty) |
| `dx-check` | All checks pass |
