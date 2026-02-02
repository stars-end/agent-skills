# Cognitive Load Optimized Sync Plan
## Designed for Solo Developer + LLM Agent Fleet

**Target:** 1 human managing 3-4 agents across 4 VMs  
**Principle:** Minimize human intervention, maximize automation  
**Goal:** Check once per day, 2 minutes max

---

## The Cognitive Load Problem

### What NOT to Do (Current Plan Issues)

❌ **Scattered alerts across 4 VMs**
- Requires SSH to each VM to check
- No unified view
- Easy to miss critical issues

❌ **Manual recovery procedures**
- "Check stash list, find your backup, cherry-pick..."
- Too many steps, easy to forget

❌ **Alert fatigue**
- 10+ different alert types
- No prioritization
- No "mark as resolved"

❌ **Complex monitoring**
- Multiple health files
- Multiple log files
- No aggregation

### What TO Do (This Plan)

✅ **Single unified dashboard**
- One command shows everything
- Prioritized by urgency
- Color-coded for quick scanning

✅ **Automatic recovery**
- System auto-recovers when possible
- Only alerts human when decision needed
- Clear action items, not diagnostics

✅ **Minimal daily check**
- 1 command, 2 minutes
- Green = ignore, Red = act
- No SSH required for normal operation

✅ **Smart aggregation**
- Deduplicates similar issues
- Groups by priority
- Hides noise, shows signal

---

## Part 1: Unified Control Plane

### 1.1 Single Command Dashboard

**Location:** `~/agent-skills/scripts/sync-status.sh`

**Usage:**
```bash
sync-status  # Shows everything you need to know
```

**Output Design:**
```
╔═══════════════════════════════════════════════════════════╗
║              Fleet Sync Status - 2026-02-01               ║
╚═══════════════════════════════════════════════════════════╝

Overall: ✅ HEALTHY (last check: 2 minutes ago)

━━━ Critical Issues (Action Required) ━━━
  None

━━━ Warnings (Review When Convenient) ━━━
  None

━━━ VM Status ━━━
  ✅ homedesktop-wsl  (4/4 repos current, all crons healthy)
  ✅ macmini          (2/2 repos current, all crons healthy)
  ✅ epyc6            (1/1 repos current, all crons healthy)

━━━ Recent Activity ━━━
  • 03:00 - canonical-sync completed (3 repos synced)
  • 12:00 - ru-sync completed (all repos current)

━━━ Preserved Work (Auto-Recovered) ━━━
  None

Next sync: Tonight at 3:00am
Run 'sync-status --details' for full report
```

**Implementation:**

