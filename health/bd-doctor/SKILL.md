---
name: bd-doctor
description: Check and fix common Beads workflow issues across all repos.
---

# bd-doctor

## Description

Check and fix common Beads workflow issues across all repos.

**Use when**:
- Beads sync fails ("JSONL is newer than database", "Push to master blocked")
- Unstaged .beads/issues.jsonl changes
- User says "fix beads", "beads sync failing", "check beads", "beads health"
- Before important operations (commits, syncs, PRs)

**Problem solved**: Eliminates "Manual Beads operations" pattern (7/69 toil commits, 10% of analyzed toil).

## Auto-Activation

This skill activates when:
- bd sync fails with common errors
- User mentions Beads issues ("beads", "bd sync", "JSONL")
- Unstaged .beads/issues.jsonl detected
- Branch/issue mismatch detected

## Implementation

The skill performs comprehensive Beads health checks and auto-fixes common issues.

### Check Script

```bash
#!/bin/bash
# ~/.agent/skills/bd-doctor/check.sh

set -e

echo "🔍 Beads Doctor - Health Check"

ISSUES_FOUND=0

# Check 1: JSONL timestamp skew (most common issue)
echo ""
echo "📋 Checking Beads JSONL sync..."
if bd sync --dry-run 2>&1 | grep -q "JSONL is newer"; then
  echo "⚠️  JSONL timestamp skew detected"
  echo "   Cause: Daemon auto-exported between your changes and sync"
  echo "   Fix: bd export --force (resolves timing issue)"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
elif bd sync --dry-run 2>&1 | grep -q "Pushing directly to master is blocked"; then
  echo "⚠️  Attempting to push JSONL to protected branch"
  echo "   Cause: Running bd sync on master branch"
  echo "   Fix: Use 'bd export --force' on master (no push), or switch to feature branch"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
  echo "✅ Beads JSONL in sync with database"
fi

# Check 2: Unstaged JSONL changes
echo ""
echo "📋 Checking for unstaged Beads changes..."
if git status --porcelain 2>/dev/null | grep -q ".beads/issues.jsonl"; then
  echo "⚠️  .beads/issues.jsonl has unstaged changes"
  echo "   Stage with: git add .beads/issues.jsonl"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
  echo "✅ No unstaged Beads changes"
fi

# Check 3: Branch/Issue mismatch
echo ""
echo "📋 Checking branch/issue alignment..."
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
if [[ $BRANCH =~ ^feature-bd-([a-z0-9]+) ]]; then
  ISSUE_ID="${BASH_REMATCH[1]}"
  if bd show "bd-$ISSUE_ID" &>/dev/null; then
    echo "✅ Branch feature-bd-$ISSUE_ID matches Beads issue bd-$ISSUE_ID"
  else
    echo "⚠️  On branch feature-bd-$ISSUE_ID but issue bd-$ISSUE_ID not found"
    echo "   Possible causes:"
    echo "   - Issue was closed/deleted"
    echo "   - Working on wrong branch"
    echo "   - Need to create issue: bd create \"Task name\" --type task"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
elif [[ $BRANCH == "master" ]] || [[ $BRANCH == "main" ]]; then
  echo "ℹ️  On $BRANCH branch (no Beads issue expected)"
else
  echo "ℹ️  On non-Beads branch: $BRANCH (custom branch, no issue tracking)"
fi

# Check 4: Feature-Key trailer in recent commits
echo ""
echo "📋 Checking Feature-Key trailers..."
RECENT_COMMIT=$(git log -1 --format=%B 2>/dev/null || echo "")
if [[ -n "$RECENT_COMMIT" ]] && ! echo "$RECENT_COMMIT" | grep -q "Feature-Key:"; then
  # Only warn if on feature branch
  if [[ $BRANCH =~ ^feature- ]]; then
    echo "⚠️  Recent commit missing Feature-Key trailer"
    echo "   Use sync-feature-branch skill for proper commit format"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  else
    echo "✅ Not on feature branch (Feature-Key not required)"
  fi
else
  echo "✅ Feature-Key trailer present or not required"
fi

# Check 5: Large JSONL files (import hang risk)
echo ""
echo "📋 Checking for large JSONL files..."
if [[ -f .beads/issues.jsonl ]]; then
  LINE_COUNT=$(wc -l < .beads/issues.jsonl 2>/dev/null || echo 0)
  if [[ $LINE_COUNT -gt 500 ]]; then
    echo "⚠️  Large JSONL file detected: $LINE_COUNT issues"
    echo "   Note: This issue was RESOLVED via PR #147 (DX tooling)"
    echo "   Solutions: Use dx-hydrate.sh OR bd-import-safe wrapper"
    echo "   Commands:"
    echo "     dx-hydrate.sh              # DX automation (recommended)"
    echo "     bd-import-safe issues.jsonl # Manual chunked import"
    echo "   See: ~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md"
    # Note: Not incrementing ISSUES_FOUND as this is informational
  elif [[ $LINE_COUNT -gt 0 ]]; then
    echo "✅ JSONL file size normal ($LINE_COUNT issues)"
  else
    echo "ℹ️  No JSONL file or empty"
  fi
else
  echo "ℹ️  No .beads/issues.jsonl found"
fi

# Check 6: DX tooling availability
echo ""
echo "📋 Checking DX tooling..."
if command -v bd-sync-safe >/dev/null 2>&1; then
  echo "✅ DX tools available (bd-sync-safe, bd-import-safe)"
elif [[ -f ~/bd/bd-sync-safe.sh ]]; then
  echo "⚠️  DX scripts found but not symlinked to ~/bin/"
  echo "   Run: dx-ensure-bins.sh to fix"
else
  echo "ℹ️  DX tooling not found (optional)"
fi

echo ""
echo "═══════════════════════════════════════"
if [[ $ISSUES_FOUND -eq 0 ]]; then
  echo "✅ All Beads checks passed! Healthy workflow."
  exit 0
else
  echo "❌ Found $ISSUES_FOUND Beads issue(s)"
  echo ""
  echo "Run: ~/.agent/skills/bd-doctor/fix.sh    # to auto-fix"
  exit 1
fi
```

