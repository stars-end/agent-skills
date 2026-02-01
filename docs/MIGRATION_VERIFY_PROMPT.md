# Migration Verification Prompt - Proof of Work

**Run this AFTER migration to verify work and provide proof-of-work.**

**For: homedesktop-wsl OR macmini agent**

---

## Copy-Paste Verification Prompt

```bash
cd ~/agent-skills && bash -c '
set -euo pipefail
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"
VM_NAME=$(hostname)
FAILED=0

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${BLUE}  MIGRATION VERIFICATION: $VM_NAME${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo ""

# Check 1: BEADS_DIR environment variable
echo -e "${YELLOW}[1] BEADS_DIR Environment Variable${RESET}"
source ~/.zshrc 2>/dev/null || true
export BEADS_DIR="${BEADS_DIR:-$HOME/bd/.beads}"
echo "  BEADS_DIR=$BEADS_DIR"
if [ "$BEADS_DIR" = "$HOME/bd/.beads" ]; then
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${RED}✗ FAIL: BEADS_DIR incorrect${RESET}"
    FAILED=$((FAILED+1))
fi
echo ""

# Check 2: Central database exists
echo -e "${YELLOW}[2] Central Database Exists${RESET}"
if [ -f "$BEADS_DIR/beads.db" ]; then
    DB_SIZE=$(ls -lh "$BEADS_DIR/beads.db" | awk "{print \$5}")
    DB_PATH=$(realpath "$BEADS_DIR/beads.db")
    echo "  Path: $DB_PATH"
    echo "  Size: $DB_SIZE"
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${RED}✗ FAIL: Database not found${RESET}"
    FAILED=$((FAILED+1))
fi
echo ""

# Check 3: BEADS_DIR in ~/.zshrc
echo -e "${YELLOW}[3] BEADS_DIR Persisted in ~/.zshrc${RESET}"
if grep -q "BEADS_DIR.*bd" ~/.zshrc 2>/dev/null; then
    BEADS_LINE=$(grep "BEADS_DIR.*bd" ~/.zshrc)
    echo "  Found: $BEADS_LINE"
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${RED}✗ FAIL: BEADS_DIR not in ~/.zshrc${RESET}"
    FAILED=$((FAILED+1))
fi
echo ""

# Check 4: Backup exists
echo -e "${YELLOW}[4] Backup Created${RESET}"
BACKUP_DIR=$(ls -td ~/.beads-migration-backup-* 2>/dev/null | head -1 || echo "")
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo "  Location: $BACKUP_DIR"
    BACKUP_ITEMS=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    echo "  Items: $BACKUP_ITEMS"
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${YELLOW}⚠ WARNING: No backup found${RESET}"
fi
echo ""

# Check 5: Code repos clean (no .beads changes)
echo -e "${YELLOW}[5] Code Repos Clean (no .beads changes)${RESET}"
REPOS_CLEAN=true
for repo in "$HOME/prime-radiant-ai" "$HOME/agent-skills" "$HOME/affordabot" "$HOME/llm-common"; do
    if [ -d "$repo/.git" ]; then
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
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${RED}✗ FAIL: Some repos have .beads changes${RESET}"
    FAILED=$((FAILED+1))
fi
echo ""

# Check 6: Database accessible (bd CLI works)
echo -e "${YELLOW}[6] Database Accessible (bd CLI)${RESET}"
export BEADS_DIR="$HOME/bd/.beads"
ISSUE_COUNT=$(bd list 2>/dev/null | wc -l || echo "0")
ISSUE_COUNT=$(echo "$ISSUE_COUNT" | tr -d "[:space:]")
echo "  Total issues: $ISSUE_COUNT"
if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${RED}✗ FAIL: No issues accessible${RESET}"
    FAILED=$((FAILED+1))
fi
echo ""

# Check 7: AGENTS.md updated with BEADS_DIR requirements
echo -e "${YELLOW}[7] AGENTS.md Updated (BEADS_DIR documented)${RESET}"
cd ~/agent-skills
if git log --oneline --all | grep -q "external beads" 2>/dev/null; then
    echo "  Latest agent-skills commits:"
    git log --oneline -5 | head -5 | sed "s/^/    /"
    echo -e "  ${GREEN}✓ PASS: External beads commits found${RESET}"
else
    echo -e "  ${YELLOW}⚠ WARNING: Cannot verify AGENTS.md update (git history)${RESET}"
fi

# Check if AGENTS.md has BEADS_DIR section
if [ -f "AGENTS.md" ] && grep -q "BEADS_DIR" AGENTS.md; then
    echo "  AGENTS.md contains BEADS_DIR documentation"
    echo -e "  ${GREEN}✓ PASS${RESET}"
else
    echo -e "  ${YELLOW}⚠ WARNING: AGENTS.md may not be latest${RESET}"
    echo "  Run: cd ~/agent-skills && git pull origin master"
fi
echo ""

# Check 8: Sample issues from central DB
echo -e "${YELLOW}[8] Sample Issues (from central DB)${RESET}"
echo "  First 5 issues:"
bd list 2>/dev/null | head -5 | sed "s/^/    /" || echo "    (Unable to list)"
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${BLUE}  VERIFICATION SUMMARY${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "  VM: $VM_NAME"
echo "  Timestamp: $(date)"
echo "  Checks passed: $((8-FAILED))/8"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}  ✓✓✓ ALL CHECKS PASSED ✓✓✓${RESET}"
    echo ""
    echo "  Migration complete and verified!"
else
    echo -e "${RED}  ✗✗✗ $FAILED CHECK(S) FAILED ✗✗✗${RESET}"
    echo ""
    echo "  Please review failed checks above."
fi
echo ""

echo -e "${YELLOW}Proof of Work Data:${RESET}"
echo "  VM: $VM_NAME"
echo "  BEADS_DIR: $BEADS_DIR"
echo "  Database: ${DB_PATH:-<not found>}"
echo "  Database size: ${DB_SIZE:-<not found>}"
echo "  Issues migrated: $ISSUE_COUNT"
echo "  Backup: ${BACKUP_DIR:-<not found>}"
echo ""
'
```

