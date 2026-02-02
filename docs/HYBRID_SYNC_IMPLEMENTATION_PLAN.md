# Hybrid Multi-VM Sync Implementation Plan
## Safety-First Approach: Zero Code Loss, Zero Silent Failures

**Created:** 2026-02-01  
**Priority:** Safety and Robustness > Speed  
**Principle:** Preserve agent work at all costs, fail loudly never silently

---

## Executive Summary

### The Safety-First Philosophy

**Core Principle:** An agent's uncommitted work is sacred. We will NEVER silently discard it.

**Design Constraints:**
1. **No silent failures** - Every error must log, alert, and be visible
2. **No data loss** - Always backup before destructive operations
3. **Fail-safe defaults** - If uncertain, preserve work and alert human
4. **Loud failures** - Agents must see problems immediately, not discover them later
5. **Graceful degradation** - Partial sync is better than no sync

### What We're Fixing

| Issue | Impact | Safety Risk | Solution |
|-------|--------|-------------|----------|
| macmini bash 3.2 | ru sync fails 100% | **SILENT FAILURE** - no alerts | Fix cron, add health checks |
| epyc6 dx-triage crash | No staleness detection | **SILENT FAILURE** - crashes quietly | Fix bug, add crash alerts |
| macmini stuck on feature branch | 18 commits behind | **CODE LOSS RISK** - reset would discard work | Safe migration with backup |
| homedesktop dirty tree | ru sync skips repo | **SILENT FAILURE** - no warning to agent | Add --autostash, alert on skip |
| No work preservation | Nuclear reset loses uncommitted work | **CODE LOSS** - agents lose hours of work | Pre-flight checks, auto-backup |

---

## Part 1: Immediate Safety Fixes (P0 - 1 hour)

### 1.1 Fix Silent Failures with Health Checks

**Problem:** Cron jobs fail silently, agents never know

**Solution:** Add health check wrapper for all cron jobs

#### Create cron-wrapper.sh

**Location:** `~/agent-skills/scripts/cron-wrapper.sh`

```bash
#!/usr/bin/env bash
# cron-wrapper.sh
# Wraps cron jobs to detect and alert on failures
# Usage: cron-wrapper.sh <job-name> <command> [args...]

set -euo pipefail

JOB_NAME="$1"
shift
COMMAND="$@"

LOG_DIR="$HOME/logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
LOG_FILE="$LOG_DIR/${JOB_NAME}.log"
HEALTH_FILE="$LOG_DIR/${JOB_NAME}.health"
ALERT_FILE="$LOG_DIR/${JOB_NAME}.ALERT"

# Remove old alert if exists (will recreate if still failing)
rm -f "$ALERT_FILE"

echo "[$TIMESTAMP] Starting $JOB_NAME" >> "$LOG_FILE"

# Run command and capture exit code
set +e
OUTPUT=$($COMMAND 2>&1)
EXIT_CODE=$?
set -e

echo "$OUTPUT" >> "$LOG_FILE"

if [[ $EXIT_CODE -eq 0 ]]; then
    # Success - update health file
    echo "[$TIMESTAMP] SUCCESS" > "$HEALTH_FILE"
    echo "[$TIMESTAMP] $JOB_NAME completed successfully" >> "$LOG_FILE"
else
    # Failure - create alert file
    cat > "$ALERT_FILE" <<EOF
⚠️  CRON JOB FAILURE ⚠️

Job:       $JOB_NAME
Time:      $TIMESTAMP
Exit Code: $EXIT_CODE
Log:       $LOG_FILE

Last output:
$(echo "$OUTPUT" | tail -20)

Action Required:
1. Check log: tail -50 $LOG_FILE
2. Fix the issue
3. Test manually: $COMMAND
4. Alert will clear on next successful run
EOF
    
    echo "[$TIMESTAMP] FAILED (exit $EXIT_CODE)" > "$HEALTH_FILE"
    echo "[$TIMESTAMP] $JOB_NAME FAILED - Alert created at $ALERT_FILE" >> "$LOG_FILE"
    
    # Also log to syslog if available
    logger -t "cron-wrapper" -p user.err "$JOB_NAME failed with exit code $EXIT_CODE" 2>/dev/null || true
fi

exit $EXIT_CODE
```

**Deployment:**
```bash
cd ~/agent-skills/scripts
# Create cron-wrapper.sh with above content
chmod +x cron-wrapper.sh

git add cron-wrapper.sh
git commit -m "feat: add cron-wrapper for health monitoring and alerts"
git push origin master

# Deploy to all VMs
scp ~/agent-skills/scripts/cron-wrapper.sh fengning@macmini:~/agent-skills/scripts/
ssh fengning@homedesktop-wsl 'scp ~/agent-skills/scripts/cron-wrapper.sh feng@epyc6:~/agent-skills/scripts/'
```

---

### 1.2 Fix macmini Bash Version (With Health Check)

**Current state:** Fails silently every 4 hours

**Fix:**
```bash
ssh fengning@macmini

# Backup crontab
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)

# Edit crontab
crontab -e

# OLD (failing silently):
# 0 12 * * * /Users/fengning/.local/bin/ru sync --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1
# 5 */4 * * * /Users/fengning/.local/bin/ru sync stars-end/agent-skills --non-interactive --quiet >> /Users/fengning/logs/ru-sync.log 2>&1

# NEW (with health monitoring):
0 12 * * * /opt/homebrew/bin/bash /Users/fengning/agent-skills/scripts/cron-wrapper.sh ru-sync '/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync --autostash --non-interactive'
5 */4 * * * /opt/homebrew/bin/bash /Users/fengning/agent-skills/scripts/cron-wrapper.sh ru-sync-agent-skills '/opt/homebrew/bin/bash /Users/fengning/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive'
```