### Fix Script

```bash
#!/bin/bash
# ~/.agent/skills/bd-doctor/fix.sh

set -e

echo "🔧 Beads Doctor - Fixing issues..."

FIXED=0

# Fix 1: JSONL timestamp skew
echo ""
echo "📋 Fixing JSONL sync..."
if bd sync --dry-run 2>&1 | grep -q "JSONL is newer"; then
  echo "Running: bd export --force"
  bd export --force
  echo "✅ JSONL exported (timestamp skew resolved)"
  FIXED=$((FIXED + 1))
elif bd sync --dry-run 2>&1 | grep -q "Pushing directly to master is blocked"; then
  echo "Running: bd export --force (no push on master)"
  bd export --force
  echo "✅ JSONL exported without pushing to master"
  FIXED=$((FIXED + 1))
else
  echo "✅ JSONL already in sync"
fi

# Fix 2: Stage unstaged JSONL
echo ""
echo "📋 Staging Beads changes..."
if git status --porcelain 2>/dev/null | grep -q ".beads/issues.jsonl"; then
  echo "Running: git add .beads/issues.jsonl"
  git add .beads/issues.jsonl
  echo "✅ Beads JSONL staged"
  FIXED=$((FIXED + 1))
else
  echo "✅ No unstaged Beads changes"
fi

# Fix 3: Branch/Issue mismatch - can't auto-fix, only warn
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
if [[ $BRANCH =~ ^feature-bd-([a-z0-9]+) ]]; then
  ISSUE_ID="${BASH_REMATCH[1]}"
  if ! bd show "bd-$ISSUE_ID" &>/dev/null; then
    echo ""
    echo "⚠️  Cannot auto-fix: Branch feature-bd-$ISSUE_ID but issue bd-$ISSUE_ID not found"
    echo "   Manual action required:"
    echo "   - Create issue: bd create \"Task name\" --type task"
    echo "   - OR switch branch: git checkout feature-bd-{correct-id}"
  fi
fi

echo ""
echo "═══════════════════════════════════════"
if [[ $FIXED -eq 0 ]]; then
  echo "ℹ️  Nothing to fix (already healthy)"
else
  echo "✅ Fixed $FIXED Beads issue(s)"
  echo ""
  echo "Next: Verify with 'bd sync' or continue workflow"
fi
```