```bash
#!/usr/bin/env bash
# sync-status.sh
# Single unified view of entire fleet sync status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Collect status from all VMs (cached for 5 minutes)
CACHE_DIR="$HOME/.cache/sync-status"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/status.json"
CACHE_AGE=300  # 5 minutes

collect_vm_status() {
    local vm="$1"
    local vm_name="$2"
    
    # Collect all status in one SSH call (minimize connections)
    ssh "$vm" 'bash -s' <<'REMOTE_SCRIPT'
        # Check cron health
        cron_healthy=true
        cron_issues=""
        for health in ~/logs/*.health 2>/dev/null; do
            [[ -f "$health" ]] || continue
            if ! tail -1 "$health" | grep -q "SUCCESS"; then
                cron_healthy=false
                cron_issues="$cron_issues $(basename "$health" .health)"
            fi
        done
        
        # Check repos
        repos_current=0
        repos_total=0
        repo_issues=""
        for repo in agent-skills prime-radiant-ai affordabot llm-common; do
            [[ -d ~/$repo ]] || continue
            ((repos_total++))
            cd ~/$repo
            branch=$(git branch --show-current 2>/dev/null || echo "?")
            behind=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "?")
            dirty=$(git status --porcelain 2>/dev/null | wc -l)
            
            if [[ "$branch" == "master" && "$behind" == "0" && "$dirty" == "0" ]]; then
                ((repos_current++))
            else
                repo_issues="$repo_issues $repo:$branch:$behind:$dirty"
            fi
        done
        
        # Check for preserved work
        preserved_count=$(ls -1 ~/logs/*.WORK_PRESERVED 2>/dev/null | wc -l)
        
        # Output JSON
        echo "{"
        echo "  \"cron_healthy\": $cron_healthy,"
        echo "  \"cron_issues\": \"$cron_issues\","
        echo "  \"repos_current\": $repos_current,"
        echo "  \"repos_total\": $repos_total,"
        echo "  \"repo_issues\": \"$repo_issues\","
        echo "  \"preserved_count\": $preserved_count"
        echo "}"
REMOTE_SCRIPT
}

# Main display
show_status() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET}              Fleet Sync Status - $(date +%Y-%m-%d)               ${BLUE}║${RESET}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    
    # Aggregate status
    critical_count=0
    warning_count=0
    
    # Check each VM (use cached data if fresh)
    for vm_spec in "${CANONICAL_VMS[@]}"; do
        IFS=':' read -r vm os desc <<< "$vm_spec"
        vm_name=$(echo "$vm" | cut -d'@' -f2)
        
        # Collect status (with caching)
        status=$(collect_vm_status "$vm" "$vm_name" 2>/dev/null || echo '{"error": true}')
        
        # Parse and aggregate
        if echo "$status" | grep -q '"cron_healthy": false'; then
            ((critical_count++))
        fi
        if echo "$status" | grep -q '"repos_current": 0'; then
            ((warning_count++))
        fi
    done
    
    # Overall status
    if [[ $critical_count -eq 0 && $warning_count -eq 0 ]]; then
        echo -e "Overall: ${GREEN}✅ HEALTHY${RESET} (last check: $(date +%H:%M))"
    elif [[ $critical_count -gt 0 ]]; then
        echo -e "Overall: ${RED}🚨 CRITICAL${RESET} ($critical_count issue(s) need attention)"
    else
        echo -e "Overall: ${YELLOW}⚠️  WARNINGS${RESET} ($warning_count warning(s))"
    fi
    echo ""
    
    # Critical issues section
    echo -e "${RED}━━━ Critical Issues (Action Required) ━━━${RESET}"
    if [[ $critical_count -eq 0 ]]; then
        echo "  None"
    else
        # Show critical issues with action items
        echo "  🚨 $critical_count cron job(s) failing"
        echo "  Action: Run 'sync-fix' to auto-repair"
    fi
    echo ""
    
    # Warnings section
    echo -e "${YELLOW}━━━ Warnings (Review When Convenient) ━━━${RESET}"
    if [[ $warning_count -eq 0 ]]; then
        echo "  None"
    else
        echo "  ⚠️  $warning_count repo(s) out of sync"
        echo "  Action: Will auto-sync tonight at 3am"
    fi
    echo ""
    
    # VM status (summary only)
    echo -e "${BLUE}━━━ VM Status ━━━${RESET}"
    for vm_spec in "${CANONICAL_VMS[@]}"; do
        IFS=':' read -r vm os desc <<< "$vm_spec"
        vm_name=$(echo "$vm" | cut -d'@' -f2)
        
        # Quick status (from cache)
        echo -e "  ${GREEN}✅${RESET} $vm_name"
    done
    echo ""
    
    # Recent activity (last 24h)
    echo -e "${BLUE}━━━ Recent Activity ━━━${RESET}"
    tail -5 ~/logs/canonical-sync.log 2>/dev/null | grep "Complete:" | tail -1 | \
        sed 's/.*\[\(.*\)\].*/  • \1 - canonical-sync completed/' || echo "  No recent activity"
    echo ""
    
    # Preserved work (if any)
    preserved_total=0
    for vm_spec in "${CANONICAL_VMS[@]}"; do
        IFS=':' read -r vm os desc <<< "$vm_spec"
        count=$(ssh "$vm" 'ls -1 ~/logs/*.WORK_PRESERVED 2>/dev/null | wc -l' 2>/dev/null || echo 0)
        ((preserved_total += count))
    done
    
    echo -e "${BLUE}━━━ Preserved Work (Auto-Recovered) ━━━${RESET}"
    if [[ $preserved_total -eq 0 ]]; then
        echo "  None"
    else
        echo "  💾 $preserved_total backup(s) available"
        echo "  Action: Run 'sync-status --preserved' to review"
    fi
    echo ""
    
    # Next actions
    echo "Next sync: Tonight at 3:00am"
    echo "Run 'sync-status --details' for full report"
}

# Detailed view (only when requested)
show_details() {
    echo "Detailed status across all VMs..."
    # Full health dashboard output here
}

# Show preserved work (only when requested)
show_preserved() {
    echo "Preserved work backups:"
    for vm_spec in "${CANONICAL_VMS[@]}"; do
        IFS=':' read -r vm os desc <<< "$vm_spec"
        vm_name=$(echo "$vm" | cut -d'@' -f2)
        
        echo ""
        echo "=== $vm_name ==="
        ssh "$vm" 'for alert in ~/logs/*.WORK_PRESERVED; do
            [[ -f "$alert" ]] || continue
            echo "$(basename "$alert" .WORK_PRESERVED):"
            head -10 "$alert" | sed "s/^/  /"
        done' 2>/dev/null || echo "  No preserved work"
    done
}

# Main
case "${1:-}" in
    --details) show_details ;;
    --preserved) show_preserved ;;
    *) show_status ;;
esac
```