**Verification:**
```bash
# Test manually
/opt/homebrew/bin/bash ~/agent-skills/scripts/cron-wrapper.sh ru-sync-test '/opt/homebrew/bin/bash ~/.local/bin/ru sync --non-interactive'

# Check health file
cat ~/logs/ru-sync-test.health
# Should show: [timestamp] SUCCESS

# Check for alerts
ls -la ~/logs/*.ALERT
# Should be empty
```

---

### 1.3 Fix epyc6 dx-triage-cron (With Crash Detection)

**Current state:** Crashes with unbound variable, no alert

**Fix:**
```bash
ssh feng@epyc6

# Backup
cp ~/.local/bin/dx-triage-cron ~/.local/bin/dx-triage-cron.backup.$(date +%Y%m%d-%H%M%S)

# Edit dx-triage-cron
nano ~/.local/bin/dx-triage-cron

# Find line ~118, add initialization:
    last_file_change=0
    hours_since_change=0  # SAFETY: Initialize before conditional to prevent unbound variable crash
    if [[ "$dirty_count" -gt 0 ]]; then

# Update crontab to use wrapper
crontab -e

# OLD:
# 0 * * * * ~/.local/bin/dx-triage-cron >> ~/logs/dx-triage-cron.log 2>&1

# NEW:
0 * * * * ~/agent-skills/scripts/cron-wrapper.sh dx-triage-cron '~/.local/bin/dx-triage-cron'
```

**Verification:**
```bash
# Test manually
~/agent-skills/scripts/cron-wrapper.sh dx-triage-test '~/.local/bin/dx-triage-cron'

# Should complete without errors
cat ~/logs/dx-triage-test.health
# Should show: SUCCESS

# Check for alerts
ls -la ~/logs/*.ALERT
```

---

### 1.4 Fix homedesktop ru sync (With Skip Detection)

**Current state:** Skips dirty repos silently

**Fix:**
```bash
# On homedesktop-wsl
crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)
crontab -e

# OLD:
# 0 12 * * * /home/fengning/.local/bin/ru sync --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1
# 0 */4 * * * /home/fengning/.local/bin/ru sync stars-end/agent-skills --non-interactive --quiet >> /home/fengning/logs/ru-sync.log 2>&1

# NEW (with wrapper and --autostash):
0 12 * * * ~/agent-skills/scripts/cron-wrapper.sh ru-sync '~/.local/bin/ru sync --autostash --non-interactive'
0 */4 * * * ~/agent-skills/scripts/cron-wrapper.sh ru-sync-agent-skills '~/.local/bin/ru sync stars-end/agent-skills --autostash --non-interactive'
```

---

### 1.5 Add SessionStart Alert Check

**Purpose:** Show agents any cron failures at session start

**Location:** All repos `.claude/hooks/sessionstart_context.sh`

**Add this section:**
```bash
# Cron Health Check
echo "System Health:"
ALERT_COUNT=$(ls -1 ~/logs/*.ALERT 2>/dev/null | wc -l)
if [[ $ALERT_COUNT -gt 0 ]]; then
  echo "  🚨 $ALERT_COUNT cron job(s) failing!"
  echo "  Check: ls -la ~/logs/*.ALERT"
  for alert in ~/logs/*.ALERT; do
    [[ -f "$alert" ]] && echo "    - $(basename $alert .ALERT)"
  done
  echo "  💡 Fix: Review alert files for details"
else
  echo "  ✅ All cron jobs healthy"
fi
echo ""
```

**Deployment:**
```bash
# Update in all repos
for repo in prime-radiant-ai affordabot llm-common agent-skills; do
  cd ~/$repo
  # Edit .claude/hooks/sessionstart_context.sh
  # Add the health check section
  git add .claude/hooks/sessionstart_context.sh
  git commit -m "feat: add cron health check to SessionStart"
  git push origin master
done
```

---

## Part 2: Safe Canonical Sync (P0 - 2 hours)

### 2.1 Design Philosophy: Preserve Work First

**Key Principle:** Never reset a repo with uncommitted work without explicit backup

**Safety Layers:**
1. **Pre-flight check** - Detect uncommitted work
2. **Auto-backup** - Stash to reflog with timestamp
3. **Alert creation** - Notify agent of backup location
4. **Graceful skip** - Don't reset if backup fails
5. **Recovery documentation** - Clear instructions in alert

---

### 2.2 Create canonical-sync-safe.sh

**Location:** `~/agent-skills/scripts/canonical-sync-safe.sh`

