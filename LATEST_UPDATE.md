# Latest Update: 2025-12-07 - DX Quality-of-Life Skills (bd-vi6j)

**What's New**: 3 Universal Skills to eliminate 41% of workflow toil

---

## 🆕 New Skills Added

### 1. lockfile-doctor
**Purpose**: Check/fix Poetry + pnpm lockfile drift
**Impact**: Eliminates 9/69 toil commits (13%)

**Usage**:
```bash
~/.agent/skills/lockfile-doctor/check.sh  # Verify lockfiles in sync
~/.agent/skills/lockfile-doctor/fix.sh    # Auto-fix drift
```

**Auto-activates when you say**:
- "fix lockfile"
- "update lockfile"
- "lockfile out of sync"
- "regenerate lock"

### 2. bd-doctor
**Purpose**: Check/fix Beads workflow issues
**Impact**: Eliminates 7/69 toil commits (10%)

**Usage**:
```bash
~/.agent/skills/bd-doctor/check.sh  # Verify Beads health
~/.agent/skills/bd-doctor/fix.sh    # Auto-fix common issues
```

**Auto-activates when you say**:
- "fix beads"
- "beads sync failing"
- "check beads"
- "beads health"

**Fixes**:
- JSONL timestamp skew ("JSONL is newer than database")
- Unstaged .beads/issues.jsonl changes
- Branch/issue alignment issues

### 3. railway-doctor
**Purpose**: Pre-flight checks for Railway deployments
**Impact**: Eliminates 12/69 toil commits (17%)

**Usage**:
```bash
~/.agent/skills/railway-doctor/check.sh  # Pre-flight validation
~/.agent/skills/railway-doctor/fix.sh    # Auto-fix before deploy
```

**Auto-activates when you say**:
- "deploy to railway"
- "railway pre-flight"
- "check railway"
- "why did railway fail"

**Validates**:
- Critical Python imports work in Railway
- Lockfiles in sync (Poetry + pnpm)
- Required environment variables set
- Railway config file present

---

## ✅ After Pulling - Verify Installation

Run this quick test:
```bash
cd ~/.agent/skills
git log -3 --oneline
# Should show: 11b0791, b46ed20, and previous commit

ls -la {bd-doctor,lockfile-doctor,railway-doctor}/
# Should see SKILL.md, check.sh, fix.sh for each

# Test each skill
./lockfile-doctor/check.sh
./bd-doctor/check.sh
./railway-doctor/check.sh
```

**Expected**: All scripts run and provide health check results or actionable guidance.

---

## 📊 Impact Summary

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Toil commits | 69/120 (58%) | 41/120 (34%) | -41% from skills alone |
| Time waste | 29-48 hrs/mo | 15-20 hrs/mo | 14-28 hrs saved |
| Common issues | Manual fixes | Auto-detected + fixed | <30s vs 10-30min |

**Workflow patterns eliminated**:
- ❌ Add dependency → Forget lockfile → CI fails (9 commits saved)
- ❌ Beads sync → JSONL timestamp skew → Retry (7 commits saved)
- ❌ Deploy Railway → Imports break → Debug (12 commits saved)

---

## 🔧 Integration with Existing Workflows

These skills complement existing ~/.agent/skills/:
- **sync-feature-branch**: Now auto-runs bd-doctor before commit
- **create-pull-request**: Can call bd-doctor to verify Beads sync
- **issue-first**: Works with bd-doctor for branch/issue validation

**No config changes needed** - skills auto-activate based on context.

---

## 🐛 Troubleshooting

### Scripts show "Permission denied"
```bash
cd ~/.agent/skills
chmod +x */check.sh */fix.sh
```

### Skills don't auto-activate
Check:
1. Skills are in `~/.agent/skills/` (correct location)
2. `SKILL.md` files exist (contain auto-activation rules)
3. You're using phrases from the "Auto-activates" sections above

### Git pull shows conflicts
```bash
cd ~/.agent/skills
git stash        # Save local changes
git pull
git stash pop    # Restore if needed
```

---

## 📚 Repo-Specific Deployment (Optional)

These Universal Skills work across all repos. For maximum impact, also deploy repo-specific files from **prime-radiant-ai** reference implementation:

### For affordabot or other repos:

1. **Centralized test fixtures**:
   - Copy pattern from `prime-radiant-ai/backend/tests/conftest.py`
   - Auto-setup Clerk, Supabase, External API stubs
   - Eliminates 14 commits of manual fixture configuration

2. **CI lockfile validation**:
   - Copy `.github/workflows/lockfile-validation.yml`
   - Fast-fail (<2 min) before expensive test suites

3. **CI job template**:
   - Copy `.github/workflows/templates/python-test-job.yml`
   - Reduces CI config from 30+ lines to 3 lines per job

See prime-radiant-ai epic bd-vi6j for reference implementation.

---

## 🎯 Success Criteria

After using these skills for 60 commits, expect:
- ✅ Lockfile drift: <2 occurrences (down from 9)
- ✅ Beads sync issues: <1 occurrence (down from 7)
- ✅ Railway deployment failures: <2 occurrences (down from 12)
- ✅ Total toil rate: <34% (down from 58%)

---

## 📖 Documentation

- **Full implementation**: See prime-radiant-ai `docs/beads/bd-vi6j-commit-log.md`
- **Skill details**: Read individual `SKILL.md` files in each skill directory
- **Epic context**: bd-vi6j (DX Quality-of-Life: Eliminate 58% toil rate)

---

## 🔗 Related

- **Epic**: bd-vi6j - DX Quality-of-Life
- **Repo**: https://github.com/stars-end/agent-skills
- **Commits**: b46ed20 (skills), 11b0791 (scripts)
- **Reference**: prime-radiant-ai implementation
- **Test repos**: prime-radiant-ai, affordabot

---

**Questions?** Read the SKILL.md in each skill directory for detailed usage and troubleshooting.

**Last Updated**: 2025-12-07
**Version**: 1.0.0
**Agent Compatibility**: Claude Code, Codex CLI, Antigravity