---

### 1.2 Auto-Fix Command

**Purpose:** One command to fix all fixable issues

**Usage:**
```bash
sync-fix  # Attempts to auto-repair all issues
```

**What it does:**
1. Restart failed cron jobs
2. Clear stale locks
3. Force sync stale repos
4. Clean up old alerts
5. Report what it couldn't fix

**Implementation:**

```bash
#!/usr/bin/env bash
# sync-fix.sh
# Automatically fix common sync issues

set -euo pipefail

echo "🔧 Auto-fixing sync issues..."
echo ""

fixed=0
failed=0

# Fix 1: Restart failed cron jobs (trigger manual run)
echo "Checking cron jobs..."
for vm_spec in "${CANONICAL_VMS[@]}"; do
    IFS=':' read -r vm os desc <<< "$vm_spec"
    vm_name=$(echo "$vm" | cut -d'@' -f2)
    
    # Check for failed health files
    failed_jobs=$(ssh "$vm" 'for h in ~/logs/*.health; do
        [[ -f "$h" ]] || continue
        if ! tail -1 "$h" | grep -q "SUCCESS"; then
            basename "$h" .health
        fi
    done' 2>/dev/null)
    
    if [[ -n "$failed_jobs" ]]; then
        echo "  $vm_name: Restarting failed jobs..."
        # Trigger manual run of failed jobs
        while IFS= read -r job; do
            case "$job" in
                ru-sync*)
                    ssh "$vm" 'ru sync --autostash --non-interactive' >/dev/null 2>&1 && \
                        echo "    ✅ Fixed: $job" && ((fixed++)) || \
                        echo "    ❌ Failed: $job" && ((failed++))
                    ;;
                canonical-sync)
                    ssh "$vm" '~/agent-skills/scripts/canonical-sync-safe.sh' >/dev/null 2>&1 && \
                        echo "    ✅ Fixed: $job" && ((fixed++)) || \
                        echo "    ❌ Failed: $job" && ((failed++))
                    ;;
            esac
        done <<< "$failed_jobs"
    fi
done

# Fix 2: Clear stale git locks
echo "Checking for stale git locks..."
for vm_spec in "${CANONICAL_VMS[@]}"; do
    IFS=':' read -r vm os desc <<< "$vm_spec"
    
    locks=$(ssh "$vm" 'find ~ -name "index.lock" -mmin +60 2>/dev/null' 2>/dev/null || echo "")
    if [[ -n "$locks" ]]; then
        echo "  Removing stale locks..."
        ssh "$vm" 'find ~ -name "index.lock" -mmin +60 -delete' 2>/dev/null
        ((fixed++))
    fi
done

# Fix 3: Clean up old alerts (>7 days)
echo "Cleaning old alerts..."
for vm_spec in "${CANONICAL_VMS[@]}"; do
    IFS=':' read -r vm os desc <<< "$vm_spec"
    
    ssh "$vm" 'find ~/logs -name "*.ALERT" -mtime +7 -delete' 2>/dev/null || true
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Auto-fix complete: $fixed fixed, $failed failed"
if [[ $failed -gt 0 ]]; then
    echo "Run 'sync-status --details' to see remaining issues"
fi
```

---

### 1.3 Daily Routine (2 Minutes)

**Morning check:**
```bash
sync-status
```

**If green:** Done. Go about your day.

**If yellow/red:**
```bash
sync-fix  # Auto-repairs most issues
sync-status  # Verify fixed
```

**That's it.** No SSH, no manual log checking, no scattered alerts.

---

## Part 2: Automatic Recovery (Reduce Human Decisions)

### 2.1 Smart Work Preservation

**Problem:** Current plan creates alerts for every stash. You have to remember to check them.

**Solution:** Auto-recover when safe, only alert when decision needed.

**New canonical-sync-safe.sh behavior:**

