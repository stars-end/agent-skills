# Evidence-Based Final Implementation Plan
## Comprehensive Analysis: 4 Repos × 3 VMs = 12 Canonical Repos

**Analysis Date:** 2026-02-01  
**Method:** Direct SSH inspection of all VMs  
**Conclusion:** Mixed state requiring targeted fixes, not nuclear approach

---

## Part 1: Actual State Analysis (Evidence)

### Repository State Matrix (4 repos × 3 VMs)

| Repo | homedesktop-wsl | macmini | epyc6 |
|------|-----------------|---------|-------|
| **agent-skills** | ✅ master, 0 behind, 5 dirty | 🚨 auto-checkpoint branch, 6 behind, 15 dirty, 50 branches | ✅ master, 0 behind, 0 dirty, 65 branches |
| **prime-radiant-ai** | ✅ master, 0 behind, clean | 🚨 bd-7coo-story-fixes, 1 behind, clean, 28 branches | ⚠️ master, 15 behind, clean, 15 branches |
| **affordabot** | ⚠️ feature branch, 2 behind, clean | 🚨 qa branch, 1 behind, clean, 9 branches | 🚨 auto-checkpoint branch, 0 behind, clean, 5 branches |
| **llm-common** | ✅ master, 0 behind, clean | 🚨 feature branch, 0 behind, clean, 9 branches | ✅ master, 0 behind, clean, 4 branches |

**Legend:**
- ✅ Good: On trunk, current or nearly current
- ⚠️ Warning: On feature branch but otherwise healthy
- 🚨 Critical: On wrong branch + other issues

### Critical Findings

#### 1. macmini: Complete Sync Failure (4/4 repos broken)
```
ru sync: 100% failure rate (bash 3.2 incompatibility)
auto-checkpoint: Running successfully every 4 hours
Result: Repos drift, auto-checkpoint creates branches, no cleanup

agent-skills:
  - Currently on: auto-checkpoint/Fengs-Mac-mini-3
  - 50 total branches (26 wip/auto branches from 7+ days ago)
  - 15 dirty files (.ralph-test-* and .ralph-work-* directories)
  - 6 commits behind origin/master
  
All 4 repos on wrong branches (0/4 on trunk)
```

**Root cause:** Cron uses `/bin/bash` (3.2), `ru` requires bash 4.0+  
**Impact:** Silent failure for 7+ days, no sync happening  
**Evidence:** `ru-sync.log` shows repeated bash version errors

#### 2. homedesktop-wsl: Mostly Healthy (3/4 good)
```
agent-skills: master, 5 dirty (our new docs)
prime-radiant-ai: master, current ✅
affordabot: feature branch (2 behind) ⚠️
llm-common: master, current ✅

ru sync: Working (has --autostash issue but succeeds on 3/4)
```

**Issue:** agent-skills dirty tree blocks ru sync  
**Impact:** Minor, only affects agent-skills  
**Evidence:** `ru-sync.log` shows "Dirty working tree" for agent-skills

#### 3. epyc6: Diverged State (2/4 issues)
```
agent-skills: master, current, 65 branches ✅
prime-radiant-ai: master but 15 behind ⚠️
affordabot: auto-checkpoint branch 🚨
llm-common: master, current ✅

ru sync: Working but reports conflicts
```

**Issue:** prime-radiant-ai diverged (local + remote both have commits)  
**Impact:** Requires manual merge/rebase  
**Evidence:** `ru-sync.log` shows "Diverged (local and remote both have new commits)"

---

### Cron/Systemd Schedule Analysis

#### homedesktop-wsl
```bash
0 12 * * *    ru sync --non-interactive --quiet  # Daily at 12:00 UTC
0 */4 * * *   ru sync agent-skills               # Every 4h
```
**Status:** ✅ Working (missing --autostash but functional)

#### macmini
```bash
0 12 * * *    ru sync --non-interactive --quiet  # FAILING (bash 3.2)
5 */4 * * *   ru sync agent-skills               # FAILING (bash 3.2)

launchd: com.starsend.auto-checkpoint every 14400s (4h)  # ✅ Working
```
**Status:** 🚨 ru sync 100% failure, auto-checkpoint creating pollution

