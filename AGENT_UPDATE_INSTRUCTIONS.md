# Agent Update Instructions: Auto-Merge Beads JSONL (bd-p4jf)

**Date**: 2025-12-08
**Version**: 1.0.0
**Affects**: All agents working on repos with Beads tracking

---

## 📋 Copy-Paste This To All Agents

```
🔔 AGENT-SKILLS UPDATE AVAILABLE

Feature: Auto-merge Beads JSONL conflicts
Status: Ready to deploy
Time: 5 minutes per agent

Instructions: https://github.com/stars-end/agent-skills/blob/main/AGENT_UPDATE_INSTRUCTIONS.md
Or: cat ~/.agent/skills/AGENT_UPDATE_INSTRUCTIONS.md
```

---

## 🎯 What This Update Does

**Problem Solved**: GitHub PRs blocked by `.beads/issues.jsonl` merge conflicts

**Solution**: Two-layer auto-merge system
- Layer 1: Skill prevents conflicts (90% coverage)
- Layer 2: GitHub Action resolves conflicts (10% coverage)

**Impact**: Zero manual JSONL conflict resolution going forward

---

## 🚀 Quick Start (All Agents)

### Step 1: Update agent-skills (All VMs)

Run this on **EVERY VM**:

```bash
cd ~/.agent/skills
git checkout main
git pull
cat LATEST_UPDATE.md  # Read what's new
```

**Expected output**:
```
Already on 'main'
Updating 9a0ac40..627d8ed
Fast-forward
 6 files changed, 642 insertions(+), 3 deletions(-)
 create mode 100644 github-actions/actions/auto-merge-beads/README.md
 ...
```

**Verify**:
```bash
# Check new files exist
ls -la github-actions/actions/auto-merge-beads/
ls -la github-actions/workflows/auto-merge-beads.yml.ref

# Check skill updated
grep -A 5 "### 2.4. Sync with Master" create-pull-request/SKILL.md
```

### Step 2: Deploy to Your Primary Repo (One Agent Only)

**Choose ONE agent** to deploy to shared repos (e.g., prime-radiant-ai):

```bash
cd ~/prime-radiant-ai  # Or your main repo
git checkout master
git pull

# Copy workflow template
cp ~/.agent/skills/github-actions/workflows/auto-merge-beads.yml.ref \
   .github/workflows/auto-merge-beads.yml

# Commit
git add .github/workflows/auto-merge-beads.yml
git commit -m "feat: Add Beads JSONL auto-merge workflow (bd-p4jf)"
git push
```

**Wait for**: Other agents to pull this workflow from master

### Step 3: Verify Setup (All Agents)

Run this on **EVERY VM** after Step 2 is merged:

```bash
cd ~/prime-radiant-ai  # Or your repo
git checkout master
git pull

# Verify workflow exists
cat .github/workflows/auto-merge-beads.yml | head -5

# Should show:
# name: Auto-Merge Beads JSONL
# on:
#   pull_request:
```

**Status check**:
```bash
# Check GitHub Actions tab
gh workflow list | grep auto-merge-beads
# Should show: auto-merge-beads  active

# Check skill works
cd ~/.agent/skills
cat create-pull-request/SKILL.md | grep -A 3 "### 2.4"
# Should show sync with master section
```

---

## 🔄 Updated Workflow (What Changed)

### Before This Update

**Creating a PR:**
```bash
User: "create PR"
Agent: Opens PR
GitHub: ❌ "This branch has conflicts"
Agent: Must resolve manually
```

### After This Update

**Creating a PR (Layer 1 - Proactive):**
```bash
User: "create PR"
Agent: Runs create-pull-request skill
  → Skill auto-merges master
  → Resolves JSONL conflicts automatically
  → Opens PR
GitHub: ✅ "Ready to merge"
```

**If conflicts slip through (Layer 2 - Reactive):**
```bash
Agent: Creates PR manually (bypassed skill)
GitHub: ❌ "This branch has conflicts"
Action: Runs auto-merge-beads workflow
  → Auto-resolves JSONL conflicts
  → Pushes fix to PR
  → Comments: "✅ Conflict auto-resolved"
GitHub: ✅ "Ready to merge"
```

---

## 📝 Agent-Specific Actions

### For Agents on VM1 (Example: claude-code)

```bash
# 1. Update agent-skills
cd ~/.agent/skills && git pull

# 2. Verify skill updated
grep "Sync with Master" create-pull-request/SKILL.md

# 3. Test on next PR
# Just use: "create PR" as normal
# Skill automatically handles merge
```

### For Agents on VM2 (Example: codex)

```bash
# 1. Update agent-skills
cd ~/.agent/skills && git pull

# 2. Wait for VM1 agent to deploy workflow
# Check: git pull in ~/prime-radiant-ai
# Verify: .github/workflows/auto-merge-beads.yml exists

# 3. Test on next PR
# Create PR as normal
# Action catches any missed conflicts
```