---

## Expected Output

```
═══════════════════════════════════════════════════════════════
  MIGRATION VERIFICATION: homedesktop-wsl
═══════════════════════════════════════════════════════════════

[1] BEADS_DIR Environment Variable
  BEADS_DIR=/home/feng/bd/.beads
  ✓ PASS

[2] Central Database Exists
  Path: /home/feng/bd/.beads/beads.db
  Size: 268K
  ✓ PASS

[3] BEADS_DIR Persisted in ~/.zshrc
  Found: export BEADS_DIR="/home/feng/bd/.beads"
  ✓ PASS

[4] Backup Created
  Location: /home/feng/.beads-migration-backup-20260131174851
  Items: 4
  ✓ PASS

[5] Code Repos Clean (no .beads changes)
  ✓ prime-radiant-ai: clean
  ✓ agent-skills: clean
  ✓ affordabot: clean
  ✓ llm-common: clean
  ✓ PASS

[6] Database Accessible (bd CLI)
  Total issues: 47
  ✓ PASS

[7] AGENTS.md Updated (BEADS_DIR documented)
  Latest agent-skills commits:
    7c6e2dec docs: add migration verification prompt with proof-of-work
    99de1c3d docs: add self-contained migration prompts for all VMs
    460c490a feat: external beads database migration (BEADS_DIR)
  ✓ PASS: External beads commits found
  AGENTS.md contains BEADS_DIR documentation
  ✓ PASS

[8] Sample Issues (from central DB)
  First 5 issues:
    agent-xxx [Px] [type] status - Title
    ...

═══════════════════════════════════════════════════════════════
  VERIFICATION SUMMARY
═══════════════════════════════════════════════════════════════

  VM: homedesktop-wsl
  Timestamp: 2026-02-01 ...
  Checks passed: 8/8

  ✓✓✓ ALL CHECKS PASSED ✓✓✓

  Migration complete and verified!

Proof of Work Data:
  VM: homedesktop-wsl
  BEADS_DIR: /home/feng/bd/.beads
  Database: /home/feng/bd/.beads/beads.db
  Database size: 268K
  Issues migrated: 47
  Backup: /home/feng/.beads-migration-backup-20260131174851
```

---

## What Gets Verified

| Check | Description |
|-------|-------------|
| [1] | BEADS_DIR environment variable is set correctly |
| [2] | Central database file exists at ~/bd/.beads/beads.db |
| [3] | BEADS_DIR is persisted in ~/.zshrc |
| [4] | Backup of old .beads directories exists |
| [5] | Code repos have no .beads/ changes (clean) |
| [6] | bd CLI can access central database |
| [7] | AGENTS.md has been updated with BEADS_DIR docs |
| [8] | Sample issues shown from central database |

---

## If Checks Fail

**BEADS_DIR not set:**
```bash
export BEADS_DIR="$HOME/bd/.beads"
echo 'export BEADS_DIR="$HOME/bd/.beads"' >> ~/.zshrc
```

**Database not found:**
```bash
cd ~/agent-skills
./scripts/migrate-to-external-beads.sh
```

**AGENTS.md not updated:**
```bash
cd ~/agent-skills
git pull origin master
```

**Repos have .beads changes:**
```bash
# This is expected if migration not yet run
# Run migration first, then verify
```
