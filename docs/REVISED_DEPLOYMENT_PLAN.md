# REVISED Deployment Plan - Agents Paused
## Phase 0 Added: Commit All Active Work First

**Context:** All agents paused, mid-stream work exists across all VMs  
**Priority:** Preserve ALL work before any destructive operations  
**New Total Time:** 110 minutes (added 15 min for Phase 0)

---

## PHASE 0: Commit All Active Work (15 minutes) - **DO THIS FIRST**

**Goal:** Commit and push ALL uncommitted work across all repos on all VMs

**Why:** Agents are mid-stream, we need to preserve their work before migration

### Step 0.1: Survey All Repos on All VMs (2 min)

```bash
# Create survey script
cat > ~/survey-all-repos.sh <<'SCRIPT'
#!/bin/bash
echo "=== REPO SURVEY ACROSS ALL VMS ==="
echo ""

survey_vm() {
    local vm_label="$1"
    local ssh_target="$2"
    
    echo "━━━ $vm_label ━━━"
    
    if [[ "$ssh_target" == "local" ]]; then
        for repo in agent-skills prime-radiant-ai affordabot llm-common; do
            if [[ -d ~/$repo ]]; then
                cd ~/$repo
                BRANCH=$(git branch --show-current)
                DIRTY=$(git status --porcelain | wc -l)
                echo "  $repo: branch=$BRANCH, dirty=$DIRTY"
            fi
        done
    else
        ssh "$ssh_target" 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
            if [[ -d ~/$repo ]]; then
                cd ~/$repo
                BRANCH=$(git branch --show-current)
                DIRTY=$(git status --porcelain | wc -l)
                echo "  $repo: branch=$BRANCH, dirty=$DIRTY"
            fi
        done'
    fi
    echo ""
}

survey_vm "homedesktop-wsl" "local"
survey_vm "macmini" "fengning@macmini"
survey_vm "epyc6" "feng@epyc6"

echo "=== END SURVEY ==="
SCRIPT

chmod +x ~/survey-all-repos.sh
./survey-all-repos.sh
```

**Review output carefully - note which repos have dirty files**

### Step 0.2: Commit All Work on homedesktop-wsl (3 min)

```bash
# Create commit-all script
cat > ~/commit-all-work.sh <<'SCRIPT'
#!/bin/bash
# commit-all-work.sh - Commit all uncommitted work to current branch

set -euo pipefail

echo "=== Committing All Uncommitted Work ==="
echo ""

for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    if [[ ! -d ~/$repo ]]; then
        continue
    fi
    
    cd ~/$repo
    
    BRANCH=$(git branch --show-current)
    DIRTY=$(git status --porcelain)
    
    if [[ -z "$DIRTY" ]]; then
        echo "✅ $repo: Clean (nothing to commit)"
        continue
    fi
    
    echo "━━━ $repo (branch: $BRANCH) ━━━"
    echo "Uncommitted changes:"
    echo "$DIRTY" | head -10
    echo ""
    
    # Stage all changes
    git add -A
    
    # Commit with timestamp
    COMMIT_MSG="WIP: preserve work before canonical sync migration ($(date +'%Y-%m-%d %H:%M:%S'))"
    git commit -m "$COMMIT_MSG"
    
    echo "✅ Committed to $BRANCH"
    
    # Try to push (best effort)
    if git push origin "$BRANCH" 2>/dev/null; then
        echo "✅ Pushed to origin/$BRANCH"
    else
        # Branch doesn't exist on remote, create it
        if git push -u origin "$BRANCH" 2>/dev/null; then
            echo "✅ Created and pushed origin/$BRANCH"
        else
            echo "⚠️  Push failed (will retry after fetch)"
            # Fetch and try again
            git fetch origin
            if git push -u origin "$BRANCH" 2>/dev/null; then
                echo "✅ Pushed to origin/$BRANCH"
            else
                echo "❌ Push failed - work is committed locally but not pushed"
                echo "   Manual push required: cd ~/$repo && git push origin $BRANCH"
            fi
        fi
    fi
    
    echo ""
done

echo "=== All Work Committed ==="
SCRIPT

chmod +x ~/commit-all-work.sh

# Run on homedesktop-wsl
./commit-all-work.sh
```

**Review output - note any repos that failed to push**

### Step 0.3: Commit All Work on macmini (5 min)

```bash
# Copy script to macmini
scp ~/commit-all-work.sh fengning@macmini:~/

# Run on macmini
ssh fengning@macmini 'bash ~/commit-all-work.sh'
```

**Review output carefully - macmini has the most uncommitted work**

**If any pushes fail:**
```bash
# SSH to macmini and manually push
ssh fengning@macmini
cd ~/repo-that-failed
git push origin $(git branch --show-current)
exit
```