## Usage Examples

### Check Beads health
```bash
bd-doctor check
```

### Auto-fix all Beads issues
```bash
bd-doctor fix
```

### Agent workflow integration

**Before bd sync**:
```bash
bd-doctor check || bd-doctor fix
bd sync
```

**Before committing**:
```bash
bd-doctor check    # Verify JSONL staged, branch/issue aligned
git commit ...
```

**When bd sync fails**:
```bash
# Error: "JSONL is newer than database"
bd-doctor fix      # Auto-resolves with bd export --force
bd sync            # Should now succeed
```

## Common Issues & Fixes

### Issue 1: "JSONL is newer than database"
**Cause**: Beads daemon auto-exported between your changes and bd sync (timestamp skew)
**Fix**: `bd export --force` then `bd sync`
**Prevention**: bd-doctor auto-detects and fixes this

### Issue 2: "Pushing directly to master is blocked"
**Cause**: Running `bd sync` on master branch (pre-push hook blocks)
**Fix**: Use `bd export --force` on master (exports without pushing), or switch to feature branch
**Prevention**: bd-doctor detects and guides to correct fix

### Issue 3: Unstaged .beads/issues.jsonl
**Cause**: Beads operations modified JSONL but not staged for commit
**Fix**: `git add .beads/issues.jsonl`
**Prevention**: bd-doctor auto-stages when detected

### Issue 4: Branch/Issue mismatch
**Cause**: On feature-bd-xyz but issue bd-xyz doesn't exist
**Fix**: Create issue or switch to correct branch
**Prevention**: bd-doctor warns early

### Issue 5: Large import hangs ("Quiet Zone") ⚠️ **RESOLVED**
**Status**: Resolved via [stars-end/agent-skills#147](https://github.com/stars-end/agent-skills/pull/147) (2025-02-09)
**Cause**: Importing 1000+ issues in single transaction causes SQLite timeout during dependency graph construction
**Symptoms**: `bd import -i issues.jsonl --no-daemon` hangs for 5+ minutes, parses JSONL successfully but never completes
**Solutions**:
  - **Automation**: Use DX tooling (dx-hydrate.sh, dx-check.sh) - handles automatically
  - **Manual**: Use chunked import wrapper: `bd-import-safe issues.jsonl` (symlinked to ~/bin/)
  - **Upstream**: Tracking via [steveyeggie/beads#1629](https://github.com/steveyeggie/beads/issues/1629)
**See also**: `~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md`

## Integration with Other Skills

### sync-feature-branch Enhancement
Modify sync-feature-branch to call bd-doctor first:
```markdown
1. Run bd-doctor check
2. If fails, run bd-doctor fix
3. Verify all checks pass
4. Proceed with commit
```

### create-pull-request Enhancement
Call bd-doctor before creating PR:
```markdown
1. Run bd-doctor check (ensure JSONL in sync)
2. Close Beads issue if work complete
3. Run bd export --force (atomic with code)
4. Create PR
```

## Cross-Repo Deployment

This skill deploys to `~/.agent/skills/` and works across:
- ✅ All repos (prime-radiant-ai, affordabot, any Beads-enabled repo)
- ✅ All AI agents (Claude Code, Codex CLI, Antigravity)
- ✅ All VMs (shared via Universal Skills MCP)

## Success Metrics

**Baseline**: 7 commits (10% of toil) wasted on Beads sync issues
**Target**: <1 commit per 60-commit cycle
**Impact**: ~30 minutes/month saved, reduced frustration

## Notes

**Design Philosophy**:
- Auto-fix where possible (JSONL sync, staging)
- Clear guidance where manual action needed (branch/issue mismatch)
- Non-blocking checks (doesn't prevent work)
- Agent-friendly (clear messages, actionable commands)

**Why not auto-amend commits?**
- Multi-agent context: auto-amend causes history conflicts
- Explicit > Implicit: agents should explicitly sync via skills
- Skills provide control: invoke when needed, not on every commit

**Complementary with**:
- sync-feature-branch skill (commits with proper Beads metadata)
- create-pull-request skill (atomic JSONL merge pattern)