```bash
#!/usr/bin/env bash
# canonical-sync-safe.sh
# Keep canonical repos synchronized with origin/master
# SAFETY FIRST: Never discard uncommitted work without backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || {
    echo "Error: canonical-targets.sh not found" >&2
    exit 1
}

TRUNK="${CANONICAL_TRUNK_BRANCH:-master}"
LOG_PREFIX="[canonical-sync $(date +'%Y-%m-%d %H:%M:%S')]"
HOSTNAME=$(hostname -s)

# Collect repos
ALL_REPOS=()
[[ -v CANONICAL_REQUIRED_REPOS[@] ]] && ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
[[ -v CANONICAL_OPTIONAL_REPOS[@] ]] && ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")

SYNCED=0
SKIPPED=0
FAILED=0
BACKED_UP=0

for repo in "${ALL_REPOS[@]}"; do
    repo_path="$HOME/$repo"
    
    # Skip if repo doesn't exist
    if [[ ! -d "$repo_path/.git" ]]; then
        echo "$LOG_PREFIX $repo: Not present (optional repo)"
        ((SKIPPED++))
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
    
    # Fetch from origin (required for all checks)
    if ! git fetch origin --prune --quiet 2>/dev/null; then
        echo "$LOG_PREFIX $repo: Failed to fetch from origin (network issue?)"
        ((FAILED++))
        continue
    fi
    
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    DIRTY=$(git status --porcelain 2>/dev/null || echo "")
    
    # SAFETY CHECK: Detect uncommitted work
    if [[ -n "$DIRTY" ]]; then
        echo "$LOG_PREFIX $repo: Has uncommitted changes - creating backup"
        
        # Create timestamped stash with metadata
        STASH_MSG="canonical-sync-backup-$HOSTNAME-$(date +%Y%m%d-%H%M%S)"
        if git stash push -u -m "$STASH_MSG" 2>/dev/null; then
            STASH_HASH=$(git rev-parse stash@{0} 2>/dev/null || echo "unknown")
            
            # Create alert file for agent
            cat > "$HOME/logs/${repo}.WORK_PRESERVED" <<EOF
💾 WORK PRESERVED: $repo

Your uncommitted changes were automatically backed up before sync.

Backup Details:
  Stash:     $STASH_MSG
  Hash:      $STASH_HASH
  Time:      $(date +'%Y-%m-%d %H:%M:%S')
  Location:  $repo_path

To restore your work:
  cd $repo_path
  git stash list  # Find your stash
  git stash pop   # Restore most recent backup
  
Or by hash:
  git stash apply $STASH_HASH

Your work is safe in the git reflog for 90 days.
EOF
            
            echo "$LOG_PREFIX $repo: Work backed up to stash ($STASH_HASH)"
            ((BACKED_UP++))
        else
            # Stash failed - DO NOT PROCEED
            echo "$LOG_PREFIX $repo: FAILED to backup work - SKIPPING SYNC (safety)"
            
            cat > "$HOME/logs/${repo}.SYNC_BLOCKED" <<EOF
🚨 SYNC BLOCKED: $repo

Canonical sync detected uncommitted changes but failed to back them up.
Your work is SAFE but this repo was NOT synced.

Action Required:
1. Check your uncommitted changes:
   cd $repo_path
   git status
   
2. Manually save your work:
   git stash push -m "manual backup"
   OR
   git commit -am "WIP: save work"
   
3. Sync will retry automatically on next run

Your work was NOT modified.
EOF
            
            ((FAILED++))
            continue
        fi
    fi
    
    # SAFETY CHECK: Detect if on feature branch with unpushed commits
    if [[ "$CURRENT_BRANCH" != "$TRUNK" && "$CURRENT_BRANCH" != "main" ]]; then
        # Check if branch exists on remote
        if git rev-parse "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
            # Branch exists remotely - check if we're ahead
            AHEAD=$(git rev-list --count "origin/$CURRENT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || echo 0)
            if [[ $AHEAD -gt 0 ]]; then
                echo "$LOG_PREFIX $repo: On $CURRENT_BRANCH with $AHEAD unpushed commits - creating backup"
                
                # Create backup branch
                BACKUP_BRANCH="backup/$CURRENT_BRANCH-$(date +%Y%m%d-%H%M%S)"
                if git branch "$BACKUP_BRANCH" 2>/dev/null; then
                    cat > "$HOME/logs/${repo}.BRANCH_PRESERVED" <<EOF
💾 BRANCH PRESERVED: $repo

You were on branch '$CURRENT_BRANCH' with unpushed commits.
A backup branch was created before switching to master.

Backup Details:
  Original:  $CURRENT_BRANCH
  Backup:    $BACKUP_BRANCH
  Commits:   $AHEAD unpushed
  Time:      $(date +'%Y-%m-%d %H:%M:%S')

To restore your work:
  cd $repo_path
  git checkout $BACKUP_BRANCH
  git log -$AHEAD  # Review your commits
  
To push your work:
  git push origin $BACKUP_BRANCH
  # Then create PR on GitHub

Your work is safe.
EOF
                    echo "$LOG_PREFIX $repo: Branch backed up as $BACKUP_BRANCH"
                    ((BACKED_UP++))
                fi
            fi
        else
            # Local-only branch with commits - definitely back up
            echo "$LOG_PREFIX $repo: On local-only branch $CURRENT_BRANCH - creating backup"
            BACKUP_BRANCH="backup/$CURRENT_BRANCH-$(date +%Y%m%d-%H%M%S)"
            git branch "$BACKUP_BRANCH" 2>/dev/null || true
            ((BACKED_UP++))
        fi
    fi
    
    # Now safe to reset to master
    echo "$LOG_PREFIX $repo: Syncing to origin/$TRUNK"
    
    # Checkout master (or main)
    if git show-ref --verify --quiet "refs/heads/$TRUNK"; then
        git checkout -f "$TRUNK" 2>/dev/null || {
            echo "$LOG_PREFIX $repo: Failed to checkout $TRUNK"
            ((FAILED++))
            continue
        }
    elif git show-ref --verify --quiet "refs/heads/main"; then
        git checkout -f main 2>/dev/null || {
            echo "$LOG_PREFIX $repo: Failed to checkout main"
            ((FAILED++))
            continue
        }
        TRUNK="main"
    else
        echo "$LOG_PREFIX $repo: Neither master nor main branch exists"
        ((FAILED++))
        continue
    fi
    
    # Reset to origin
    if git reset --hard "origin/$TRUNK" 2>/dev/null; then
        # Clean untracked files
        git clean -fdx 2>/dev/null || true
        echo "$LOG_PREFIX $repo: ✅ Synced to origin/$TRUNK"
        ((SYNCED++))
    else
        echo "$LOG_PREFIX $repo: Failed to reset to origin/$TRUNK"
        ((FAILED++))
    fi
done

# Summary
echo "$LOG_PREFIX Complete: $SYNCED synced, $BACKED_UP backed up, $SKIPPED skipped, $FAILED failed"

# Exit with error if any failures
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
```

---

### 2.3 Add .CANONICAL_REPO Marker Files

**Purpose:** Visual warning in file trees