### Step 0.4: Commit All Work on epyc6 (5 min)

```bash
# Copy script to epyc6
scp ~/commit-all-work.sh feng@epyc6:~/

# Run on epyc6
ssh feng@epyc6 'bash ~/commit-all-work.sh'
```

**Review output - note any failed pushes**

### Step 0.5: Verify All Work Committed and Pushed

```bash
# Run survey again
./survey-all-repos.sh
```

**Expected output:** All repos should show `dirty=0` or very low numbers

**If any repos still have uncommitted work:**
```bash
# Investigate manually
ssh <vm> 'cd ~/repo && git status'
```

### Phase 0 Complete ✅

**Verification checklist:**
- [ ] All repos surveyed
- [ ] All uncommitted work committed to current branches
- [ ] All commits pushed to origin (or noted if failed)
- [ ] Survey shows all repos clean or minimal dirty files

**Critical:** Do NOT proceed to Phase 1 until all work is committed and pushed.

---

## PHASE 1: Emergency Fixes (5 minutes)

**No changes from original plan - safe to proceed after Phase 0**

### Step 1.1: Fix macmini ru sync (2 min)

```bash
ssh fengning@macmini

# Backup current crontab
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

# Edit crontab
crontab -e
```

**Change:**
```cron
# FROM:
0 12 * * * /Users/fengning/.local/bin/ru sync --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
5 */4 * * * /Users/fengning/.local/bin/ru sync stars-end/agent-skills --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1

# TO:
0 12 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
5 */4 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
```

**Verify:**
```bash
/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash
# Should succeed
exit
```

### Step 1.2: Disable auto-checkpoint on macmini (1 min)

```bash
ssh fengning@macmini

launchctl unload ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist

mv ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist \
   ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist.disabled

# Verify
launchctl list | grep auto-checkpoint
# Should return nothing

exit
```

### Step 1.3: Add --autostash to homedesktop-wsl (2 min)

```bash
# On homedesktop-wsl
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

crontab -e
```

**Add --autostash to both ru sync lines**

### Phase 1 Complete ✅

---

## PHASE 2: Safe Migration (15 min) - **REVISED**

**Change from original:** Now that all work is committed and pushed, migration is safer

### Step 2.1: Create REVISED Migration Script

```bash
cd ~/agent-skills/scripts

cat > migrate-to-trunk.sh <<'SCRIPT'
#!/bin/bash
# migrate-to-trunk.sh - Safe migration to trunk
# REVISED: Assumes all work already committed in Phase 0

set -euo pipefail

echo "=== Safe Migration to Trunk ==="
echo ""
echo "⚠️  IMPORTANT: This assumes all work was committed in Phase 0"
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
    
    # 1. Check for uncommitted changes (should be none after Phase 0)
    DIRTY=$(git status --porcelain)
    if [[ -n "$DIRTY" ]]; then
        echo "⚠️  WARNING: Uncommitted changes found (Phase 0 incomplete?)"
        echo "$DIRTY" | head -10
        echo ""
        echo "Stashing..."
        git stash push -u -m "emergency-stash-$(date +%Y%m%d-%H%M%S)"
        echo "✅ Stashed (recover with: git stash list && git stash pop)"
        echo ""
    fi
    
    # 2. Check for unpushed commits
    if [[ "$CURRENT" != "$TRUNK" ]]; then
        if git rev-parse "origin/$CURRENT" >/dev/null 2>&1; then
            AHEAD=$(git rev-list --count "origin/$CURRENT..$CURRENT" 2>/dev/null || echo 0)
            if [[ $AHEAD -gt 0 ]]; then
                echo "⚠️  WARNING: $AHEAD unpushed commits (Phase 0 incomplete?)"
                BACKUP="backup-$CURRENT-$(date +%Y%m%d-%H%M%S)"
                git branch "$BACKUP"
                echo "✅ Created backup branch: $BACKUP"
                echo ""
            else
                echo "✅ All commits pushed to origin/$CURRENT"
                echo ""
            fi
        else
            # Local-only branch (shouldn't happen after Phase 0)
            echo "⚠️  WARNING: Local-only branch (Phase 0 incomplete?)"
            BACKUP="backup-$CURRENT-$(date +%Y%m%d-%H%M%S)"
            git branch "$BACKUP"
            echo "✅ Created backup branch: $BACKUP"
            echo ""
        fi
    fi
    
    # 3. Fetch and reset to trunk
    echo "Fetching from origin..."
    git fetch origin --prune --quiet
    
    echo "Checking out $TRUNK..."
    git checkout -f "$TRUNK"
    
    echo "Resetting to origin/$TRUNK..."
    git reset --hard "origin/$TRUNK"
    
    echo "Cleaning untracked files..."
    git clean -fdx
    
    # 4. Delete WIP branches (noise from auto-checkpoint)
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
echo "Review any backup branches created:"
git branch -a | grep backup || echo "  None (all work was pushed in Phase 0)"
echo ""
echo "Review any stashes created:"
git stash list || echo "  None (all work was committed in Phase 0)"
echo ""
SCRIPT

chmod +x migrate-to-trunk.sh
```