#### epyc6
```bash
0 12 * * *    ru sync --non-interactive --quiet  # Working
10 */4 * * *  ru sync agent-skills               # Working
```
**Status:** ✅ Working (but has diverged repo issue)

---

### Branch Pollution Analysis

**macmini agent-skills: 50 branches**
- 26 wip/auto/* branches (oldest: 7 days)
- 20+ feature-agent-* branches
- Currently on auto-checkpoint branch

**epyc6 agent-skills: 65 branches**
- Many feature-bd-* branches
- No wip/auto branches (auto-checkpoint not running here)
- Currently on master (good)

**Insight:** Branch count alone isn't the problem. The problem is:
1. Being on wrong branch (blocks ru sync)
2. WIP branches accumulating (auto-checkpoint without cleanup)
3. No automated pruning

---

## Part 2: How Current Plan Handles This Mess

### Current Plan's Migration Phase

**Proposed:**
```bash
# One-time migration: Delete all WIP branches, reset to trunk
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    git checkout -f master
    git reset --hard origin/master
    git clean -fdx
    git branch | grep 'wip/auto/' | xargs git branch -D
done
```

**Analysis of what this would do:**

#### macmini agent-skills (50 branches, 15 dirty files)
- ✅ Would reset to master
- ✅ Would delete 26 wip/auto branches
- ⚠️ Would delete 15 dirty files (.ralph-test-*, .ralph-work-*)
  - **Question:** Are these important? They look like agent test directories
  - **Risk:** If they contain uncommitted work, it's lost
  - **Mitigation:** Check if pushed to auto-checkpoint branch first

#### epyc6 prime-radiant-ai (diverged: local ahead 1, remote ahead 15)
- ❌ `git reset --hard origin/master` would LOSE the 1 local commit
- **Risk:** If that commit is important, it's gone
- **Better:** Check if local commit is pushed elsewhere, or create backup branch

#### homedesktop-wsl affordabot (on feature branch, 2 behind)
- ⚠️ Would force checkout master, losing feature branch context
- **Question:** Is this feature branch pushed? If yes, safe. If no, lost.

**Verdict:** Migration is too aggressive without pre-flight checks.

---

### Current Plan's Prevention Phase

**Proposed:**
```bash
# Hourly canonical-sync.sh
git checkout -f master
git reset --hard origin/master
git clean -fdx
```

**Analysis:**

#### Would this prevent macmini's mess?
- ✅ YES - Would keep repos on master
- ✅ YES - Would prevent branch accumulation
- ⚠️ ONLY IF ru sync is fixed first (bash version)
- ⚠️ ONLY IF auto-checkpoint is disabled or modified

**Problem:** If auto-checkpoint still runs every 4h and creates branches, then hourly sync fights with it:
- 00:00 - auto-checkpoint creates branch
- 01:00 - canonical-sync resets to master
- 04:00 - auto-checkpoint creates branch again
- 05:00 - canonical-sync resets to master
- Result: Constant churn, auto-checkpoint work lost

#### Would this prevent epyc6's divergence?
- ⚠️ MAYBE - Depends on what caused divergence
- If agent commits directly to canonical repo: YES (prevents it)
- If divergence from legitimate work: NO (loses work)

**Verdict:** Prevention works ONLY if auto-checkpoint is handled.

---

## Part 3: Revised Plan (Evidence-Based)

### Key Insights from Evidence

1. **macmini is the only disaster** (4/4 repos broken)
   - Root cause: bash version (fixable in 2 min)
   - Secondary: auto-checkpoint pollution (needs strategy)

2. **homedesktop-wsl is mostly fine** (3/4 good)
   - Only needs --autostash flag

3. **epyc6 has one diverged repo** (1/4 issue)
   - Needs manual merge, not automation

4. **Branch count is misleading**
   - epyc6: 65 branches but on master (fine)
   - macmini: 50 branches and on wrong branch (problem)
   - Issue is being on wrong branch, not branch count

5. **auto-checkpoint is the root cause of pollution**
   - Creates branches but never cleans up
   - Conflicts with canonical repo philosophy
   - Only running on macmini (launchd)

### Revised Strategy: Surgical Fixes, Not Nuclear

**Principle:** Fix the root causes, don't nuke everything

#### Phase 1: Fix macmini ru sync (2 minutes)
```bash
ssh fengning@macmini

# Fix cron to use homebrew bash
crontab -e

# Change from:
# 0 12 * * * /Users/fengning/.local/bin/ru sync ...
# To:
0 12 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> ~/logs/ru-sync.log 2>&1
5 */4 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> ~/logs/ru-sync.log 2>&1
```

**Impact:** Fixes 100% failure rate immediately

#### Phase 2: Disable auto-checkpoint on macmini (1 minute)
```bash
ssh fengning@macmini