**Implementation:**
```bash
# On homedesktop-wsl
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    [[ ! -d ~/$repo ]] && continue
    
    cat > ~/$repo/.CANONICAL_REPO <<EOF
⚠️  CANONICAL REPOSITORY - READ ONLY ⚠️

This directory is a synchronized mirror of origin/master.
It auto-syncs daily and will reset to origin/master.

🚨 DO NOT COMMIT DIRECTLY HERE 🚨

For development work, use worktrees:
  dx-worktree create bd-xxxx $repo
  cd /tmp/agents/bd-xxxx/$repo
  # Work here instead

Why?
- Canonical repos stay clean across all VMs
- Your work in worktrees is isolated and safe
- PRs merge to origin/master, then sync here automatically

If you accidentally committed here:
- Your work is backed up in git reflog
- Check ~/logs/${repo}.WORK_PRESERVED for recovery instructions
EOF
    
    # Add to .gitignore (don't commit the marker)
    grep -q "^\.CANONICAL_REPO$" ~/$repo/.gitignore 2>/dev/null || \
        echo ".CANONICAL_REPO" >> ~/$repo/.gitignore
done
```

---

### 2.4 Deploy canonical-sync-safe.sh

**Schedule:** Daily at 3am (low-traffic time), staggered by VM

```bash
# Create script
cd ~/agent-skills/scripts
# Create canonical-sync-safe.sh with above content
chmod +x canonical-sync-safe.sh

git add canonical-sync-safe.sh
git commit -m "feat: add safe canonical sync with work preservation"
git push origin master

# Deploy to all VMs
scp ~/agent-skills/scripts/canonical-sync-safe.sh fengning@macmini:~/agent-skills/scripts/
ssh fengning@homedesktop-wsl 'scp ~/agent-skills/scripts/canonical-sync-safe.sh feng@epyc6:~/agent-skills/scripts/'

# Add to crontab (DAILY, not hourly - safety first)
# homedesktop-wsl
crontab -e
# Add:
0 3 * * * ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'

# macmini
ssh fengning@macmini 'crontab -e'
# Add:
5 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'

# epyc6
ssh feng@epyc6 'crontab -e'
# Add:
10 3 * * * ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'
```

---

### 2.5 Manual Migration: Fix macmini Stuck Branch (SAFE)

**Current state:** macmini on `bd-7coo-story-fixes` (already merged)

**Safe migration:**
```bash
ssh fengning@macmini

cd ~/prime-radiant-ai

# 1. Check for any uncommitted work
git status

# 2. If dirty, back it up
if [[ -n "$(git status --porcelain)" ]]; then
    git stash push -u -m "pre-migration-backup-$(date +%Y%m%d-%H%M%S)"
    echo "Work backed up to stash"
fi

# 3. Check if current branch has unpushed commits
CURRENT_BRANCH=$(git branch --show-current)
if git rev-parse "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
    AHEAD=$(git rev-list --count "origin/$CURRENT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || echo 0)
    if [[ $AHEAD -gt 0 ]]; then
        # Create backup branch
        BACKUP_BRANCH="backup/$CURRENT_BRANCH-$(date +%Y%m%d-%H%M%S)"
        git branch "$BACKUP_BRANCH"
        echo "Created backup branch: $BACKUP_BRANCH"
    fi
fi

# 4. Fetch latest
git fetch origin --prune

# 5. Switch to master
git checkout master

# 6. Reset to origin/master
git reset --hard origin/master

# 7. Clean
git clean -fdx

# 8. Verify
git status
git log -1
```

---

## Part 3: Agent Guidance & Training (P1 - 1 hour)

### 3.1 Update AGENTS.md (Comprehensive)

**Location:** `~/agent-skills/AGENTS.md`

**Add new section after "## Daily Workflow":**

```markdown
## CRITICAL: Canonical Repo Safety Rules

### What Are Canonical Repos?

These directories are **read-only mirrors** of `origin/master`:
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

They sync daily at 3am across all VMs (homedesktop-wsl, macmini, epyc6).

### 🚨 NEVER Work Directly in Canonical Repos

**Why?**
- Daily sync will reset them to origin/master
- Your uncommitted work will be backed up, but you'll lose time
- Other agents/VMs need consistent state

**How to know if you're in a canonical repo?**
```bash
# Check for marker file
ls -la .CANONICAL_REPO

# Or check git directory
git rev-parse --git-dir
# If shows `.git` → Canonical repo (don't work here)
# If shows `.git/worktrees/...` → Worktree (safe to work)
```

### ✅ CORRECT: Use Worktrees for Development

**Every time you start work:**
```bash
# 1. Create worktree for your issue
dx-worktree create bd-xxxx prime-radiant-ai

# 2. Change to worktree directory
cd /tmp/agents/bd-xxxx/prime-radiant-ai

# 3. Verify you're in a worktree
git rev-parse --git-dir
# Should show: .git/worktrees/...