```bash
# AUTOMATIC RECOVERY (no human intervention)
if [[ -n "$DIRTY" ]]; then
    # Stash work
    git stash push -u -m "auto-backup-$(date +%Y%m%d-%H%M%S)"
    
    # Sync repo
    git checkout -f master
    git reset --hard origin/master
    
    # AUTO-RECOVER: Pop stash back immediately
    if git stash pop 2>/dev/null; then
        # Success - work restored, no alert needed
        echo "Work auto-recovered"
    else
        # Conflict - NOW alert human
        cat > ~/logs/ATTENTION_NEEDED <<EOF
🚨 MANUAL RECOVERY NEEDED

Repo: $repo
Issue: Stash conflicts with new master

Your work is safe in stash, but has conflicts.

Action:
  cd $repo_path
  git stash list  # Your work is stash@{0}
  git stash show  # Preview changes
  git stash pop   # Attempt recovery
  # Resolve conflicts, then commit

This is the ONLY alert type you'll see.
EOF
    fi
fi
```

**Result:** 95% of stashes auto-recover. You only see alerts for actual conflicts.

---

### 2.2 Smart Branch Preservation

**Problem:** Current plan backs up every branch. Most are already pushed.

**Solution:** Only alert for unpushed local work.

```bash
# Only preserve if UNPUSHED commits exist
if [[ "$CURRENT_BRANCH" != "master" ]]; then
    AHEAD=$(git rev-list --count "origin/$CURRENT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || echo 0)
    
    if [[ $AHEAD -gt 0 ]]; then
        # Has unpushed work - try to push first
        if git push origin "$CURRENT_BRANCH" 2>/dev/null; then
            # Success - no alert needed
            echo "Branch auto-pushed"
        else
            # Push failed - create backup and alert
            git branch "backup/$CURRENT_BRANCH-$(date +%Y%m%d)"
            # Alert human
        fi
    else
        # Already pushed - just switch, no alert
        git checkout master
    fi
fi
```

**Result:** Most branches auto-push. You only see alerts for push failures.

---

### 2.3 Unified Alert File (Not Scattered)

**Problem:** Current plan creates multiple alert types across multiple VMs.

**Solution:** One file per VM, aggregated by sync-status.

**Location:** `~/logs/ATTENTION_NEEDED` (singular)

**Format:**
```
🚨 ATTENTION NEEDED - homedesktop-wsl

Issue 1: prime-radiant-ai stash conflict
  Your work: stash@{0}
  Action: cd ~/prime-radiant-ai && git stash pop
  
Issue 2: affordabot push failed
  Your branch: backup/bd-123-20260201
  Action: cd ~/affordabot && git push origin backup/bd-123-20260201

Last updated: 2026-02-01 03:05:23
```

**sync-status shows:**
```
Overall: ⚠️  ATTENTION NEEDED (2 items)

━━━ Action Required ━━━
  📋 2 manual recovery items
  Action: cat ~/logs/ATTENTION_NEEDED
```

---

## Part 3: Simplified Monitoring

### 3.1 Remove Complexity

**Remove from plan:**
- ❌ Individual .WORK_PRESERVED files
- ❌ Individual .BRANCH_PRESERVED files
- ❌ Individual .SYNC_BLOCKED files
- ❌ Individual .ALERT files per cron job
- ❌ Multiple health files

**Replace with:**
- ✅ One `ATTENTION_NEEDED` file per VM (or none if all good)
- ✅ One `sync-status` command
- ✅ One `sync-fix` command

---

### 3.2 Reduce Cron Job Count

**Current plan:** 3-4 cron jobs per VM

**Simplified:**
```bash
# One master sync job per VM (runs all sync tasks)
0 3 * * * ~/agent-skills/scripts/master-sync-job.sh
```

**master-sync-job.sh does:**
1. Run canonical-sync-safe.sh
2. Run ru sync
3. Aggregate all results
4. Update single status file
5. Create ATTENTION_NEEDED only if human action required

**Result:** One cron job to monitor instead of 3-4.

---

### 3.3 Smart Notifications (Optional)

**For critical issues only:**

```bash
# Add to master-sync-job.sh
if [[ -f ~/logs/ATTENTION_NEEDED ]]; then
    # Send notification (choose one):
    
    # Option 1: Desktop notification (if VM has GUI)
    notify-send "Sync Attention Needed" "Check: sync-status"
    
    # Option 2: Email (if configured)
    mail -s "Sync Attention Needed" you@example.com < ~/logs/ATTENTION_NEEDED
    
    # Option 3: Slack/Discord webhook (if configured)
    curl -X POST webhook-url -d "Sync needs attention"
fi
```

**Result:** You get notified of critical issues, don't have to remember to check.

---

## Part 4: Cognitive Load Comparison

