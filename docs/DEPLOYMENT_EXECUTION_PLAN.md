# Deployment & Migration Execution Plan
## Step-by-Step Guide for Solo Developer

**Estimated Total Time:** 95 minutes  
**Agent Coordination:** Agents can continue working (with caveats)  
**Rollback:** Available at each phase

---

## Pre-Flight Checklist

### Do I Need to Stop Agents?

**Short answer: NO, but with coordination**

**Phase 1 (Emergency Fixes):** Agents can keep working
- Fixing cron jobs doesn't affect active sessions
- Disabling auto-checkpoint doesn't affect current work

**Phase 2 (Migration):** Coordinate with agents
- If agent is actively working in a canonical repo → wait for them to finish
- If agent is in a worktree → no impact
- Takes 15 min per VM, can do one VM at a time

**Phase 3-5:** Agents can keep working
- Installing hooks/scripts doesn't affect active sessions

### What You'll Need

- ✅ SSH access to all 3 VMs (you have this via Tailscale)
- ✅ Terminal access to homedesktop-wsl (you're on it now)
- ✅ 95 minutes of focused time (can split across multiple sessions)
- ✅ Backup plan (reflog keeps 90 days)

---

## Phase 1: Emergency Fixes (5 minutes)

**Goal:** Fix macmini ru sync, disable auto-checkpoint, add --autostash

**Agent Impact:** NONE - agents can keep working

### Step 1.1: Fix macmini ru sync (2 min)

```bash
# From homedesktop-wsl
ssh fengning@macmini

# Backup current crontab
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

# Edit crontab
crontab -e
```

**Find these lines:**
```cron
0 12 * * * /Users/fengning/.local/bin/ru sync --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
5 */4 * * * /Users/fengning/.local/bin/ru sync stars-end/agent-skills --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
```

**Replace with:**
```cron
0 12 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
5 */4 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
```

**Save and exit** (`:wq` in vim, or Ctrl+X in nano)

**Verify:**
```bash
# Test ru sync manually
/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash

# Should succeed now (no bash version error)
```

**Exit macmini:**
```bash
exit
```

### Step 1.2: Disable auto-checkpoint on macmini (1 min)

```bash
# From homedesktop-wsl
ssh fengning@macmini

# Unload launchd service
launchctl unload ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist

# Verify it's stopped
launchctl list | grep auto-checkpoint
# Should return nothing

# Backup the plist (in case you want to re-enable later)
mv ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist \
   ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist.disabled

exit
```

### Step 1.3: Add --autostash to homedesktop-wsl (2 min)

```bash
# On homedesktop-wsl (local)
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

crontab -e
```

**Find these lines:**
```cron
0 12 * * * /home/fengning/.local/bin/ru sync --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
0 */4 * * * /home/fengning/.local/bin/ru sync stars-end/agent-skills --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
```

**Replace with:**
```cron
0 12 * * * /home/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
0 */4 * * * /home/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
```

**Save and exit**

### Step 1.4: Add --autostash to epyc6 (optional - already working)

```bash
ssh feng@epyc6

crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

crontab -e
```

**Add --autostash to both ru sync lines (same as above)**

```bash
exit
```

### Phase 1 Complete ✅

**Verify:**
```bash
# Check macmini can sync now
ssh fengning@macmini '/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash'
# Should succeed

# Check auto-checkpoint is stopped
ssh fengning@macmini 'launchctl list | grep auto-checkpoint'
# Should return nothing
```

**Agent Impact:** NONE - agents didn't notice anything

---

## Phase 2: Safe Migration (15 min per VM)

**Goal:** Reset all repos to trunk, clean up branches

**Agent Impact:** MEDIUM - coordinate with agents

### Before Starting Phase 2

**Check if any agents are actively working:**

```bash
# Check homedesktop-wsl
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo 2>/dev/null && {
        echo "$repo: $(git branch --show-current)"
        git status --porcelain | head -5
    }
done

# Check macmini
ssh fengning@macmini 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo 2>/dev/null && {
        echo "$repo: $(git branch --show-current)"
        git status --porcelain | head -5
    }
done'

# Check epyc6
ssh feng@epyc6 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo 2>/dev/null && {
        echo "$repo: $(git branch --show-current)"
        git status --porcelain | head -5
    }
done'
```

**If you see uncommitted changes:**
- Ask agent: "Are you actively working in ~/repo right now?"
- If yes: Wait for them to commit/push, or do that VM later
- If no: Proceed with migration

### Step 2.1: Create Migration Script

```bash
# On homedesktop-wsl
cd ~/agent-skills/scripts

cat > migrate-to-trunk.sh <<'SCRIPT'
#!/bin/bash
# migrate-to-trunk.sh - Safe migration to trunk with backups

set -euo pipefail

echo "=== Safe Migration to Trunk ==="
echo "This script will:"
echo "  1. Check for unpushed commits → create backup branches"
echo "  2. Stash dirty files → recoverable via git stash list"
echo "  3. Reset to trunk"
echo "  4. Delete WIP branches"
echo ""
read -p "Press Enter to continue, Ctrl+C to abort..."
echo ""

for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Migrating ~/$repo"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd ~/$repo 2>/dev/null || {
        echo "⚠️  Repo not found, skipping"
        echo ""
        continue
    }
    
    # Determine trunk branch
    TRUNK="master"
    if git show-ref --verify --quiet refs/heads/main; then
        TRUNK="main"
    fi
    
    CURRENT=$(git branch --show-current)
    echo "Current branch: $CURRENT"
    echo "Target trunk: $TRUNK"
    echo ""
    
    # 1. Check for unpushed commits
    if [[ "$CURRENT" != "$TRUNK" ]]; then
        if git rev-parse "origin/$CURRENT" >/dev/null 2>&1; then
            AHEAD=$(git rev-list --count "origin/$CURRENT..$CURRENT" 2>/dev/null || echo 0)
            if [[ $AHEAD -gt 0 ]]; then
                BACKUP="backup-$CURRENT-$(date +%Y%m%d-%H%M%S)"
                git branch "$BACKUP"
                echo "✅ Created backup branch: $BACKUP ($AHEAD unpushed commits)"
                echo ""
            else
                echo "✅ All commits pushed to origin/$CURRENT"
                echo ""
            fi
        else
            # Local-only branch
            BACKUP="backup-$CURRENT-$(date +%Y%m%d-%H%M%S)"
            git branch "$BACKUP"
            echo "✅ Created backup branch: $BACKUP (local-only branch)"
            echo ""
        fi
    fi
    
    # 2. Stash dirty files
    DIRTY=$(git status --porcelain)
    if [[ -n "$DIRTY" ]]; then
        echo "⚠️  Dirty files found:"
        echo "$DIRTY" | head -10
        echo ""
        STASH_MSG="pre-migration-$(date +%Y%m%d-%H%M%S)"
        git stash push -u -m "$STASH_MSG"
        echo "✅ Stashed as: $STASH_MSG"
        echo "   Recover with: git stash list && git stash pop"
        echo ""
    fi
    
    # 3. Reset to trunk
    echo "Fetching from origin..."
    git fetch origin --prune --quiet
    
    echo "Checking out $TRUNK..."
    git checkout -f "$TRUNK"
    
    echo "Resetting to origin/$TRUNK..."
    git reset --hard "origin/$TRUNK"
    
    echo "Cleaning untracked files..."
    git clean -fdx
    
    # 4. Delete WIP branches
    WIP_BRANCHES=$(git branch | grep -E 'wip/auto|auto-checkpoint/' || echo "")
    if [[ -n "$WIP_BRANCHES" ]]; then
        echo ""
        echo "Deleting WIP branches:"
        echo "$WIP_BRANCHES"
        echo "$WIP_BRANCHES" | xargs -r git branch -D
        echo "✅ WIP branches deleted"
    fi
    
    echo ""
    echo "✅ $repo migrated to $TRUNK"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "=== Migration Complete ==="
echo ""
echo "Review any backup branches:"
git branch -a | grep backup || echo "  None created"
echo ""
echo "Review any stashes:"
git stash list || echo "  None created"
echo ""
SCRIPT

chmod +x migrate-to-trunk.sh
```

### Step 2.2: Run Migration on homedesktop-wsl (5 min)

```bash
# On homedesktop-wsl
cd ~/agent-skills/scripts
./migrate-to-trunk.sh
```

**Review output carefully:**
- Note any backup branches created
- Note any stashes created
- Verify all repos on trunk

**Verify:**
```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo && echo "$repo: $(git branch --show-current)"
done
```

Should show all on master/main.

### Step 2.3: Run Migration on macmini (5 min)

```bash
# From homedesktop-wsl
scp ~/agent-skills/scripts/migrate-to-trunk.sh fengning@macmini:~/

ssh fengning@macmini 'bash ~/migrate-to-trunk.sh'
```

**Review output, verify all repos on trunk**

### Step 2.4: Run Migration on epyc6 (5 min)

```bash
# From homedesktop-wsl
scp ~/agent-skills/scripts/migrate-to-trunk.sh feng@epyc6:~/

ssh feng@epyc6 'bash ~/migrate-to-trunk.sh'
```

**Review output, verify all repos on trunk**

### Step 2.5: Handle epyc6 prime-radiant Divergence (manual)

**If migration script created a backup branch for prime-radiant-ai on epyc6:**

```bash
ssh feng@epyc6
cd ~/prime-radiant-ai

# Check what the local commit was
git log backup-* -1 --oneline

# If it's important, push it
git push origin backup-bd-whatever-20260201

# If it's noise, just delete the backup
git branch -D backup-*

exit
```

### Phase 2 Complete ✅

**Verify all VMs:**
```bash
# Quick check script
for vm in "localhost" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    if [[ "$vm" == "localhost" ]]; then
        for repo in agent-skills prime-radiant-ai affordabot llm-common; do
            cd ~/$repo 2>/dev/null && echo "  $repo: $(git branch --show-current)"
        done
    else
        ssh "$vm" 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
            cd ~/$repo 2>/dev/null && echo "  $repo: $(git branch --show-current)"
        done'
    fi
    echo ""
done
```

**All should show master or main.**

---

## Phase 3: Daily Sync (30 minutes)

**Goal:** Install canonical-sync.sh on all VMs, add to cron

**Agent Impact:** NONE - installs for future use

### Step 3.1: Create canonical-sync.sh

```bash
# On homedesktop-wsl
cd ~/agent-skills/scripts

cat > canonical-sync.sh <<'SCRIPT'
#!/bin/bash
# canonical-sync.sh - Daily reset of canonical repos to origin/trunk

set -euo pipefail

REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
LOG_PREFIX="[canonical-sync $(date +'%Y-%m-%d %H:%M:%S')]"

SYNCED=0
SKIPPED=0

for repo in "${REPOS[@]}"; do
    cd ~/$repo 2>/dev/null || continue
    
    # Skip if this is a worktree
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
    if [[ "$GIT_DIR" =~ worktrees ]]; then
        continue
    fi
    
    # Skip if git operation in progress
    if [[ -f .git/index.lock ]]; then
        echo "$LOG_PREFIX $repo: Skipped (git operation in progress)"
        ((SKIPPED++))
        continue
    fi
    
    # Determine trunk
    TRUNK="master"
    if git show-ref --verify --quiet refs/heads/main; then
        TRUNK="main"
    fi
    
    # Fetch from origin
    if ! git fetch origin --prune --quiet 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to fetch (network issue?)"
        ((SKIPPED++))
        continue
    fi
    
    # Nuclear reset
    if ! git checkout -f "$TRUNK" 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to checkout $TRUNK"
        ((SKIPPED++))
        continue
    fi
    
    if ! git reset --hard "origin/$TRUNK" 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to reset to origin/$TRUNK"
        ((SKIPPED++))
        continue
    fi
    
    git clean -fdx 2>/dev/null || true
    
    # Clean up old WIP branches
    git branch | grep -E 'wip/auto|auto-checkpoint/' | xargs -r git branch -D 2>/dev/null || true
    
    echo "$LOG_PREFIX $repo: ✅ Synced to origin/$TRUNK"
    ((SYNCED++))
done

echo "$LOG_PREFIX Complete: $SYNCED synced, $SKIPPED skipped"

# Alert if all syncs failed
if [[ $SYNCED -eq 0 && $SKIPPED -gt 0 ]]; then
    echo "🚨 SYNC FAILED: 0 repos synced" | tee ~/logs/SYNC_ALERT
fi

exit 0
SCRIPT

chmod +x canonical-sync.sh
```

### Step 3.2: Test canonical-sync.sh locally

```bash
cd ~/agent-skills/scripts
./canonical-sync.sh
```

**Should output:**
```
[canonical-sync 2026-02-01 ...] agent-skills: ✅ Synced to origin/master
[canonical-sync 2026-02-01 ...] prime-radiant-ai: ✅ Synced to origin/master
...
[canonical-sync 2026-02-01 ...] Complete: 4 synced, 0 skipped
```

### Step 3.3: Commit and push canonical-sync.sh

```bash
cd ~/agent-skills
git add scripts/canonical-sync.sh scripts/migrate-to-trunk.sh
git commit -m "feat: add canonical-sync and migrate-to-trunk scripts"
git push origin master
```

### Step 3.4: Deploy to macmini and epyc6

```bash
# macmini
scp ~/agent-skills/scripts/canonical-sync.sh fengning@macmini:~/agent-skills/scripts/
ssh fengning@macmini 'chmod +x ~/agent-skills/scripts/canonical-sync.sh'

# epyc6
scp ~/agent-skills/scripts/canonical-sync.sh feng@epyc6:~/agent-skills/scripts/
ssh feng@epyc6 'chmod +x ~/agent-skills/scripts/canonical-sync.sh'
```

### Step 3.5: Add to cron (all VMs)

**homedesktop-wsl:**
```bash
crontab -e
```

**Add:**
```cron
# Daily canonical sync at 3:00 AM
0 3 * * * ~/agent-skills/scripts/canonical-sync.sh >> ~/logs/canonical-sync.log 2>&1
```

**macmini:**
```bash
ssh fengning@macmini 'crontab -e'
```

**Add:**
```cron
# Daily canonical sync at 3:05 AM
5 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/canonical-sync.sh >> ~/logs/canonical-sync.log 2>&1
```

**epyc6:**
```bash
ssh feng@epyc6 'crontab -e'
```

**Add:**
```cron
# Daily canonical sync at 3:10 AM
10 3 * * * ~/agent-skills/scripts/canonical-sync.sh >> ~/logs/canonical-sync.log 2>&1
```

### Phase 3 Complete ✅

**Verify cron entries:**
```bash
crontab -l | grep canonical-sync
ssh fengning@macmini 'crontab -l | grep canonical-sync'
ssh feng@epyc6 'crontab -l | grep canonical-sync'
```

---

## Phase 4: Prevention (30 minutes)

**Goal:** Add pre-commit hooks, .CANONICAL_REPO markers, update AGENTS.md

**Agent Impact:** LOW - agents will see warnings on next commit attempt

### Step 4.1: Create pre-commit hook

```bash
cd ~/agent-skills

cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/bash
# pre-commit hook - Block commits to canonical repos

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")

# Allow commits in worktrees
if [[ "$GIT_DIR" =~ worktrees ]]; then
    exit 0
fi

# Block commits in canonical repos
cat <<EOF

╔═══════════════════════════════════════════════════════════╗
║  🚨 COMMIT BLOCKED: Canonical Repository                ║
╚═══════════════════════════════════════════════════════════╝

This is a canonical repository that resets to origin/master
daily at 3am. Commits here will be lost.

Use worktrees for all development work:
  dx-worktree create bd-xxxx $(basename $(git rev-parse --show-toplevel))
  cd /tmp/agents/bd-xxxx/$(basename $(git rev-parse --show-toplevel))

Then commit there instead.

To bypass (testing only): git commit --no-verify

EOF
exit 1
HOOK

chmod +x .git/hooks/pre-commit
```

### Step 4.2: Deploy pre-commit hook to all repos

```bash
# Local repos
for repo in prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/.git/hooks/pre-commit ~/$repo/.git/hooks/
    chmod +x ~/$repo/.git/hooks/pre-commit
done

# Test it
cd ~/agent-skills
echo "test" >> README.md
git add README.md
git commit -m "test"
# Should block with error message

git checkout README.md
```

### Step 4.3: Create .CANONICAL_REPO markers

```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cat > ~/$repo/.CANONICAL_REPO <<'EOF'
⚠️  CANONICAL REPOSITORY - AUTO-RESETS DAILY ⚠️

This directory resets to origin/master every night at 3am.
Any commits here will be LOST.

For development work:
  dx-worktree create <issue-id> REPO_NAME
  cd /tmp/agents/<issue-id>/REPO_NAME

Your IDE should show this file as a reminder.
EOF
    
    # Add to gitignore
    grep -q "^\.CANONICAL_REPO$" ~/$repo/.gitignore 2>/dev/null || \
        echo ".CANONICAL_REPO" >> ~/$repo/.gitignore
done
```

### Step 4.4: Deploy to other VMs

**macmini:**
```bash
# Pre-commit hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    ssh fengning@macmini "cat > ~/\$repo/.git/hooks/pre-commit" < ~/agent-skills/.git/hooks/pre-commit
    ssh fengning@macmini "chmod +x ~/\$repo/.git/hooks/pre-commit"
done

# .CANONICAL_REPO markers
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    scp ~/$repo/.CANONICAL_REPO fengning@macmini:~/$repo/
done
```

**epyc6:**
```bash
# Pre-commit hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    ssh feng@epyc6 "cat > ~/\$repo/.git/hooks/pre-commit" < ~/agent-skills/.git/hooks/pre-commit
    ssh feng@epyc6 "chmod +x ~/\$repo/.git/hooks/pre-commit"
done

# .CANONICAL_REPO markers
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    scp ~/$repo/.CANONICAL_REPO feng@epyc6:~/$repo/
done
```

### Step 4.5: Update AGENTS.md

```bash
cd ~/agent-skills
nano AGENTS.md
```

**Add this section after the "Daily Workflow" section:**

```markdown
---

## Canonical Repository Rules

**CRITICAL:** The following directories are canonical repositories that auto-reset daily:
- ~/agent-skills
- ~/prime-radiant-ai
- ~/affordabot
- ~/llm-common

**Rules:**
1. ❌ NEVER commit directly to canonical repos
2. ✅ ALWAYS use worktrees for development work
3. 🔄 Canonical repos reset to origin/master at 3am daily

**Workflow:**
```bash
# Start new work
dx-worktree create bd-xxxx prime-radiant-ai
cd /tmp/agents/bd-xxxx/prime-radiant-ai

# Work normally
git add .
git commit -m "feat: your changes"
git push origin bd-xxxx

# Create PR from worktree branch
```

**If you accidentally commit to a canonical repo:**
The pre-commit hook will block you. If you bypass it, your work will be lost at 3am.

**Recovery (if work was lost):**
```bash
cd ~/repo
git reflog | head -20  # Find your commit
git show <commit-hash>  # Verify it's your work
dx-worktree create bd-recovery repo
cd /tmp/agents/bd-recovery/repo
git cherry-pick <commit-hash>
git push origin bd-recovery
```
```

**Save and commit:**
```bash
git add AGENTS.md
git commit -m "docs: add canonical repository rules to AGENTS.md"
git push origin master
```

### Phase 4 Complete ✅

---

## Phase 5: Monitoring (5 minutes)

**Goal:** Add repo-status script and auto-check

**Agent Impact:** NONE

### Step 5.1: Create repo-status script

```bash
cd ~/agent-skills/scripts

cat > repo-status.sh <<'SCRIPT'
#!/bin/bash
# repo-status.sh - Quick health check of canonical repos

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

ISSUES=0

# Check for sync alert
if [[ -f ~/logs/SYNC_ALERT ]]; then
    echo -e "${RED}🚨 SYNC FAILED - check ~/logs/canonical-sync.log${RESET}"
    ((ISSUES++))
fi

for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo 2>/dev/null || continue
    
    # Determine trunk
    TRUNK="master"
    git show-ref --verify --quiet refs/heads/main && TRUNK="main"
    
    BRANCH=$(git branch --show-current)
    
    # Check if on trunk
    if [[ "$BRANCH" != "$TRUNK" ]]; then
        echo -e "${YELLOW}⚠️  $repo on $BRANCH (expected $TRUNK)${RESET}"
        ((ISSUES++))
    fi
    
    # Check if behind
    BEHIND=$(git rev-list --count HEAD..origin/$TRUNK 2>/dev/null || echo 0)
    if [[ $BEHIND -gt 5 ]]; then
        echo -e "${YELLOW}⚠️  $repo $BEHIND commits behind${RESET}"
        ((ISSUES++))
    fi
    
    # Check for dirty files
    DIRTY=$(git status --porcelain | wc -l)
    if [[ $DIRTY -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  $repo has $DIRTY dirty files${RESET}"
        ((ISSUES++))
    fi
done

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✅ All canonical repos healthy${RESET}"
fi

exit 0
SCRIPT

chmod +x repo-status.sh
```

### Step 5.2: Add alias and auto-check

```bash
# Add to ~/.bashrc
cat >> ~/.bashrc <<'EOF'

# Canonical repo status check
alias repo-status='~/agent-skills/scripts/repo-status.sh'

# Auto-check on shell startup (silent if all good)
if [[ -f ~/agent-skills/scripts/repo-status.sh ]]; then
    ~/agent-skills/scripts/repo-status.sh 2>/dev/null || true
fi
EOF

# Reload
source ~/.bashrc
```

### Step 5.3: Test repo-status

```bash
repo-status
```

Should show: `✅ All canonical repos healthy`

### Step 5.4: Deploy to other VMs

```bash
# Commit and push
cd ~/agent-skills
git add scripts/repo-status.sh
git commit -m "feat: add repo-status monitoring script"
git push origin master

# Deploy to macmini
scp ~/agent-skills/scripts/repo-status.sh fengning@macmini:~/agent-skills/scripts/
ssh fengning@macmini 'chmod +x ~/agent-skills/scripts/repo-status.sh'
ssh fengning@macmini "echo 'alias repo-status=~/agent-skills/scripts/repo-status.sh' >> ~/.bashrc"

# Deploy to epyc6
scp ~/agent-skills/scripts/repo-status.sh feng@epyc6:~/agent-skills/scripts/
ssh feng@epyc6 'chmod +x ~/agent-skills/scripts/repo-status.sh'
ssh feng@epyc6 "echo 'alias repo-status=~/agent-skills/scripts/repo-status.sh' >> ~/.bashrc"
```

### Phase 5 Complete ✅

---

## Rollback Procedures

### If Phase 1 Causes Issues (ru sync broken)

```bash
# Restore crontab backup
ssh fengning@macmini 'crontab ~/crontab.backup.*'

# Re-enable auto-checkpoint
ssh fengning@macmini 'mv ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist.disabled \
    ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist'
ssh fengning@macmini 'launchctl load ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist'
```

### If Phase 2 Causes Issues (migration lost work)

```bash
# Check backup branches
cd ~/repo
git branch | grep backup

# Restore from backup
git checkout backup-whatever-20260201

# Or restore from stash
git stash list
git stash pop

# Or restore from reflog (90-day history)
git reflog | head -20
git checkout <commit-hash>
```

### If Phase 3 Causes Issues (canonical-sync broken)

```bash
# Disable canonical-sync
crontab -e
# Comment out or delete the canonical-sync line

# On all VMs
ssh fengning@macmini 'crontab -e'  # Comment out canonical-sync
ssh feng@epyc6 'crontab -e'  # Comment out canonical-sync
```

### If Phase 4 Causes Issues (hooks blocking work)

```bash
# Temporarily disable pre-commit hook
cd ~/repo
mv .git/hooks/pre-commit .git/hooks/pre-commit.disabled

# Or bypass for one commit
git commit --no-verify -m "message"
```

---

## Post-Deployment Verification

### Day 1 (Immediately After Deployment)

```bash
# Check all repos on trunk
repo-status
# Should show: ✅ All canonical repos healthy

# Check cron entries
crontab -l | grep -E "ru sync|canonical-sync"
ssh fengning@macmini 'crontab -l | grep -E "ru sync|canonical-sync"'
ssh feng@epyc6 'crontab -l | grep -E "ru sync|canonical-sync"'
```

### Day 2 (After First Sync)

```bash
# Check canonical-sync ran successfully
tail -20 ~/logs/canonical-sync.log
ssh fengning@macmini 'tail -20 ~/logs/canonical-sync.log'
ssh feng@epyc6 'tail -20 ~/logs/canonical-sync.log'

# Should show: "Complete: 4 synced, 0 skipped"

# Check all repos still on trunk
repo-status
```

### Week 1

```bash
# Check ru sync working on macmini
ssh fengning@macmini 'tail -50 ~/logs/ru-sync.log | grep -v "bash version"'
# Should show successful syncs, no bash errors

# Check no new WIP branches accumulating
ssh fengning@macmini 'git -C ~/agent-skills branch | grep -c "wip/auto" || echo 0'
# Should show: 0
```

---

## Summary

**Total Time:** 95 minutes (can split across multiple sessions)

**Agent Coordination:**
- Phase 1: Agents can keep working ✅
- Phase 2: Coordinate with agents (check if working in canonical repos)
- Phase 3-5: Agents can keep working ✅

**Deployment Method:**
- SSH from homedesktop-wsl to macmini and epyc6
- Copy scripts via scp
- Edit crontabs via ssh
- No downtime required

**Rollback:**
- Available at each phase
- Crontab backups created automatically
- Git reflog keeps 90 days of history

**Verification:**
- `repo-status` shows health
- Logs in ~/logs/*.log
- Auto-check on shell startup

**Ready to start Phase 1?**

---

**END OF DEPLOYMENT EXECUTION PLAN**