### Step 2.2: Run Migration on homedesktop-wsl (5 min)

```bash
cd ~/agent-skills/scripts
./migrate-to-trunk.sh
```

**Expected:** Should show "All commits pushed" for all repos (thanks to Phase 0)

### Step 2.3: Run Migration on macmini (5 min)

```bash
scp ~/agent-skills/scripts/migrate-to-trunk.sh fengning@macmini:~/
ssh fengning@macmini 'bash ~/migrate-to-trunk.sh'
```

**Expected:** Should migrate cleanly since Phase 0 committed all work

### Step 2.4: Run Migration on epyc6 (5 min)

```bash
scp ~/agent-skills/scripts/migrate-to-trunk.sh feng@epyc6:~/
ssh feng@epyc6 'bash ~/migrate-to-trunk.sh'
```

### Step 2.5: Verify All Repos on Trunk

```bash
# Quick verification
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

**All should show master or main**

### Phase 2 Complete ✅

---

## PHASE 3-5: No Changes

**Phases 3-5 remain the same as original plan:**
- Phase 3: Install canonical-sync.sh (30 min)
- Phase 4: Add prevention (pre-commit hooks, markers, AGENTS.md) (30 min)
- Phase 5: Add monitoring (repo-status) (5 min)

See original DEPLOYMENT_EXECUTION_PLAN.md for details.

---

## Summary of Changes

### What Changed

**Added Phase 0 (15 min):**
- Survey all repos across all VMs
- Commit all uncommitted work to current branches
- Push all commits to origin
- Verify all work preserved

**Revised Phase 2:**
- Migration script now expects clean repos (thanks to Phase 0)
- Still creates backups if anything was missed
- Still stashes if uncommitted changes found
- But should be clean migration in practice

### Why This Is Safer

**Before (original plan):**
- Migration script checks and backs up on-the-fly
- Risk of missing something in automated checks

**After (revised plan):**
- Phase 0 explicitly commits ALL work first
- You review the commit output
- Migration is just cleanup (resetting to trunk)
- All agent work is safely in feature branches on origin

### New Timeline

| Phase | Time | What |
|-------|------|------|
| **Phase 0** | **15 min** | **Commit all active work** |
| Phase 1 | 5 min | Emergency fixes |
| Phase 2 | 15 min | Safe migration |
| Phase 3 | 30 min | Install canonical-sync |
| Phase 4 | 30 min | Add prevention |
| Phase 5 | 5 min | Add monitoring |
| **Total** | **100 min** | |

---

## Execution Order (Step-by-Step)

### 1. Phase 0: Commit All Work (15 min)
```bash
# Survey
./survey-all-repos.sh

# Commit on all VMs
./commit-all-work.sh  # homedesktop-wsl
ssh fengning@macmini 'bash ~/commit-all-work.sh'
ssh feng@epyc6 'bash ~/commit-all-work.sh'

# Verify
./survey-all-repos.sh  # Should show all clean
```

### 2. Phase 1: Emergency Fixes (5 min)
```bash
# Fix macmini bash + disable auto-checkpoint
# Add --autostash to all VMs
```

### 3. Phase 2: Migration (15 min)
```bash
# Run migration on all VMs
./migrate-to-trunk.sh  # homedesktop-wsl
ssh fengning@macmini 'bash ~/migrate-to-trunk.sh'
ssh feng@epyc6 'bash ~/migrate-to-trunk.sh'
```

### 4. Phases 3-5: Install & Configure (65 min)
```bash
# Install canonical-sync, hooks, monitoring
# See original plan for details
```

---

## Critical Success Factors

**Phase 0 is CRITICAL:**
- Do NOT skip it
- Do NOT proceed to Phase 1 until all work is committed and pushed
- Review the commit output carefully
- If any pushes fail, fix them before proceeding

**Why:**
- Agents are mid-stream with active work
- Phase 0 preserves ALL of it in feature branches
- Phase 2 migration can then safely reset to trunk
- All agent work is recoverable from origin

---

## Ready to Execute?

**Start with Phase 0:**
```bash
cd ~
./survey-all-repos.sh
```

This will show you exactly what work exists across all VMs.

Then we'll commit it all before any destructive operations.

**Should I create the Phase 0 scripts now?**

---

**END OF REVISED DEPLOYMENT PLAN**