# Unload launchd service
launchctl unload ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist

# Or disable it
mv ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist.disabled
```

**Rationale:**
- auto-checkpoint conflicts with canonical repo philosophy
- Creates branches that never get cleaned up
- ru sync can't run when on auto-checkpoint branch
- If you need work preservation, use worktrees (already have dx-worktree)

**Alternative (if you want to keep it):**
- Modify auto-checkpoint to only run in worktrees, not canonical repos
- Add cleanup logic to delete old wip/auto branches

#### Phase 3: Manual cleanup of macmini (10 minutes)

**Safe migration with verification:**

```bash
ssh fengning@macmini

# For each repo, check current state before nuking
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cd ~/$repo
    echo "=== $repo ==="
    
    CURRENT=$(git branch --show-current)
    echo "Current branch: $CURRENT"
    
    # Check if current branch is pushed
    if git rev-parse "origin/$CURRENT" >/dev/null 2>&1; then
        AHEAD=$(git rev-list --count "origin/$CURRENT..$CURRENT" 2>/dev/null || echo 0)
        if [[ $AHEAD -gt 0 ]]; then
            echo "⚠️  Has $AHEAD unpushed commits on $CURRENT"
            echo "Creating backup: backup-$CURRENT-$(date +%Y%m%d)"
            git branch "backup-$CURRENT-$(date +%Y%m%d)"
        else
            echo "✅ All commits pushed"
        fi
    else
        echo "⚠️  Local-only branch: $CURRENT"
        echo "Creating backup: backup-$CURRENT-$(date +%Y%m%d)"
        git branch "backup-$CURRENT-$(date +%Y%m%d)"
    fi
    
    # Check dirty files
    DIRTY=$(git status --porcelain | wc -l)
    if [[ $DIRTY -gt 0 ]]; then
        echo "⚠️  Has $DIRTY dirty files"
        git status --porcelain
        echo "Stashing: stash-pre-migration-$(date +%Y%m%d-%H%M%S)"
        git stash push -u -m "stash-pre-migration-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Now safe to reset
    git fetch origin --prune
    git checkout -f master 2>/dev/null || git checkout -f main 2>/dev/null
    git reset --hard origin/master 2>/dev/null || git reset --hard origin/main 2>/dev/null
    git clean -fdx
    
    # Delete old WIP branches (they're noise)
    git branch | grep 'wip/auto/' | xargs -r git branch -D
    
    echo "✅ $repo migrated to trunk"
    echo ""
done
```

**This is safer because:**
- Creates backups only if needed (unpushed commits)
- Stashes dirty files (recoverable)
- Shows what it's doing (not silent)
- Can be run manually to verify before automating

#### Phase 4: Fix homedesktop-wsl agent-skills (1 minute)
```bash
# Add --autostash to cron
crontab -e

# Change:
0 */4 * * * /home/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> ~/logs/ru-sync.log 2>&1
```

#### Phase 5: Fix epyc6 prime-radiant-ai divergence (5 minutes)
```bash
ssh feng@epyc6
cd ~/prime-radiant-ai

# Check what the local commit is
git log origin/master..HEAD

# If it's important, push it
git push origin HEAD:backup-epyc6-$(date +%Y%m%d)