# 4. Work normally
git checkout -b bd-xxxx
# Make changes, commit, push
git commit -am "your changes"
git push origin bd-xxxx
```

**Why worktrees?**
- Isolated from canonical repo
- Your work is safe from daily sync
- Can have multiple issues in progress
- Easy cleanup when done

### What If I Accidentally Worked in Canonical?

**Don't panic - your work is backed up automatically.**

Check for backup alerts:
```bash
ls -la ~/logs/*.WORK_PRESERVED
ls -la ~/logs/*.BRANCH_PRESERVED
```

**Restore uncommitted changes:**
```bash
cd ~/prime-radiant-ai
git stash list  # Find your backup
git stash pop   # Restore most recent
```

**Restore from backup branch:**
```bash
cd ~/prime-radiant-ai
git branch -a | grep backup/  # Find your backup
git checkout backup/bd-xxxx-20260201-030500
git log -5  # Review your commits
git push origin backup/bd-xxxx-20260201-030500  # Push to remote
```

**Your work is in reflog for 90 days:**
```bash
cd ~/prime-radiant-ai
git reflog  # Shows all recent commits
git show <commit-hash>  # View your changes
git cherry-pick <commit-hash>  # Apply to worktree
```

### Daily Workflow (Updated)

**1. Session Start:**
```bash
# Check system health
# SessionStart hook will show any cron failures

# Check for work preservation alerts
ls -la ~/logs/*.WORK_PRESERVED
ls -la ~/logs/*.BRANCH_PRESERVED
```

**2. Start Work:**
```bash
# ALWAYS use worktrees
dx-worktree create bd-xxxx prime-radiant-ai
cd /tmp/agents/bd-xxxx/prime-radiant-ai

# Verify you're in worktree
git rev-parse --git-dir | grep worktrees || echo "⚠️  NOT IN WORKTREE!"

# Create feature branch
git checkout -b bd-xxxx
```

**3. During Work:**
```bash
# Save frequently
git commit -am "progress checkpoint"
git push origin bd-xxxx
```

**4. End Session:**
```bash
# Push all work
git push origin bd-xxxx

# Create PR if ready
gh pr create --fill

# Cleanup worktree (optional, can keep for next session)
dx-worktree cleanup bd-xxxx
```

### Troubleshooting

**"My changes disappeared!"**
```bash
# Check backup alerts
cat ~/logs/prime-radiant-ai.WORK_PRESERVED

# Check stash
cd ~/prime-radiant-ai
git stash list

# Check reflog
git reflog | head -20
```

**"Cron job failing"**
```bash
# Check alerts
ls -la ~/logs/*.ALERT

# Read alert details
cat ~/logs/ru-sync.ALERT

# Check health status
cat ~/logs/ru-sync.health
```

**"How do I know if canonical sync is working?"**
```bash
# Check last sync time
tail -20 ~/logs/canonical-sync.log

# Check health
cat ~/logs/canonical-sync.health

# Verify master is current
cd ~/prime-radiant-ai
git fetch origin
git log master..origin/master  # Should be empty
```
```

---

### 3.2 Update SessionStart Hook (All Repos)

**Add to `.claude/hooks/sessionstart_context.sh`:**

```bash
# Canonical Repo Warning
if [[ -f "$PROJECT_DIR/.CANONICAL_REPO" ]]; then
  echo "⚠️  CANONICAL REPOSITORY WARNING ⚠️"
  echo "  This is a read-only mirror. Use worktrees for development:"
  echo "  dx-worktree create bd-xxxx $(basename $PROJECT_DIR)"
  echo ""
fi

# Work Preservation Alerts
REPO_NAME=$(basename "$PROJECT_DIR")
if [[ -f "$HOME/logs/${REPO_NAME}.WORK_PRESERVED" ]]; then
  echo "💾 WORK PRESERVED ALERT"
  echo "  Your uncommitted changes were backed up during sync."
  echo "  Details: cat ~/logs/${REPO_NAME}.WORK_PRESERVED"
  echo ""
fi

if [[ -f "$HOME/logs/${REPO_NAME}.BRANCH_PRESERVED" ]]; then
  echo "💾 BRANCH PRESERVED ALERT"
  echo "  Your feature branch was backed up during sync."
  echo "  Details: cat ~/logs/${REPO_NAME}.BRANCH_PRESERVED"
  echo ""
fi

# Cron Health Check (from Part 1)
echo "System Health:"
ALERT_COUNT=$(ls -1 ~/logs/*.ALERT 2>/dev/null | wc -l)
if [[ $ALERT_COUNT -gt 0 ]]; then
  echo "  🚨 $ALERT_COUNT cron job(s) failing!"
  echo "  Check: ls -la ~/logs/*.ALERT"
  for alert in ~/logs/*.ALERT; do
    [[ -f "$alert" ]] && echo "    - $(basename $alert .ALERT)"
  done
  echo "  💡 Fix: Review alert files for details"
else
  echo "  ✅ All cron jobs healthy"
fi
echo ""

# Master Status (keep from original plan)
echo "Master Status:"
if command -v git >/dev/null 2>&1 && [ -d "$PROJECT_DIR/.git" ]; then
  git fetch origin ${CANONICAL_TRUNK_BRANCH:-master} --quiet 2>/dev/null || true
  
  LOCAL_MASTER=$(git rev-parse ${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "")
  REMOTE_MASTER=$(git rev-parse origin/${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "")
  
  if [ -n "$LOCAL_MASTER" ] && [ -n "$REMOTE_MASTER" ]; then
    if [ "$LOCAL_MASTER" != "$REMOTE_MASTER" ]; then
      BEHIND=$(git rev-list --count ${CANONICAL_TRUNK_BRANCH:-master}..origin/${CANONICAL_TRUNK_BRANCH:-master} 2>/dev/null || echo "?")
      echo "  ⚠️  Local master is ${BEHIND} commits behind origin"
      echo "  💡 Will auto-sync at 3am, or run: canonical-sync-safe.sh"
    else
      echo "  ✅ Master is current"
    fi
  else
    echo "  ⚠️  Cannot verify master status"
  fi
fi
echo ""
```

---

### 3.3 Update Pre-Push Hook (Canonical Repo Block)

**Location:** `~/agent-skills/hooks/pre-push` (and each product repo `.githooks/pre-push`)

```bash
#!/usr/bin/env bash
# Pre-push hook: Guide agents to worktrees

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --git-dir)

# Check if this is a canonical repo (not a worktree)
if [[ -f "$REPO_ROOT/.CANONICAL_REPO" && "$GIT_DIR" == "$REPO_ROOT/.git" ]]; then
  echo ""
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║  🚨 PUSH BLOCKED: This is a canonical repository        ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""
  echo "Canonical repos are read-only mirrors. Use worktrees instead:"
  echo ""
  echo "  1. Create worktree for your issue:"
  echo "     dx-worktree create bd-xxxx $(basename $REPO_ROOT)"
  echo ""
  echo "  2. Work in the worktree:"
  echo "     cd /tmp/agents/bd-xxxx/$(basename $REPO_ROOT)"
  echo "     git commit -am 'your changes'"
  echo "     git push origin bd-xxxx"
  echo ""
  echo "  3. Canonical repo will auto-sync after PR merge."
  echo ""
  echo "Your current changes are SAFE - they're still in this repo."
  echo "Just move them to a worktree:"
  echo "  git stash"
  echo "  dx-worktree create bd-xxxx $(basename $REPO_ROOT)"
  echo "  cd /tmp/agents/bd-xxxx/$(basename $REPO_ROOT)"
  echo "  git stash pop"
  echo ""
  echo "If you need to bypass (testing only):"
  echo "  git push --no-verify"
  echo ""
  exit 1
fi

# Allow pushes from worktrees (normal flow)
# Continue with existing checks...
```

---

## Part 4: Monitoring & Alerting (P1 - 30 min)

### 4.1 Create Health Dashboard Script

**Location:** `~/agent-skills/scripts/health-dashboard.sh`

```bash
#!/usr/bin/env bash
# health-dashboard.sh
# Show system health across all VMs

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Multi-VM Canonical Sync Health Dashboard          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

check_vm_health() {
    local vm="$1"
    local vm_name="$2"
    
    echo "━━━ $vm_name ($vm) ━━━"
    
    # Check cron health
    echo "Cron Jobs:"
    ssh "$vm" 'for health in ~/logs/*.health; do
        [[ -f "$health" ]] || continue
        job=$(basename "$health" .health)
        status=$(tail -1 "$health" | grep -o "SUCCESS\|FAILED" || echo "UNKNOWN")
        if [[ "$status" == "SUCCESS" ]]; then
            echo "  ✅ $job"
        else
            echo "  ❌ $job"
        fi
    done' 2>/dev/null || echo "  ⚠️  Cannot connect to $vm"
    
    # Check for alerts
    echo "Alerts:"
    ALERT_COUNT=$(ssh "$vm" 'ls -1 ~/logs/*.ALERT 2>/dev/null | wc -l' 2>/dev/null || echo "?")
    if [[ "$ALERT_COUNT" == "0" ]]; then
        echo "  ✅ No alerts"
    else
        echo "  🚨 $ALERT_COUNT active alert(s)"
        ssh "$vm" 'for alert in ~/logs/*.ALERT; do
            [[ -f "$alert" ]] && echo "    - $(basename "$alert" .ALERT)"
        done' 2>/dev/null || true
    fi
    
    # Check canonical repos
    echo "Canonical Repos:"
    ssh "$vm" 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
        [[ -d ~/$repo ]] || continue
        cd ~/$repo
        branch=$(git branch --show-current 2>/dev/null || echo "?")
        behind=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "?")
        dirty=$(git status --porcelain 2>/dev/null | wc -l)
        
        if [[ "$branch" == "master" && "$behind" == "0" && "$dirty" == "0" ]]; then
            echo "  ✅ $repo"
        else
            echo "  ⚠️  $repo: branch=$branch, behind=$behind, dirty=$dirty"
        fi
    done' 2>/dev/null || echo "  ⚠️  Cannot check repos"
    
    echo ""
}

# Check all VMs
check_vm_health "fengning@homedesktop-wsl" "homedesktop-wsl"
check_vm_health "fengning@macmini" "macmini"
check_vm_health "feng@epyc6" "epyc6"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Run this daily: ~/agent-skills/scripts/health-dashboard.sh"
echo "Or add to cron: 0 9 * * * ~/agent-skills/scripts/health-dashboard.sh | mail -s 'VM Health' you@example.com"
```

**Deployment:**
```bash
cd ~/agent-skills/scripts
# Create health-dashboard.sh
chmod +x health-dashboard.sh

git add health-dashboard.sh
git commit -m "feat: add health dashboard for multi-VM monitoring"
git push origin master

# Test it
./health-dashboard.sh
```

---

### 4.2 Add Daily Health Email (Optional)

```bash
# On homedesktop-wsl (or wherever you check email)
crontab -e

# Add:
0 9 * * * ~/agent-skills/scripts/health-dashboard.sh > /tmp/health-report.txt && cat /tmp/health-report.txt
```

---

## Part 5: Deployment Checklist (Safety-First)

### Phase 1: Safety Infrastructure (Day 1 - 2 hours)

**DO NOT SKIP - These prevent silent failures**

- [ ] **Create cron-wrapper.sh**
  ```bash
  cd ~/agent-skills/scripts
  # Create cron-wrapper.sh
  chmod +x cron-wrapper.sh
  git add cron-wrapper.sh
  git commit -m "feat: add cron health monitoring wrapper"
  git push origin master
  ```

- [ ] **Deploy cron-wrapper to all VMs**
  ```bash
  scp ~/agent-skills/scripts/cron-wrapper.sh fengning@macmini:~/agent-skills/scripts/
  ssh fengning@homedesktop-wsl 'scp ~/agent-skills/scripts/cron-wrapper.sh feng@epyc6:~/agent-skills/scripts/'
  ssh fengning@macmini 'chmod +x ~/agent-skills/scripts/cron-wrapper.sh'
  ssh feng@epyc6 'chmod +x ~/agent-skills/scripts/cron-wrapper.sh'
  ```

- [ ] **Update all cron jobs to use wrapper (homedesktop-wsl)**
  ```bash
  crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)
  crontab -e
  # Wrap all existing jobs with cron-wrapper.sh
  ```

- [ ] **Update all cron jobs to use wrapper (macmini)**
  ```bash
  ssh fengning@macmini
  crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)
  crontab -e
  # Use /opt/homebrew/bin/bash
  # Wrap with cron-wrapper.sh
  # Add --autostash to ru sync
  ```

- [ ] **Update all cron jobs to use wrapper (epyc6)**
  ```bash
  ssh feng@epyc6
  crontab -l > ~/crontab.backup.$(date +%Y%m%d-%H%M%S)
  crontab -e
  # Wrap with cron-wrapper.sh
  # Fix dx-triage-cron unbound variable first
  ```

- [ ] **Wait 1 hour and verify health files**
  ```bash
  # Check all VMs
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'ls -la ~/logs/*.health'
      ssh $vm 'cat ~/logs/*.health'
  done
  ```

- [ ] **Check for any alerts**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'ls -la ~/logs/*.ALERT 2>/dev/null || echo "No alerts"'
  done
  ```

**STOP HERE if any alerts exist. Fix them before proceeding.**

---

### Phase 2: Safe Canonical Sync (Day 2 - 2 hours)

**DO NOT DEPLOY until Phase 1 is verified working**

- [ ] **Create canonical-sync-safe.sh**
  ```bash
  cd ~/agent-skills/scripts
  # Create canonical-sync-safe.sh with full safety checks
  chmod +x canonical-sync-safe.sh
  ```

- [ ] **Test canonical-sync-safe.sh locally (dry run)**
  ```bash
  # Add dry-run mode to script for testing
  # Or test on a non-critical repo first
  cd ~/agent-skills
  git checkout -b test-canonical-sync
  # Make some uncommitted changes
  echo "test" >> test.txt
  
  # Run sync
  ~/agent-skills/scripts/canonical-sync-safe.sh
  
  # Verify:
  # 1. Changes were stashed
  # 2. Alert file created
  # 3. Can restore from stash
  git stash list
  git stash pop
  ```

- [ ] **Commit and push canonical-sync-safe.sh**
  ```bash
  git add scripts/canonical-sync-safe.sh
  git commit -m "feat: add safe canonical sync with work preservation"
  git push origin master
  ```

- [ ] **Deploy to all VMs**
  ```bash
  scp ~/agent-skills/scripts/canonical-sync-safe.sh fengning@macmini:~/agent-skills/scripts/
  ssh fengning@homedesktop-wsl 'scp ~/agent-skills/scripts/canonical-sync-safe.sh feng@epyc6:~/agent-skills/scripts/'
  ```

- [ ] **Add .CANONICAL_REPO markers**
  ```bash
  for repo in agent-skills prime-radiant-ai affordabot llm-common; do
      [[ -d ~/$repo ]] && cat > ~/$repo/.CANONICAL_REPO <<'EOF'
⚠️  CANONICAL REPOSITORY - READ ONLY ⚠️
[content from section 2.3]
EOF
  done
  ```

- [ ] **Manually fix macmini stuck branch (SAFE)**
  ```bash
  ssh fengning@macmini
  # Follow section 2.5 step-by-step
  # Verify backup created before reset
  ```

- [ ] **Add canonical-sync to cron (DAILY at 3am)**
  ```bash
  # homedesktop-wsl
  crontab -e
  # Add: 0 3 * * * ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'
  
  # macmini
  ssh fengning@macmini 'crontab -e'
  # Add: 5 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'
  
  # epyc6
  ssh feng@epyc6 'crontab -e'
  # Add: 10 3 * * * ~/agent-skills/scripts/cron-wrapper.sh canonical-sync '~/agent-skills/scripts/canonical-sync-safe.sh'
  ```

- [ ] **Wait for first 3am run, verify logs**
  ```bash
  # Next morning, check logs
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'tail -50 ~/logs/canonical-sync.log'
      ssh $vm 'cat ~/logs/canonical-sync.health'
  done
  ```

---

### Phase 3: Agent Guidance (Day 3 - 1 hour)

- [ ] **Update AGENTS.md**
  ```bash
  cd ~/agent-skills
  # Add comprehensive canonical repo safety section
  git add AGENTS.md
  git commit -m "docs: add canonical repo safety rules and worktree workflow"
  git push origin master
  ```

- [ ] **Update SessionStart hooks (all repos)**
  ```bash
  for repo in prime-radiant-ai affordabot llm-common agent-skills; do
      cd ~/$repo
      # Edit .claude/hooks/sessionstart_context.sh
      # Add canonical warning, work preservation alerts, health check
      git add .claude/hooks/sessionstart_context.sh
      git commit -m "feat: add safety alerts to SessionStart hook"
      git push origin master
  done
  ```

- [ ] **Update pre-push hooks (all repos)**
  ```bash
  for repo in prime-radiant-ai affordabot llm-common agent-skills; do
      cd ~/$repo
      # Edit .githooks/pre-push or hooks/pre-push
      # Add canonical repo block with worktree guidance
      git add .githooks/pre-push
      git commit -m "feat: block pushes from canonical repos, guide to worktrees"
      git push origin master
  done
  ```

- [ ] **Pull updates on all VMs**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      for repo in agent-skills prime-radiant-ai affordabot llm-common; do
          ssh $vm "cd ~/$repo 2>/dev/null && git pull origin master || true"
      done
  done
  ```

- [ ] **Test SessionStart hook**
  ```bash
  # Start new Claude session in each repo
  # Verify all alerts and warnings appear
  ```

---

### Phase 4: Monitoring (Day 3 - 30 min)

- [ ] **Create health-dashboard.sh**
  ```bash
  cd ~/agent-skills/scripts
  # Create health-dashboard.sh
  chmod +x health-dashboard.sh
  git add health-dashboard.sh
  git commit -m "feat: add multi-VM health dashboard"
  git push origin master
  ```

- [ ] **Test health dashboard**
  ```bash
  ~/agent-skills/scripts/health-dashboard.sh
  # Should show status of all VMs
  ```

- [ ] **Add to daily routine**
  ```bash
  # Add alias to .bashrc/.zshrc
  echo "alias health='~/agent-skills/scripts/health-dashboard.sh'" >> ~/.bashrc
  ```

---

### Phase 5: Verification (Day 4 - 2 hours)

- [ ] **Run health dashboard**
  ```bash
  ~/agent-skills/scripts/health-dashboard.sh
  # All should be green
  ```

- [ ] **Check all cron health files**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'for h in ~/logs/*.health; do
          echo "$(basename $h): $(tail -1 $h)"
      done'
  done
  ```

- [ ] **Verify no alerts**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'ls ~/logs/*.ALERT 2>/dev/null || echo "No alerts ✅"'
  done
  ```

- [ ] **Verify all canonical repos on master**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
          [[ -d ~/$repo ]] && echo "$repo: $(cd ~/$repo && git branch --show-current)"
      done'
  done
  # All should show "master"
  ```

- [ ] **Verify all canonical repos current**
  ```bash
  for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
      echo "=== $vm ==="
      ssh $vm 'for repo in agent-skills prime-radiant-ai affordabot llm-common; do
          [[ -d ~/$repo ]] && cd ~/$repo && \
          behind=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "?") && \
          echo "$repo: behind by $behind"
      done'
  done
  # All should show "behind by 0"
  ```

- [ ] **Test agent workflow end-to-end**
  ```bash
  # 1. Start Claude session
  # 2. Verify SessionStart shows health status
  # 3. Try to commit in canonical repo
  # 4. Verify pre-push hook blocks with helpful message
  # 5. Create worktree
  # 6. Work in worktree
  # 7. Push from worktree (should succeed)
  ```

- [ ] **Simulate work preservation**
  ```bash
  # In a test repo:
  cd ~/prime-radiant-ai
  echo "test" >> test.txt
  git add test.txt
  
  # Run canonical-sync manually
  ~/agent-skills/scripts/canonical-sync-safe.sh
  
  # Verify:
  # 1. Work was stashed
  # 2. Alert file created
  # 3. Can restore from stash
  cat ~/logs/prime-radiant-ai.WORK_PRESERVED
  git stash list
  git stash pop
  ```

---

## Part 6: Ongoing Monitoring (Daily)

### Daily Health Check (5 minutes)

```bash
# Run health dashboard
~/agent-skills/scripts/health-dashboard.sh

# Check for any alerts
ls -la ~/logs/*.ALERT

# Check for work preservation alerts
ls -la ~/logs/*.WORK_PRESERVED
ls -la ~/logs/*.BRANCH_PRESERVED
```

### Weekly Deep Check (15 minutes)

```bash
# Check cron logs for patterns
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'tail -100 ~/logs/canonical-sync.log | grep -E "FAILED|backed up|SKIPPED"'
done

# Check for recurring failures
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'grep FAILED ~/logs/*.health 2>/dev/null | wc -l'
done

# Check git reflog size (work preservation history)
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    echo "=== $vm ==="
    ssh $vm 'for repo in prime-radiant-ai agent-skills; do
        [[ -d ~/$repo ]] && echo "$repo: $(cd ~/$repo && git reflog | wc -l) reflog entries"
    done'
done
```

---

## Part 7: Rollback Procedures

### If canonical-sync causes issues

```bash
# 1. Disable canonical-sync cron on all VMs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm 'crontab -l | grep -v canonical-sync | crontab -'
done

# 2. Restore from crontab backup
ssh fengning@macmini 'crontab ~/crontab.backup.YYYYMMDD-HHMMSS'

# 3. Restore any lost work from reflog
cd ~/prime-radiant-ai
git reflog
git cherry-pick <commit-hash>
```

### If cron-wrapper causes issues

```bash
# Remove wrapper from all cron jobs
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "feng@epyc6"; do
    ssh $vm 'crontab -l > /tmp/crontab.tmp
    sed "s|cron-wrapper.sh [^ ]* ||g" /tmp/crontab.tmp | crontab -'
done
```

### If agents confused by new workflow

```bash
# Temporarily disable pre-push hook
cd ~/prime-radiant-ai
mv .githooks/pre-push .githooks/pre-push.disabled

# Or soften it (change exit 1 to exit 0)
```

---

## Success Metrics

### Week 1 (Safety Verification)

- [ ] **Zero code loss incidents** - No agent work lost
- [ ] **Zero silent failures** - All cron failures visible in alerts
- [ ] **100% health file coverage** - All cron jobs writing health status
- [ ] **All canonical repos on master** - No stuck branches

### Week 2 (Operational Health)

- [ ] **Zero cron failures** - All jobs running successfully
- [ ] **Zero work preservation incidents** - No uncommitted work in canonical repos
- [ ] **Agents using worktrees** - >80% of development in worktrees
- [ ] **All VMs synchronized** - Master branches current across all VMs

### Month 1 (Autonomous Operation)

- [ ] **Zero manual interventions** - System runs autonomously
- [ ] **Zero merge conflicts** - Agents always working on fresh master
- [ ] **Agents self-correcting** - Following workflow without prompting
- [ ] **Health dashboard green** - All metrics healthy

---

## Appendix: Safety Checklist

Before deploying ANY change:

- [ ] **Backup exists** - Crontab backed up with timestamp
- [ ] **Rollback tested** - Know how to undo the change
- [ ] **Logs configured** - Change writes to log file
- [ ] **Health check added** - Change reports success/failure
- [ ] **Alert on failure** - Failures create visible alerts
- [ ] **Tested manually** - Change tested before adding to cron
- [ ] **Documented** - Change documented in this plan

Before any destructive operation:

- [ ] **Work checked** - No uncommitted changes
- [ ] **Backup created** - Stash or backup branch created
- [ ] **Alert created** - Agent notified of backup location
- [ ] **Recovery tested** - Verified can restore from backup
- [ ] **Graceful failure** - If backup fails, operation skips

---

**END OF HYBRID SAFETY-FIRST IMPLEMENTATION PLAN**
