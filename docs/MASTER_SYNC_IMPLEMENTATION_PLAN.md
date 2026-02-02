# Master Sync Implementation Plan
## Comprehensive Multi-VM Sync Enforcement for Autonomous Agent Fleet

**Created:** 2026-02-01  
**Scope:** 3 VMs × 4 Canonical Repos × 9-12 Autonomous Agents  
**Objective:** Eliminate master branch staleness across distributed agent fleet

---

## Executive Summary

### The Problem
Autonomous LLM agents working across 3 VMs (homedesktop-wsl, macmini, epyc6) on 4 canonical repos (prime-radiant-ai, agent-skills, affordabot, llm-common) are experiencing master branch staleness, leading to:
- Merge conflicts when agents create PRs
- Agents rebasing on stale master
- Wasted agent cycles resolving avoidable conflicts
- Inconsistent base state across VMs

### Root Causes Identified

| VM | Issue | Impact | Root Cause |
|----|-------|--------|------------|
| **macmini** | `ru sync` fails 100% | prime-radiant-ai 18 commits behind | Cron uses system bash 3.2, `ru` requires bash 4.0+ |
| **epyc6** | `dx-triage-cron` crashes | No staleness detection for 4+ days | Unbound variable `hours_since_change` at line 186 |
| **homedesktop-wsl** | `ru sync` skips agent-skills | Dirty working tree blocks pull | No `--autostash` flag in cron |
| **All VMs** | Master never syncs on feature branches | Agents work on stale base | `ru sync` only pulls current branch, not master |