# If it's noise, just reset
git reset --hard origin/master
```

#### Phase 6: Add daily canonical-sync (30 minutes)

**NOT hourly - daily at 3am**

Why daily not hourly?
- Less aggressive (gives you time to notice issues)
- Sufficient for keeping repos current (overnight sync)
- Less likely to conflict with active work
- Easier to debug if something goes wrong

```bash
#!/usr/bin/env bash
# canonical-sync-safe.sh
# Daily sync with safety checks

set -euo pipefail

for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    [[ ! -d ~/$repo ]] && continue
    cd ~/$repo
    
    # Skip if worktree
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
    [[ "$GIT_DIR" =~ worktrees ]] && continue
    
    # Skip if git operation in progress
    [[ -f .git/index.lock ]] && continue
    
    # Determine trunk
    TRUNK="master"
    git show-ref --verify --quiet refs/heads/main && TRUNK="main"
    
    CURRENT=$(git branch --show-current)
    
    # If not on trunk, check if safe to switch
    if [[ "$CURRENT" != "$TRUNK" ]]; then
        # Check for uncommitted changes
        if [[ -n "$(git status --porcelain)" ]]; then
            echo "⚠️  $repo: Has uncommitted changes on $CURRENT, skipping"
            continue
        fi
        
        # Check for unpushed commits
        if git rev-parse "origin/$CURRENT" >/dev/null 2>&1; then
            AHEAD=$(git rev-list --count "origin/$CURRENT..$CURRENT" 2>/dev/null || echo 0)
            if [[ $AHEAD -gt 0 ]]; then
                echo "⚠️  $repo: Has $AHEAD unpushed commits on $CURRENT, skipping"
                continue
            fi
        fi
    fi
    
    # Safe to sync
    git fetch origin --prune --quiet 2>/dev/null || continue
    git checkout -f "$TRUNK" 2>/dev/null || continue
    git reset --hard "origin/$TRUNK" 2>/dev/null || continue
    git clean -fdx 2>/dev/null || true
    
    echo "✅ $repo synced to $TRUNK"
done
```

**Add to cron (daily, not hourly):**
```bash
# homedesktop-wsl
0 3 * * * ~/agent-skills/scripts/canonical-sync-safe.sh >> ~/logs/canonical-sync.log 2>&1

# macmini  
5 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/canonical-sync-safe.sh >> ~/logs/canonical-sync.log 2>&1

# epyc6
10 3 * * * ~/agent-skills/scripts/canonical-sync-safe.sh >> ~/logs/canonical-sync.log 2>&1
```

#### Phase 7: Add prevention hooks (15 minutes)

**Pre-commit hook to block canonical repo commits:**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")

# Allow in worktrees
[[ "$GIT_DIR" =~ worktrees ]] && exit 0

# Block in canonical repos
if [[ -f "$(git rev-parse --show-toplevel)/.CANONICAL_REPO" ]]; then
    echo ""
    echo "🚨 COMMIT BLOCKED: Canonical repository"
    echo ""
    echo "Use worktrees for development:"
    echo "  dx-worktree create bd-xxxx $(basename $(git rev-parse --show-toplevel))"
    echo ""
    exit 1
fi
```

**Add .CANONICAL_REPO markers:**
```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cat > ~/$repo/.CANONICAL_REPO <<'EOF'
⚠️  CANONICAL REPOSITORY - READ ONLY ⚠️
This directory syncs daily at 3am.
For development, use: dx-worktree create bd-xxxx REPO
EOF
done
```

---

## Part 4: Cognitive Load Analysis

### Daily Routine

**With this plan:**
```bash
# Morning check (30 seconds)
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
        cd ~/$repo 2>/dev/null && echo "$repo: $(git branch --show-current)"
    done'
done | grep -v master | grep -v main
```

**If output is empty:** All good, go code.  
**If output shows repos:** Check why they're on feature branches.

**Simpler version:**
```bash
# Add to ~/.bashrc
alias repo-status='for repo in agent-skills prime-radiant-ai affordabot llm-common; do cd ~/$repo 2>/dev/null && echo "$repo: $(git branch --show-current)"; done | grep -v master | grep -v main || echo "✅ All on trunk"'
```

Then just: `repo-status` (2 seconds)

### Comparison to Original Plans