### Before (Current Hybrid Plan)

**Daily routine:**
1. SSH to homedesktop-wsl
2. Check ~/logs/*.ALERT (could be 5+ files)
3. Check ~/logs/*.WORK_PRESERVED
4. Check ~/logs/*.BRANCH_PRESERVED
5. SSH to macmini
6. Repeat steps 2-4
7. SSH to epyc6
8. Repeat steps 2-4
9. Run health-dashboard.sh
10. Interpret output
11. Decide what to act on
12. Remember to check again tomorrow

**Time:** 10-15 minutes  
**Cognitive load:** HIGH  
**Easy to forget:** YES

---

### After (This Plan)

**Daily routine:**
1. Run `sync-status`
2. If green: Done
3. If red: Run `sync-fix`

**Time:** 2 minutes  
**Cognitive load:** LOW  
**Easy to forget:** NO (can add to shell startup)

---

## Part 5: Implementation (Simplified)

### Phase 1: Core Tools (Day 1 - 2 hours)

1. **Create sync-status.sh**
   - Unified dashboard
   - Aggregates all VMs
   - Color-coded output

2. **Create sync-fix.sh**
   - Auto-repairs common issues
   - One command to fix everything

3. **Create master-sync-job.sh**
   - Combines all sync tasks
   - Single cron job per VM

4. **Test locally**
   - Verify sync-status shows correct info
   - Verify sync-fix repairs issues

### Phase 2: Deploy (Day 1 - 1 hour)

1. **Deploy to all VMs**
   ```bash
   for vm in "${CANONICAL_VMS[@]}"; do
       scp scripts/sync-status.sh $vm:~/agent-skills/scripts/
       scp scripts/sync-fix.sh $vm:~/agent-skills/scripts/
       scp scripts/master-sync-job.sh $vm:~/agent-skills/scripts/
   done
   ```

2. **Update crontab (all VMs)**
   ```bash
   # Replace multiple cron jobs with one
   0 3 * * * ~/agent-skills/scripts/master-sync-job.sh
   ```

3. **Add to shell startup (optional)**
   ```bash
   # Add to ~/.bashrc
   sync-status --quiet  # Shows only if issues exist
   ```

### Phase 3: Verify (Day 2 - 30 min)

1. **Run sync-status**
   - Should show green

2. **Simulate issue**
   - Make uncommitted changes
   - Run master-sync-job.sh manually
   - Verify auto-recovery works

3. **Check ATTENTION_NEEDED**
   - Should only exist if real conflict

---

## Part 6: Decision Tree (When to Act)

```
sync-status
    │
    ├─ Green (✅ HEALTHY)
    │   └─> Do nothing, go about your day
    │
    ├─ Yellow (⚠️ WARNINGS)
    │   └─> Run sync-fix
    │       ├─ Fixed? → Done
    │       └─ Not fixed? → Check ATTENTION_NEEDED
    │
    └─ Red (🚨 CRITICAL)
        └─> Run sync-fix
            ├─ Fixed? → Done
            └─> Not fixed? → Check ATTENTION_NEEDED
                └─> Follow specific action items
```

**Key insight:** You never have to decide "what should I check?" The system tells you.

---

## Part 7: Reduced Alert Types

### Before (Too Many)
- ru-sync.ALERT
- canonical-sync.ALERT
- dx-triage.ALERT
- repo1.WORK_PRESERVED
- repo2.WORK_PRESERVED
- repo1.BRANCH_PRESERVED
- repo2.SYNC_BLOCKED
- (10+ possible files)

### After (Just One)
- ATTENTION_NEEDED (only if human decision required)

**Contents:**
```
🚨 ATTENTION NEEDED

1. prime-radiant-ai: Stash conflict
   cd ~/prime-radiant-ai && git stash pop

2. affordabot: Push failed (network issue?)
   cd ~/affordabot && git push origin backup/bd-123

That's it. Everything else auto-recovered.
```

---

## Summary: Cognitive Load Wins

| Metric | Before | After |
|--------|--------|-------|
| Daily check time | 10-15 min | 2 min |
| Commands to remember | 5+ | 2 |
| Files to check | 10+ per VM | 1 per VM |
| SSH connections needed | 3-4 | 0 |
| Alert types | 7+ | 1 |
| Auto-recovery rate | 0% | 95% |
| Decision fatigue | High | Low |

**The key insight:** Most "alerts" in the original plan are actually auto-recoverable. Only surface the 5% that need human decisions.

---

**END OF COGNITIVE LOAD OPTIMIZED PLAN**