### The Solution
Multi-layered enforcement using **guidance over blocking**:
1. **master-sync cron** (every 15min) - Keeps master refs current across all VMs
2. **SessionStart hooks** - Shows agents master staleness at session start
3. **start-feature auto-fix** - Updates master before creating feature branches
4. **AGENTS.md training** - Teaches agents the correct workflow
5. **dx-triage integration** - Detects and auto-fixes staleness
6. **Enhanced pre-push** - Warns (doesn't block) about stale master

---

## Part 1: Bug Fixes (P0 - Deploy Immediately)

### 1.1 Fix macmini: Bash Version Incompatibility

**File:** macmini crontab  
**Issue:** Cron uses `/bin/bash` (3.2), but `ru` requires bash 4.0+  
**Evidence:**
```
ru: Bash >= 4.0 is required (found: 3.2.57(1)-release)
```

**Fix:**
```bash
# SSH to macmini
ssh fengning@macmini

# Edit crontab
crontab -e

# Change ALL lines containing 'ru' from:
0 12 * * * /Users/fengning/.local/bin/ru sync --non-interactive --quiet >> ...

# To:
0 12 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1

# Also update the agent-skills specific line:
5 */4 * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
```

**Verification:**
```bash
# Test manually
/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --non-interactive

# Should see success, not bash version error
```

---

### 1.2 Fix epyc6: dx-triage-cron Unbound Variable

**File:** `~/.local/bin/dx-triage-cron` (epyc6)  
**Issue:** Variable `hours_since_change` used before initialization when `dirty_count=0`  
**Line:** 186  
**Evidence:**
```
/home/feng/.local/bin/dx-triage-cron: line 186: hours_since_change: unbound variable
```

**Fix:**
```bash
# SSH to epyc6
ssh feng@epyc6

# Edit dx-triage-cron
nano ~/.local/bin/dx-triage-cron

# Find line ~145 (before the dirty_count check):
    # Get last file modification time (for uncommitted changes)
    # Cross-platform stat: macOS (BSD) uses -f %m, Linux (GNU) uses -c %Y
    last_file_change=0
    hours_since_change=0  # <-- ADD THIS LINE (initialize before conditional)
    if [[ "$dirty_count" -gt 0 ]]; then
```

**Verification:**
```bash
# Test manually
~/.local/bin/dx-triage-cron --verbose

# Should complete without unbound variable error
```

---

### 1.3 Fix homedesktop-wsl: Add --autostash to ru sync

**File:** homedesktop-wsl crontab  
**Issue:** `ru sync` fails on dirty working tree (agent-skills has uncommitted changes)  
**Evidence:**
```
✗ Pull failed: stars-end/agent-skills
Issue: Dirty working tree (uncommitted changes)
```

**Fix:**
```bash
# On homedesktop-wsl
crontab -e

# Change:
0 12 * * * /home/fengning/.local/bin/ru sync --non-interactive --quiet >> ...

# To:
0 12 * * * /home/fengning/.local/bin/ru sync --autostash --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1

# Also update agent-skills line:
0 */4 * * * /home/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
```

---

## Part 2: New Tool - master-sync

### 2.1 Tool Design

**Purpose:** Keep master branch refs current across all canonical repos, even when on feature branches  
**Location:** `~/agent-skills/scripts/master-sync.sh`  
**Deployment:** Symlinked to `~/.local/bin/master-sync` on all VMs  
**Cron:** Every 15min (staggered by VM)

**Key Features:**
- Updates master ref WITHOUT checking it out (safe for feature branch work)
- Force-updates if fast-forward fails (master is read-only locally)
- Skips if git operation in progress (`.git/index.lock`)
- Works on all canonical repos
- Logs to `~/logs/master-sync.log`

**Implementation:**

```bash
#!/usr/bin/env bash
# master-sync.sh
# Keep master branches current across all canonical repos
# Safe to run while on feature branches - updates refs only

set -euo pipefail

# Source canonical targets
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/canonical-targets.sh" ]]; then
    source "$SCRIPT_DIR/canonical-targets.sh"
elif [[ -f "$HOME/.local/bin/canonical-targets.sh" ]]; then
    source "$HOME/.local/bin/canonical-targets.sh"
else
    echo "Error: canonical-targets.sh not found" >&2
    exit 1
fi

MASTER_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"
LOG_PREFIX="[master-sync $(date +'%Y-%m-%d %H:%M:%S')]"

# Collect all repos to sync
ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")
fi

UPDATED=0
SKIPPED=0
FAILED=0

for repo in "${ALL_REPOS[@]}"; do
    repo_path="$HOME/$repo"
    
    # Skip if repo doesn't exist
    if [[ ! -d "$repo_path/.git" ]]; then
        continue
    fi
    
    cd "$repo_path"
    
    # Skip if git operation in progress
    if [[ -f .git/index.lock ]]; then
        echo "$LOG_PREFIX $repo: Skipped (git operation in progress)"
        ((SKIPPED++))
        continue
    fi
    
    # Skip worktrees (only process main repo)
    if [[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]]; then
        continue
    fi
    
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    
    # Fetch all refs quietly
    if ! git fetch origin --quiet 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to fetch from origin"
        ((FAILED++))
        continue
    fi
    
    # Get current state
    LOCAL_MASTER=$(git rev-parse "$MASTER_BRANCH" 2>/dev/null || echo "")
    REMOTE_MASTER=$(git rev-parse "origin/$MASTER_BRANCH" 2>/dev/null || echo "")
    
    if [[ -z "$LOCAL_MASTER" || -z "$REMOTE_MASTER" ]]; then
        echo "$LOG_PREFIX $repo: Cannot resolve master refs"
        ((FAILED++))
        continue
    fi
    
    # Check if update needed
    if [[ "$LOCAL_MASTER" == "$REMOTE_MASTER" ]]; then
        # Already current
        ((SKIPPED++))
        continue
    fi
    
    # Update local master ref (force, since master is read-only locally)
    if git branch -f "$MASTER_BRANCH" "origin/$MASTER_BRANCH" 2>/dev/null; then
        BEHIND=$(git rev-list --count "$LOCAL_MASTER..origin/$MASTER_BRANCH" 2>/dev/null || echo "?")
        echo "$LOG_PREFIX $repo: Updated master (+$BEHIND commits)"
        ((UPDATED++))
        
        # If currently ON master, also pull it
        if [[ "$current_branch" == "$MASTER_BRANCH" ]]; then
            if git pull --ff-only 2>/dev/null; then
                echo "$LOG_PREFIX $repo: Pulled master (on master branch)"
            else
                # If can't fast-forward, reset to origin (master is read-only)
                git reset --hard "origin/$MASTER_BRANCH" 2>/dev/null || true
                echo "$LOG_PREFIX $repo: Reset master to origin (was diverged)"
            fi
        fi
    else
        echo "$LOG_PREFIX $repo: Failed to update master ref"
        ((FAILED++))
    fi
done

echo "$LOG_PREFIX Complete: $UPDATED updated, $SKIPPED current, $FAILED failed"
exit 0
```

---

### 2.2 Deployment Strategy

**Step 1: Create tool in agent-skills**
```bash
# On homedesktop-wsl (primary dev machine)
cd ~/agent-skills
mkdir -p scripts
# Create scripts/master-sync.sh with content above
chmod +x scripts/master-sync.sh
git add scripts/master-sync.sh
git commit -m "feat: add master-sync tool for multi-VM sync enforcement"
git push origin master
```

**Step 2: Deploy to all VMs using canonical-targets.sh**
```bash
# On homedesktop-wsl
cd ~/agent-skills

# Use built-in deployment function
source scripts/canonical-targets.sh
deploy_to_all_vms scripts/master-sync.sh ~/.local/bin/master-sync

# Or manual deployment:
# homedesktop-wsl (local)
ln -sf ~/agent-skills/scripts/master-sync.sh ~/.local/bin/master-sync

# macmini
scp ~/agent-skills/scripts/master-sync.sh fengning@macmini:~/.local/bin/master-sync
ssh fengning@macmini 'chmod +x ~/.local/bin/master-sync'

# epyc6 (via jump host)
scp ~/agent-skills/scripts/master-sync.sh fengning@homedesktop-wsl:/tmp/master-sync.sh
ssh fengning@homedesktop-wsl 'scp /tmp/master-sync.sh feng@epyc6:~/.local/bin/master-sync && ssh feng@epyc6 "chmod +x ~/.local/bin/master-sync"'
```

**Step 3: Deploy canonical-targets.sh (dependency)**
```bash
# Ensure canonical-targets.sh is in ~/.local/bin on all VMs
source ~/agent-skills/scripts/canonical-targets.sh
deploy_to_all_vms ~/agent-skills/scripts/canonical-targets.sh ~/.local/bin/canonical-targets.sh
```

**Step 4: Add to crontab on all VMs (staggered)**
```bash
# homedesktop-wsl
crontab -e
# Add:
0,15,30,45 * * * * /home/fengning/.local/bin/master-sync >> /home/fengning/logs/master-sync.log 2>&1

# macmini
ssh fengning@macmini 'crontab -e'
# Add:
2,17,32,47 * * * * /opt/homebrew/bin/bash /Users/fengning/.local/bin/master-sync >> /Users/fengning/logs/master-sync.log 2>&1

# epyc6
ssh feng@epyc6 'crontab -e'
# Add:
4,19,34,49 * * * * /home/feng/.local/bin/master-sync >> /home/feng/logs/master-sync.log 2>&1
```

**Step 5: Create log directories**
```bash
# All VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm 'mkdir -p ~/logs'
done
```

---

## Part 3: SessionStart Hook Enhancements

### 3.1 Enhancement Design

**Purpose:** Show agents master staleness at every session start  
**Location:** `.claude/hooks/sessionstart_context.sh` in each product repo  
**Repos:** prime-radiant-ai, affordabot, llm-common, agent-skills

**Changes:**
Add master staleness check after "Git Status:" section, before "Feature Branches:"

**Implementation:**

```bash
# Add to sessionstart_context.sh after Git Status section:

# Master Branch Status
echo "Master Status:"
if command -v git >/dev/null 2>&1 && [ -d "$PROJECT_DIR/.git" ]; then
  git fetch origin ${CANONICAL_TRUNK_BRANCH:-master} --quiet 2>/dev/null || true
  
  LOCAL_MASTER=$(git rev-parse ${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "")
  REMOTE_MASTER=$(git rev-parse origin/${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "")
  
  if [ -n "$LOCAL_MASTER" ] && [ -n "$REMOTE_MASTER" ]; then
    if [ "$LOCAL_MASTER" != "$REMOTE_MASTER" ]; then
      BEHIND=$(git rev-list --count ${CANONICAL_TRUNK_BRANCH:-master}..origin/${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "?")
      echo "  ⚠️  Local master is ${BEHIND} commits behind origin"
      echo "  💡 Fix: git fetch origin master:master --force"
      echo "  💡 Or: master-sync (updates all repos)"
    else
      echo "  ✅ Master is current"
    fi
  else
    echo "  ⚠️  Cannot verify master status"
  fi
fi
echo ""
```

### 3.2 Deployment

**Step 1: Update in prime-radiant-ai**
```bash
cd ~/prime-radiant-ai
# Edit .claude/hooks/sessionstart_context.sh
# Add the master status check section

git add .claude/hooks/sessionstart_context.sh
git commit -m "feat: add master staleness check to SessionStart hook"
git push origin master
```

**Step 2: Replicate to other repos**
```bash
# affordabot
cd ~/affordabot
# Copy the same change to .claude/hooks/sessionstart_context.sh
git add .claude/hooks/sessionstart_context.sh
git commit -m "feat: add master staleness check to SessionStart hook"
git push origin master

# llm-common
cd ~/llm-common
# Same change
git add .claude/hooks/sessionstart_context.sh
git commit -m "feat: add master staleness check to SessionStart hook"
git push origin master

# agent-skills
cd ~/agent-skills
# Same change to .claude/hooks/sessionstart_context.sh
git add .claude/hooks/sessionstart_context.sh
git commit -m "feat: add master staleness check to SessionStart hook"
git push origin master
```

**Step 3: Pull on all VMs**
```bash
# After pushing to origin, pull on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    for repo in "prime-radiant-ai" "affordabot" "llm-common" "agent-skills"; do
        ssh $vm "cd ~/$repo 2>/dev/null && git pull origin master || true"
    done
done
```

---

## Part 4: start-feature.sh Auto-Fix Enhancement

### 4.1 Enhancement Design

**File:** `~/agent-skills/core/feature-lifecycle/start.sh`  
**Purpose:** Automatically update master before creating feature branches  
**Current behavior:** Tries to sync current repo, fails silently  
**New behavior:** Force-update master ref, warn but continue if fails

**Changes:**

Replace the "0. Sync current repo" section (lines ~15-27) with:

```bash
# 0. Ensure master is current before branching
echo "Checking master branch status..."

# Get current repo path
REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_PATH"

# Determine master branch name
MASTER_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"
if ! git rev-parse --verify "$MASTER_BRANCH" >/dev/null 2>&1; then
  # Try 'main' if 'master' doesn't exist
  if git rev-parse --verify "main" >/dev/null 2>&1; then
    MASTER_BRANCH="main"
  fi
fi

# Fetch from origin
git fetch origin "$MASTER_BRANCH" --quiet 2>/dev/null || {
  echo "⚠️  Cannot fetch from origin (network issue?)"
  echo "Proceeding anyway, but master may be stale..."
}

# Check if master is stale
LOCAL_MASTER=$(git rev-parse "$MASTER_BRANCH" 2>/dev/null || echo "")
REMOTE_MASTER=$(git rev-parse "origin/$MASTER_BRANCH" 2>/dev/null || echo "")

if [[ -n "$LOCAL_MASTER" && -n "$REMOTE_MASTER" && "$LOCAL_MASTER" != "$REMOTE_MASTER" ]]; then
  BEHIND=$(git rev-list --count "$MASTER_BRANCH..origin/$MASTER_BRANCH" 2>/dev/null || echo "?")
  echo "⚠️  Local master is ${BEHIND} commits behind origin"
  echo "Updating master ref (safe, doesn't affect current branch)..."
  
  # Force-update master ref (doesn't checkout, just updates ref)
  if git fetch origin "$MASTER_BRANCH:$MASTER_BRANCH" --force 2>/dev/null; then
    echo "✅ Master updated to latest"
  else
    # Fallback: use branch -f
    if git branch -f "$MASTER_BRANCH" "origin/$MASTER_BRANCH" 2>/dev/null; then
      echo "✅ Master updated to latest (via branch -f)"
    else
      echo "⚠️  Could not update master (continuing anyway)"
    fi
  fi
else
  echo "✅ Master is current"
fi

echo ""
```

### 4.2 Deployment

```bash
# On homedesktop-wsl
cd ~/agent-skills
# Edit core/feature-lifecycle/start.sh with changes above

git add core/feature-lifecycle/start.sh
git commit -m "feat: auto-update master ref in start-feature before branching"
git push origin master

# Pull on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm "cd ~/agent-skills && git pull origin master"
done
```

---

## Part 5: AGENTS.md Updates (Agent Training)

### 5.1 Updates Required

**File:** `~/agent-skills/AGENTS.md`  
**Sections to update:**
1. Daily Workflow - Add master-sync requirement
2. Landing the Plane - Add rebase-on-master requirement
3. Quick Commands Reference - Add master-sync
4. Troubleshooting - Add master staleness section

**Changes:**

#### Section 1: Daily Workflow (after "Start Here")

```markdown
## Daily Workflow

**CRITICAL: Before starting ANY feature work:**

1. **Update master across all repos:**
   ```bash
   master-sync
   ```
   This ensures you're branching from the latest code.

2. **Check SessionStart banner** - Shows master status automatically

3. **Start feature work:**
   ```bash
   start-feature bd-xxx
   ```
   (This also auto-updates master, but running `master-sync` first is best practice)

**During work:**
- `sync-feature "message"` - Save work frequently
- SessionStart hook will warn if master becomes stale

**Why this matters:**
- 9-12 autonomous agents working across 3 VMs
- Master syncs every 15min via cron
- Stale master = merge conflicts later
- Fresh master = clean rebases
```

#### Section 2: Landing the Plane (update existing section)

```markdown
## Landing the Plane (Session Completion)

**MANDATORY WORKFLOW:**

1. **Ensure master is current:**
   ```bash
   # Update master ref (doesn't checkout, safe on feature branch)
   git fetch origin master:master --force
   ```

2. **Rebase on fresh master:**
   ```bash
   git rebase master
   ```
   If conflicts: resolve them in your feature branch, NOT in master.

3. **Run quality gates** (if code changed):
   ```bash
   make ci-lite  # or sync-feature (runs ci-lite automatically)
   ```

4. **Push to remote:**
   ```bash
   git push origin HEAD
   ```
   Pre-push hook will warn if master is stale (informational, won't block).

5. **Create PR** (if ready):
   ```bash
   # Use GitHub CLI or web interface
   gh pr create --fill
   ```

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER push to master directly (pre-push hook blocks this)
- NEVER force-push to master
- ALWAYS rebase on master before creating PR
```

#### Section 3: Quick Commands Reference (update table)

```markdown
## Quick Commands Reference

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `master-sync` | Update master in all repos | Start of day, before feature work |
| `start-feature bd-xxx` | Start new feature | After master-sync |
| `sync-feature "msg"` | Save work + run CI | Frequently during work |
| `finish-feature` | Verify & create PR | When feature is complete |
| `dx-triage` | Check repo health | When confused about state |
| `dx-triage --fix` | Auto-fix safe issues | After dx-triage shows problems |
| `dx-check` | Verify environment | Session start, troubleshooting |
```

#### Section 4: Add new Troubleshooting section

```markdown
## Troubleshooting: Master Branch Staleness

### Symptom: "Local master is X commits behind"

**Shown in:**
- SessionStart hook banner
- Pre-push hook warnings
- dx-triage output

**Quick fix:**
```bash
# Option 1: Update just this repo
git fetch origin master:master --force

# Option 2: Update all repos (recommended)
master-sync
```

### Symptom: Merge conflicts when rebasing

**Cause:** Master was stale when you created feature branch

**Fix:**
```bash
# 1. Update master to latest
git fetch origin master:master --force

# 2. Rebase your feature branch on fresh master
git rebase master

# 3. Resolve conflicts in your feature branch
# 4. Continue rebase
git rebase --continue

# 5. Force-push your feature branch (safe, it's your branch)
git push origin HEAD --force-with-lease
```

### Symptom: "Cannot update master (continuing anyway)"

**Cause:** Network issue or git operation in progress

**Fix:**
```bash
# Check network
ping github.com

# Check for git lock
ls -la .git/index.lock
# If exists, wait for other git operation to finish, or:
rm .git/index.lock  # Only if you're sure no git operation is running

# Retry
master-sync
```

### Prevention

**master-sync cron runs every 15min on all VMs:**
- homedesktop-wsl: :00, :15, :30, :45
- macmini: :02, :17, :32, :47
- epyc6: :04, :19, :34, :49

**Check cron status:**
```bash
# View recent sync activity
tail -50 ~/logs/master-sync.log

# Check cron is running
crontab -l | grep master-sync
```
```

### 5.2 Deployment

```bash
# On homedesktop-wsl
cd ~/agent-skills
# Edit AGENTS.md with all changes above

git add AGENTS.md
git commit -m "docs: update AGENTS.md with master-sync workflow and troubleshooting"
git push origin master

# Pull on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm "cd ~/agent-skills && git pull origin master"
done
```

---

## Part 6: Pre-Push Hook Enhancements

### 6.1 Enhancement Design

**Files:**
- `~/prime-radiant-ai/.githooks/pre-push`
- `~/affordabot/.githooks/pre-push`
- `~/llm-common/.githooks/pre-push`
- `~/agent-skills/hooks/pre-push`

**Purpose:** Warn (don't block) when master is stale  
**Behavior:** Informational message with remediation steps

**Changes:**

Add after the "block pushes to default branch" section:

```bash
# Check if master is stale (informational warning, not blocking)
if command -v git >/dev/null 2>&1; then
  current_branch=$(git branch --show-current 2>/dev/null || echo "")
  default_branch=$(git remote show origin 2>/dev/null | sed -n 's/^\s*HEAD branch: //p')
  if [ -z "$default_branch" ]; then default_branch="master"; fi
  
  if [[ "$current_branch" != "$default_branch" ]]; then
    # On feature branch - check if master is stale
    git fetch origin "$default_branch" --quiet 2>/dev/null || true
    
    LOCAL_MASTER=$(git rev-parse "$default_branch" 2>/dev/null || echo "")
    REMOTE_MASTER=$(git rev-parse "origin/$default_branch" 2>/dev/null || echo "")
    
    if [[ -n "$LOCAL_MASTER" && -n "$REMOTE_MASTER" && "$LOCAL_MASTER" != "$REMOTE_MASTER" ]]; then
      BEHIND=$(git rev-list --count "$default_branch..origin/$default_branch" 2>/dev/null || echo "?")
      echo "" >&2
      echo "ℹ️  Note: Local $default_branch is ${BEHIND} commits behind origin" >&2
      echo "   This won't block your push, but consider rebasing:" >&2
      echo "   git fetch origin $default_branch:$default_branch --force && git rebase $default_branch" >&2
      echo "" >&2
    fi
  fi
fi
```

### 6.2 Deployment

```bash
# prime-radiant-ai
cd ~/prime-radiant-ai
# Edit .githooks/pre-push
git add .githooks/pre-push
git commit -m "feat: add master staleness warning to pre-push hook"
git push origin master

# affordabot
cd ~/affordabot
# Same change
git add .githooks/pre-push
git commit -m "feat: add master staleness warning to pre-push hook"
git push origin master

# llm-common
cd ~/llm-common
# Same change
git add .githooks/pre-push
git commit -m "feat: add master staleness warning to pre-push hook"
git push origin master

# agent-skills
cd ~/agent-skills
# Edit hooks/pre-push
git add hooks/pre-push
git commit -m "feat: add master staleness warning to pre-push hook"
git push origin master

# Pull on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    for repo in "prime-radiant-ai" "affordabot" "llm-common" "agent-skills"; do
        ssh $vm "cd ~/$repo 2>/dev/null && git pull origin master || true"
    done
done
```

---

## Part 7: dx-triage Enhancements

### 7.1 Enhancement Design

**File:** `~/agent-skills/scripts/dx-triage.sh`  
**Purpose:** Detect master staleness even when on feature branch  
**New check:** Add master-staleness to triage conditions

**Changes:**

In the repo checking loop, after the "Check behind/ahead" section (around line 120):

```bash
# Check if master ref is stale (even if on feature branch)
master_behind=0
master_stale=0
if [[ "$branch" != "$CANONICAL_TRUNK_BRANCH" ]]; then
  LOCAL_MASTER=$(git rev-parse "$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo "")
  REMOTE_MASTER=$(git rev-parse "origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo "")
  
  if [[ -n "$LOCAL_MASTER" && -n "$REMOTE_MASTER" && "$LOCAL_MASTER" != "$REMOTE_MASTER" ]]; then
    master_behind=$(git rev-list --count "$CANONICAL_TRUNK_BRANCH..origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo 0)
    if [[ "$master_behind" -gt 10 ]]; then
      master_stale=1
    fi
  fi
fi
```

Add to FLAG_REASON logic (around line 160):

```bash
# Add after existing FLAG_REASON checks:
elif [[ "$master_stale" -eq 1 ]]; then
  FLAG_REASON="Master ref is $master_behind commits behind (update: git fetch origin $CANONICAL_TRUNK_BRANCH:$CANONICAL_TRUNK_BRANCH --force)"
fi
```

In `dx-triage --fix` mode, add auto-fix for stale master (around line 250):

```bash
# In the fix mode section, add:
if [[ "$master_stale" -eq 1 ]]; then
  echo "  Updating master ref..."
  if git fetch origin "$CANONICAL_TRUNK_BRANCH:$CANONICAL_TRUNK_BRANCH" --force 2>/dev/null; then
    echo "  ✅ Master updated (+$master_behind commits)"
  else
    echo "  ⚠️  Failed to update master"
  fi
fi
```

### 7.2 Deployment

```bash
# On homedesktop-wsl
cd ~/agent-skills
# Edit scripts/dx-triage.sh with changes above

git add scripts/dx-triage.sh
git commit -m "feat: add master staleness detection and auto-fix to dx-triage"
git push origin master

# Deploy to all VMs
source scripts/canonical-targets.sh
deploy_to_all_vms scripts/dx-triage.sh ~/.local/bin/dx-triage

# Or manual:
ln -sf ~/agent-skills/scripts/dx-triage.sh ~/.local/bin/dx-triage
scp ~/agent-skills/scripts/dx-triage.sh fengning@macmini:~/.local/bin/dx-triage
scp ~/agent-skills/scripts/dx-triage.sh fengning@homedesktop-wsl:/tmp/dx-triage.sh
ssh fengning@homedesktop-wsl 'scp /tmp/dx-triage.sh feng@epyc6:~/.local/bin/dx-triage'
```

---

## Part 8: Deployment Checklist

### Phase 1: Bug Fixes (Day 1 - 30min)

**Priority:** P0 - Immediate  
**Impact:** Fixes broken sync on macmini and epyc6

- [ ] **macmini:** Fix bash version in crontab
  ```bash
  ssh fengning@macmini
  crontab -e
  # Change all 'ru' lines to use /opt/homebrew/bin/bash
  # Add --autostash flag
  ```
  
- [ ] **epyc6:** Fix dx-triage-cron unbound variable
  ```bash
  ssh feng@epyc6
  nano ~/.local/bin/dx-triage-cron
  # Add: hours_since_change=0 before line 145
  ```
  
- [ ] **homedesktop-wsl:** Add --autostash to ru sync cron
  ```bash
  crontab -e
  # Add --autostash to both ru sync lines
  ```

- [ ] **Verify fixes:**
  ```bash
  # macmini
  ssh fengning@macmini '/opt/homebrew/bin/bash ~/.local/bin/ru sync --non-interactive'
  
  # epyc6
  ssh feng@epyc6 '~/.local/bin/dx-triage-cron --verbose'
  
  # homedesktop-wsl
  tail -20 ~/logs/ru-sync.log  # Should show success
  ```

### Phase 2: master-sync Tool (Day 1-2 - 2 hours)

**Priority:** P0 - Core solution  
**Impact:** Enables 15min master sync across all VMs

- [ ] **Create master-sync.sh in agent-skills**
  ```bash
  cd ~/agent-skills
  # Create scripts/master-sync.sh
  chmod +x scripts/master-sync.sh
  git add scripts/master-sync.sh
  git commit -m "feat: add master-sync tool"
  git push origin master
  ```

- [ ] **Deploy canonical-targets.sh to all VMs**
  ```bash
  source ~/agent-skills/scripts/canonical-targets.sh
  deploy_to_all_vms ~/agent-skills/scripts/canonical-targets.sh ~/.local/bin/canonical-targets.sh
  ```

- [ ] **Deploy master-sync to all VMs**
  ```bash
  deploy_to_all_vms ~/agent-skills/scripts/master-sync.sh ~/.local/bin/master-sync
  ```

- [ ] **Create log directories on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      ssh $vm 'mkdir -p ~/logs'
  done
  ```

- [ ] **Add master-sync to crontab on all VMs**
  ```bash
  # homedesktop-wsl
  crontab -e
  # Add: 0,15,30,45 * * * * /home/fengning/.local/bin/master-sync >> ~/logs/master-sync.log 2>&1
  
  # macmini
  ssh fengning@macmini 'crontab -e'
  # Add: 2,17,32,47 * * * * /opt/homebrew/bin/bash ~/.local/bin/master-sync >> ~/logs/master-sync.log 2>&1
  
  # epyc6
  ssh feng@epyc6 'crontab -e'
  # Add: 4,19,34,49 * * * * /home/feng/.local/bin/master-sync >> ~/logs/master-sync.log 2>&1
  ```

- [ ] **Test master-sync manually on each VM**
  ```bash
  ssh fengning@homedesktop-wsl 'master-sync'
  ssh fengning@macmini '/opt/homebrew/bin/bash ~/.local/bin/master-sync'
  ssh feng@epyc6 'master-sync'
  ```

- [ ] **Monitor logs for 1 hour**
  ```bash
  # Check logs after 15min, 30min, 45min, 60min
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'tail -20 ~/logs/master-sync.log'
  done
  ```

### Phase 3: SessionStart Hook Updates (Day 2 - 1 hour)

**Priority:** P1 - Agent visibility  
**Impact:** Agents see master staleness at session start

- [ ] **Update prime-radiant-ai SessionStart hook**
  ```bash
  cd ~/prime-radiant-ai
  # Edit .claude/hooks/sessionstart_context.sh
  git add .claude/hooks/sessionstart_context.sh
  git commit -m "feat: add master staleness check"
  git push origin master
  ```

- [ ] **Update affordabot SessionStart hook**
  ```bash
  cd ~/affordabot
  # Same change
  git add .claude/hooks/sessionstart_context.sh
  git commit -m "feat: add master staleness check"
  git push origin master
  ```

- [ ] **Update llm-common SessionStart hook**
  ```bash
  cd ~/llm-common
  # Same change
  git add .claude/hooks/sessionstart_context.sh
  git commit -m "feat: add master staleness check"
  git push origin master
  ```

- [ ] **Update agent-skills SessionStart hook**
  ```bash
  cd ~/agent-skills
  # Same change
  git add .claude/hooks/sessionstart_context.sh
  git commit -m "feat: add master staleness check"
  git push origin master
  ```

- [ ] **Pull on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      for repo in "prime-radiant-ai" "affordabot" "llm-common" "agent-skills"; do
          ssh $vm "cd ~/$repo 2>/dev/null && git pull origin master || true"
      done
  done
  ```

- [ ] **Test SessionStart hook**
  ```bash
  # Start a new Claude Code session in each repo
  # Verify master status appears in banner
  ```

### Phase 4: start-feature.sh Enhancement (Day 2 - 30min)

**Priority:** P1 - Auto-fix at branch creation  
**Impact:** Agents always branch from fresh master

- [ ] **Update start-feature.sh**
  ```bash
  cd ~/agent-skills
  # Edit core/feature-lifecycle/start.sh
  git add core/feature-lifecycle/start.sh
  git commit -m "feat: auto-update master in start-feature"
  git push origin master
  ```

- [ ] **Pull on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      ssh $vm "cd ~/agent-skills && git pull origin master"
  done
  ```

- [ ] **Test start-feature**
  ```bash
  # In a test repo, make master stale:
  cd ~/prime-radiant-ai
  git branch -f master HEAD~5  # Make master 5 commits behind
  
  # Run start-feature
  ~/agent-skills/core/feature-lifecycle/start.sh bd-test-123
  
  # Verify master was updated
  git log master -1  # Should show latest commit
  ```

### Phase 5: AGENTS.md Updates (Day 3 - 1 hour)

**Priority:** P1 - Agent training  
**Impact:** Agents learn correct workflow

- [ ] **Update AGENTS.md**
  ```bash
  cd ~/agent-skills
  # Edit AGENTS.md with all sections
  git add AGENTS.md
  git commit -m "docs: update AGENTS.md with master-sync workflow"
  git push origin master
  ```

- [ ] **Pull on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      ssh $vm "cd ~/agent-skills && git pull origin master"
  done
  ```

- [ ] **Verify AGENTS.md is symlinked in all repos**
  ```bash
  for repo in "prime-radiant-ai" "affordabot" "llm-common"; do
      ls -la ~/$repo/AGENTS.md
      ls -la ~/$repo/GEMINI.md
      # Both should exist, GEMINI.md should be symlink to AGENTS.md
  done
  ```

### Phase 6: Pre-Push Hook Updates (Day 3 - 30min)

**Priority:** P2 - Additional guidance  
**Impact:** Agents warned at push time about stale master

- [ ] **Update pre-push hooks in all repos**
  ```bash
  # prime-radiant-ai
  cd ~/prime-radiant-ai
  # Edit .githooks/pre-push
  git add .githooks/pre-push
  git commit -m "feat: add master staleness warning"
  git push origin master
  
  # Repeat for affordabot, llm-common, agent-skills
  ```

- [ ] **Pull on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      for repo in "prime-radiant-ai" "affordabot" "llm-common" "agent-skills"; do
          ssh $vm "cd ~/$repo 2>/dev/null && git pull origin master || true"
      done
  done
  ```

- [ ] **Test pre-push hook**
  ```bash
  # Make master stale, push feature branch
  # Should see warning but push succeeds
  ```

### Phase 7: dx-triage Enhancement (Day 3 - 30min)

**Priority:** P2 - Recovery tool  
**Impact:** dx-triage can detect and fix stale master

- [ ] **Update dx-triage.sh**
  ```bash
  cd ~/agent-skills
  # Edit scripts/dx-triage.sh
  git add scripts/dx-triage.sh
  git commit -m "feat: add master staleness to dx-triage"
  git push origin master
  ```

- [ ] **Deploy to all VMs**
  ```bash
  source scripts/canonical-targets.sh
  deploy_to_all_vms scripts/dx-triage.sh ~/.local/bin/dx-triage
  ```

- [ ] **Test dx-triage**
  ```bash
  # Make master stale
  cd ~/prime-radiant-ai
  git branch -f master HEAD~10
  
  # Run dx-triage
  dx-triage
  # Should show "Master ref is 10 commits behind"
  
  # Run dx-triage --fix
  dx-triage --fix
  # Should auto-update master
  ```

### Phase 8: Verification (Day 4 - 2 hours)

**Priority:** P0 - Ensure everything works  
**Impact:** Catch issues before agents encounter them

- [ ] **Verify cron jobs on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'crontab -l | grep -E "ru sync|master-sync|dx-triage"'
  done
  ```

- [ ] **Verify logs show activity**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'tail -5 ~/logs/master-sync.log'
      ssh $vm 'tail -5 ~/logs/ru-sync.log'
      ssh $vm 'tail -5 ~/logs/dx-triage-cron.log'
  done
  ```

- [ ] **Check master status across all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'for repo in prime-radiant-ai agent-skills affordabot llm-common; do
          [ -d ~/$repo ] || continue
          cd ~/$repo
          behind=$(git rev-list --count master..origin/master 2>/dev/null || echo "?")
          echo "  $repo: master behind by $behind"
      done'
  done
  ```
  All should show "behind by 0"

- [ ] **Test agent workflow end-to-end**
  ```bash
  # 1. Start Claude Code session
  # 2. Verify SessionStart shows "Master is current"
  # 3. Run: start-feature bd-test-999
  # 4. Verify master was checked/updated
  # 5. Make a commit
  # 6. Run: sync-feature "test commit"
  # 7. Push
  # 8. Verify pre-push hook shows no warnings
  ```

- [ ] **Monitor for 24 hours**
  - Check logs every 4 hours
  - Verify master stays current
  - Watch for any cron failures

---

## Part 9: Monitoring & Maintenance

### 9.1 Daily Checks

**Command:**
```bash
# Run this daily for first week
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'for repo in prime-radiant-ai agent-skills affordabot llm-common; do
        [ -d ~/$repo ] || continue
        cd ~/$repo
        behind=$(git rev-list --count master..origin/master 2>/dev/null || echo "?")
        branch=$(git branch --show-current)
        echo "  $repo: on $branch, master behind by $behind"
    done'
done
```

**Expected output:**
```
=== fengning@homedesktop-wsl ===
  prime-radiant-ai: on master, master behind by 0
  agent-skills: on master, master behind by 0
  affordabot: on feature-bd-123, master behind by 0
  llm-common: on master, master behind by 0
=== fengning@macmini ===
  prime-radiant-ai: on bd-7coo-story-fixes, master behind by 0
  agent-skills: on master, master behind by 0
=== feng@epyc6 ===
  prime-radiant-ai: on master, master behind by 0
  agent-skills: on master, master behind by 0
```

### 9.2 Log Monitoring

**Check master-sync logs:**
```bash
# Should show activity every 15min
tail -50 ~/logs/master-sync.log

# Look for:
# - "Updated master (+N commits)" - Good, sync working
# - "Complete: X updated, Y current, 0 failed" - Good
# - "Failed to fetch" - Network issue, investigate
# - "Failed to update master ref" - Git issue, investigate
```

**Check ru-sync logs:**
```bash
# Should show activity daily at 12:00 UTC
tail -50 ~/logs/ru-sync.log

# Look for:
# - "✅ Updated: N repos" - Good
# - "⚠️ Conflicts: N repos" - Check which repos, may need manual fix
# - "✗ Pull failed" - Investigate cause
```

**Check dx-triage-cron logs:**
```bash
# Should show activity hourly
tail -50 ~/logs/dx-triage-cron.log

# Look for:
# - "dx-triage-cron complete: 0 repo(s) flagged" - Good
# - "FLAGGED: repo - reason" - Investigate flagged repo
# - Errors - Fix script issues
```

### 9.3 Troubleshooting

**Problem:** master-sync not running

```bash
# Check cron
crontab -l | grep master-sync

# Check if script exists
ls -la ~/.local/bin/master-sync

# Check if executable
chmod +x ~/.local/bin/master-sync

# Test manually
master-sync

# Check for errors
tail -50 ~/logs/master-sync.log
```

**Problem:** master still stale after sync

```bash
# Check if cron is actually running
grep master-sync /var/log/syslog  # Linux
grep master-sync /var/log/system.log  # macOS

# Check git connectivity
git fetch origin master

# Check for git locks
ls -la ~/prime-radiant-ai/.git/index.lock
# If exists, remove: rm ~/prime-radiant-ai/.git/index.lock

# Force sync manually
cd ~/prime-radiant-ai
git fetch origin master:master --force
```

**Problem:** Agents still creating PRs with stale master

```bash
# Check if SessionStart hook is running
# Start new Claude session, look for "Master Status:" in banner

# Check if start-feature is updated
cat ~/agent-skills/core/feature-lifecycle/start.sh | grep "Ensure master is current"

# Check AGENTS.md is current
head -50 ~/agent-skills/AGENTS.md | grep master-sync
```

---

## Part 10: Success Metrics

### Week 1 Targets

- [ ] **Zero master staleness** across all VMs (checked daily)
- [ ] **Zero cron failures** in master-sync logs
- [ ] **Zero agent-created PRs** with merge conflicts due to stale master
- [ ] **100% SessionStart hooks** showing master status

### Week 2 Targets

- [ ] **Agents using master-sync** proactively (check git logs for "Updated master" messages)
- [ ] **Zero dx-triage flags** for master staleness
- [ ] **All VMs syncing** within 15min of origin/master updates

### Month 1 Targets

- [ ] **Autonomous operation** - No manual intervention needed
- [ ] **Agent compliance** - Agents following workflow without prompting
- [ ] **Zero staleness incidents** - No merge conflicts due to stale master

---

## Appendix A: File Locations

### Tools (in agent-skills)
- `scripts/master-sync.sh` - New master sync tool
- `scripts/canonical-targets.sh` - Canonical VM/repo registry (existing)
- `scripts/dx-triage.sh` - Enhanced triage tool
- `scripts/dx-check.sh` - Environment checker (existing)
- `core/feature-lifecycle/start.sh` - Enhanced start-feature
- `core/feature-lifecycle/sync.sh` - Existing sync-feature
- `AGENTS.md` - Enhanced agent training doc

### Hooks (per repo)
- `.claude/hooks/sessionstart_context.sh` - Enhanced SessionStart
- `.githooks/pre-push` - Enhanced pre-push hook

### Cron Jobs (per VM)
- `~/logs/master-sync.log` - master-sync output
- `~/logs/ru-sync.log` - ru sync output
- `~/logs/dx-triage-cron.log` - dx-triage-cron output

### Binaries (per VM)
- `~/.local/bin/master-sync` - Symlink to agent-skills/scripts/master-sync.sh
- `~/.local/bin/dx-triage` - Symlink to agent-skills/scripts/dx-triage.sh
- `~/.local/bin/canonical-targets.sh` - Symlink to agent-skills/scripts/canonical-targets.sh
- `~/.local/bin/ru` - Existing repo updater

---

## Appendix B: VM-Specific Notes

### homedesktop-wsl (fengning@homedesktop-wsl)
- **OS:** Linux (WSL2)
- **Shell:** bash
- **Bash version:** 5.x (modern)
- **Canonical repos:** All 4 (agent-skills, prime-radiant-ai, affordabot, llm-common)
- **Role:** Primary development machine
- **Quirks:** None
- **Cron user:** fengning
- **Log path:** `/home/fengning/logs/`

### macmini (fengning@macmini)
- **OS:** macOS
- **Shell:** zsh (default), bash available
- **Bash version:** System bash 3.2 (outdated), Homebrew bash 5.3 at `/opt/homebrew/bin/bash`
- **Canonical repos:** agent-skills, prime-radiant-ai (required); affordabot, llm-common (optional)
- **Role:** macOS builds, iOS development
- **Quirks:** 
  - MUST use `/opt/homebrew/bin/bash` for all bash scripts in cron
  - Has launchd auto-checkpoint service
- **Cron user:** fengning
- **Log path:** `/Users/fengning/logs/`

### epyc6 (feng@epyc6)
- **OS:** Linux
- **Shell:** bash
- **Bash version:** 5.x (modern)
- **Canonical repos:** agent-skills (required); prime-radiant-ai, affordabot, llm-common (optional)
- **Role:** GPU work, ML training, heavy compute
- **Quirks:**
  - User is `feng` not `fengning`
  - No `jq` installed (no sudo access)
  - May need jump host (homedesktop-wsl) for SSH
  - dx-triage-cron had unbound variable bug (now fixed)
- **Cron user:** feng
- **Log path:** `/home/feng/logs/`

---

## Appendix C: Canonical Repos

### prime-radiant-ai
- **GitHub:** stars-end/prime-radiant-ai
- **Trunk branch:** master
- **Primary VMs:** homedesktop-wsl, macmini
- **Purpose:** Main product repo
- **Hooks:** .githooks/pre-push, .claude/hooks/sessionstart_context.sh

### agent-skills
- **GitHub:** stars-end/agent-skills
- **Trunk branch:** master
- **Primary VMs:** All 3 (required on all)
- **Purpose:** Global skills and automation
- **Hooks:** hooks/pre-push, .claude/hooks/sessionstart_context.sh

### affordabot
- **GitHub:** stars-end/affordabot
- **Trunk branch:** master
- **Primary VMs:** homedesktop-wsl
- **Purpose:** Affordabot product
- **Hooks:** .githooks/pre-push, .claude/hooks/sessionstart_context.sh

### llm-common
- **GitHub:** stars-end/llm-common
- **Trunk branch:** master
- **Primary VMs:** homedesktop-wsl
- **Purpose:** Shared LLM utilities
- **Hooks:** .githooks/pre-push, .claude/hooks/sessionstart_context.sh

---

## Appendix D: Quick Reference Commands

### For You (Human)

```bash
# Check master status across all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'for repo in prime-radiant-ai agent-skills affordabot llm-common; do
        [ -d ~/$repo ] || continue
        cd ~/$repo
        behind=$(git rev-list --count master..origin/master 2>/dev/null || echo "?")
        echo "  $repo: behind by $behind"
    done'
done

# Deploy a file to all VMs
source ~/agent-skills/scripts/canonical-targets.sh
deploy_to_all_vms <source_file> <dest_path>

# Check cron status on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'crontab -l'
done

# Check logs on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'tail -20 ~/logs/master-sync.log'
done
```

### For Agents

```bash
# Update master across all repos
master-sync

# Start feature work (auto-updates master)
start-feature bd-xxx

# Save work
sync-feature "commit message"

# Check repo health
dx-triage

# Fix repo issues
dx-triage --fix

# Check environment
dx-check
```

---

**END OF IMPLEMENTATION PLAN**