| Aspect | Nuclear Plan | This Plan |
|--------|--------------|-----------|
| Migration risk | High (deletes everything) | Low (checks first) |
| Sync frequency | Hourly | Daily |
| auto-checkpoint | Ignored (conflicts) | Disabled (root cause) |
| Handles divergence | No (force reset) | Yes (manual check) |
| Cognitive load | Very low (but risky) | Low (and safe) |
| Implementation time | 90 min | 60 min |

---

## Part 5: Implementation Timeline

### Immediate (Today - 15 minutes)

**Priority 1: Fix macmini ru sync**
```bash
ssh fengning@macmini 'crontab -e'
# Update to use /opt/homebrew/bin/bash
# Add --autostash flag
```

**Priority 2: Disable auto-checkpoint**
```bash
ssh fengning@macmini 'launchctl unload ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist'
```

**Verify:**
```bash
# Wait 4 hours, check ru-sync.log
ssh fengning@macmini 'tail -20 ~/logs/ru-sync.log'
# Should show success, not bash errors
```

### Tomorrow (30 minutes)

**Manual cleanup of macmini:**
```bash
# Run the safe migration script from Phase 3
# Verify backups created
# Verify all repos on trunk
```

**Add canonical-sync to all VMs:**
```bash
# Deploy script
# Add to cron (daily at 3am)
```

### Day 3 (15 minutes)

**Add prevention:**
```bash
# Add pre-commit hooks
# Add .CANONICAL_REPO markers
# Test by trying to commit to canonical repo
```

### Day 4 (Verification)

**Check logs:**
```bash
# Check canonical-sync ran successfully
tail -50 ~/logs/canonical-sync.log

# Check all repos on trunk
repo-status
```

---

## Part 6: What This Plan Does Differently

### 1. Respects Existing State
- Doesn't blindly delete branches
- Checks for unpushed commits
- Creates backups when needed
- Stashes dirty files

### 2. Fixes Root Causes
- macmini bash version (immediate fix)
- auto-checkpoint pollution (disable it)
- Missing --autostash (add it)
- Not addressing symptoms

### 3. Daily Not Hourly
- Less aggressive
- Easier to debug
- Sufficient for overnight sync
- Won't conflict with active work

### 4. Handles Edge Cases
- Diverged repos (manual check)
- Dirty files (stash)
- Unpushed commits (backup)
- Git locks (skip)

### 5. Low Cognitive Load
- `repo-status` shows problems
- Daily sync handles cleanup
- Pre-commit prevents accidents
- No manual maintenance

---

## Part 7: Success Metrics

### Week 1
- ✅ macmini ru sync working (check logs)
- ✅ All repos on trunk (check repo-status)
- ✅ No new WIP branches (check branch count)

### Week 2
- ✅ Daily sync running successfully (check logs)
- ✅ Repos stay on trunk (check repo-status)
- ✅ No manual interventions needed

### Month 1
- ✅ Zero branch pollution
- ✅ Zero manual cleanups
- ✅ Autonomous operation

---

## Part 8: Rollback Plan

### If canonical-sync causes issues
```bash
# Disable it
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm 'crontab -l | grep -v canonical-sync | crontab -'
done

# Restore from backup branches
cd ~/prime-radiant-ai
git checkout backup-bd-7coo-story-fixes-20260201
```

### If you need auto-checkpoint back
```bash
ssh fengning@macmini 'launchctl load ~/Library/LaunchAgents/com.starsend.auto-checkpoint.plist'
```

---

## Conclusion

**This plan is:**
- ✅ Evidence-based (analyzed all 12 repos)
- ✅ Surgical (fixes root causes, not symptoms)
- ✅ Safe (checks before deleting)
- ✅ Low cognitive load (repo-status + daily sync)
- ✅ Pragmatic (60 min implementation)

**Key differences from nuclear plan:**
- Daily sync (not hourly) - less aggressive
- Disables auto-checkpoint - fixes root cause
- Safe migration - checks before deleting
- Handles edge cases - divergence, dirty files

**Ready to implement?**

---

**END OF EVIDENCE-BASED FINAL PLAN**