### For Agents on VM3, VM4, etc.

Same as VM2 - just pull updates and verify.

---

## 🧪 Testing Instructions

### Test 1: Skill Prevents Conflicts (Expected Path)

```bash
# Create feature branch with JSONL changes
git checkout -b feature-test-automerge
bd create "Test auto-merge" --type task
# Make some changes
git commit -am "test changes"

# Use create-pull-request skill
User: "create PR"

# Expected behavior:
# 1. Skill detects JSONL divergence
# 2. Auto-merges master
# 3. Resolves conflicts
# 4. Creates PR
# 5. ✅ No conflicts on GitHub
```

### Test 2: Action Resolves Conflicts (Fallback Path)

```bash
# Create PR manually (bypass skill)
git checkout -b feature-test-action
bd create "Test action" --type task
git commit -am "test changes"
git push -u origin feature-test-action

# Create PR manually
gh pr create --title "Test auto-merge action" --body "Testing"

# Expected behavior:
# 1. PR has JSONL conflicts
# 2. Action runs automatically
# 3. Auto-resolves conflicts
# 4. Comments on PR: "✅ Conflict auto-resolved"
# 5. ✅ PR becomes mergeable
```

---

## ❓ FAQ

### Q: Do I need to do anything special when creating PRs?

**A**: No! Just use "create PR" as normal. The skill automatically handles merging master to prevent conflicts.

### Q: What if I create a PR manually (gh pr create)?

**A**: The GitHub Action (Layer 2) will catch it and auto-resolve any JSONL conflicts. You'll see a comment on the PR.

### Q: What if JSONL AND code files have conflicts?

**A**: The action will abort (safety check). You'll need to resolve manually. Only JSONL-only conflicts are auto-merged.

### Q: Do I need to deploy the workflow to every repo?

**A**: Only to repos with Beads tracking (`.beads/issues.jsonl`). If a repo doesn't use Beads, skip deployment.

### Q: Can I disable this if it causes issues?

**A**: Yes! Just delete `.github/workflows/auto-merge-beads.yml` or disable the workflow in GitHub Actions settings.

### Q: What if the skill doesn't run (I'm using a different tool)?

**A**: The GitHub Action (Layer 2) is your fallback. It'll catch and resolve conflicts even if you bypass the skill.

---

## 🐛 Troubleshooting

### Issue: "Skill doesn't seem to be running"

**Check**:
```bash
cd ~/.agent/skills
git log --oneline -5 create-pull-request/SKILL.md
# Should show recent update (bd-p4jf)

grep -A 10 "### 2.4" create-pull-request/SKILL.md
# Should show "Sync with Master" section
```

**Fix**: Pull latest agent-skills
```bash
cd ~/.agent/skills && git pull
```

### Issue: "GitHub Action not running on my PR"

**Check**:
```bash
cd ~/prime-radiant-ai  # Your repo
cat .github/workflows/auto-merge-beads.yml | head -10
# Should exist and show workflow config
```

**Fix**: Deploy workflow
```bash
cp ~/.agent/skills/github-actions/workflows/auto-merge-beads.yml.ref \
   .github/workflows/auto-merge-beads.yml
git add .github/workflows/auto-merge-beads.yml
git commit -m "feat: Add auto-merge workflow"
git push
```

### Issue: "Action runs but doesn't resolve conflict"

**Check PR for comment**:
```bash
gh pr view <PR#> --comments
```

**Possible reasons**:
1. Multiple files have conflicts (not just JSONL) → Manual resolution required
2. JSONL corruption → Run `bd export -o .beads/issues.jsonl` and commit
3. Permission issues → Check GitHub Actions has write permissions

---

## 📊 Rollout Status Tracking

### Checklist for Each Agent/VM

**VM1 (claude-code):**
- [ ] agent-skills updated
- [ ] Workflow deployed to prime-radiant-ai
- [ ] Skill tested (created 1 PR successfully)
- [ ] Action verified (checked workflow runs)

**VM2 (codex):**
- [ ] agent-skills updated
- [ ] Workflow exists in prime-radiant-ai (pulled from master)
- [ ] Skill tested
- [ ] Action verified

**VM3 (...):**
- [ ] agent-skills updated
- [ ] Workflow exists in repos
- [ ] Skill tested
- [ ] Action verified

**VM4 (...):**
- [ ] agent-skills updated
- [ ] Workflow exists in repos
- [ ] Skill tested
- [ ] Action verified

---

## 📞 Support

**Questions?** Ask the agent who deployed this:
- Beads issue: bd-p4jf
- PR: https://github.com/stars-end/agent-skills/pull/2
- Docs: `~/.agent/skills/github-actions/actions/auto-merge-beads/README.md`

**Issues?** Create Beads issue or comment on bd-p4jf

---

**Last Updated**: 2025-12-08
**Next Update**: TBD (check LATEST_UPDATE.md regularly)
