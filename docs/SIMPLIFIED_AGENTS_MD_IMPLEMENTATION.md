# Simplified AGENTS.md Implementation Plan
## Zero-Cognitive-Load Enforcement for Solo Developer

**Date:** 2026-02-01  
**Objective:** Auto-generated AGENTS.md + enforcement with minimal maintenance burden  
**Constraint:** Solo founder, 3 VMs, all zsh, no per-IDE customization

---

## Design Principles

1. **Simplicity over completeness** - Fewer moving parts
2. **zsh-only** - All VMs run zsh (macOS, WSL, Ubuntu)
3. **No per-IDE hooks** - Shell-level only, IDEs inherit
4. **Goal, not hard stop** - <800 lines target, not blocker
5. **All-at-once rollout** - Deploy everything in one session

---

## Architecture (3 Components Only)

### Component 1: AGENTS.md Generator (Per-Repo)

**Purpose:** Auto-generate AGENTS.md from SKILL.md files

**Files:**
```
~/agent-skills/
├── AGENTS.md (GENERATED)
├── fragments/
│   ├── nakomi-protocol.md (static)
│   └── canonical-rules.md (static)
└── scripts/
    └── generate-agents-index.sh (generator)

~/prime-radiant-ai/
├── AGENTS.md (GENERATED = universal + repo-specific)
├── fragments/
│   └── repo-specific.md (static)
└── scripts/
    └── compile-agents-md.sh (generator)
```

**How it works:**
```bash
# Universal (agent-skills)
~/agent-skills/scripts/generate-agents-index.sh
# Output: ~/agent-skills/AGENTS.md (300-500 lines)

# Repo-specific (prime-radiant-ai)
~/prime-radiant-ai/scripts/compile-agents-md.sh
# Output: ~/prime-radiant-ai/AGENTS.md (500-700 lines)
#   = cat ~/agent-skills/AGENTS.md
#     + context skills index
#     + workflow skills index
#     + fragments/repo-specific.md
```

**Line count:** Target <800, warn if over, but don't block

---

### Component 2: Auto-Update (Git Hook Only)

**Purpose:** Regenerate AGENTS.md when SKILL.md changes

**Files:**
```
~/agent-skills/.git/hooks/post-commit
~/prime-radiant-ai/.git/hooks/post-commit
~/affordabot/.git/hooks/post-commit
~/llm-common/.git/hooks/post-commit
```

**How it works:**
```bash
#!/bin/zsh
# post-commit hook

if git diff-tree --name-only -r HEAD | grep -q "SKILL.md\|fragments/"; then
    ./scripts/generate-agents-index.sh  # or compile-agents-md.sh
    
    if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
        git add AGENTS.md
        git commit --amend --no-edit --no-verify
    fi
fi
```

**Triggers:**
- ✅ Git post-commit (immediate, local)
- ❌ Cron (removed - too complex)
- ❌ GitHub Actions (removed - too complex)
- ❌ Pre-push hook (removed - too complex)

**Result:** AGENTS.md regenerates on commit, amends automatically

---

### Component 3: Session-Start Enforcement (zsh-only)

**Purpose:** Warn agents about canonical repos, guide to worktrees

**Files:**
```
~/.zshrc (on all VMs)
~/canonical-repo-reminder.sh (sourced by .zshrc)
```

**How it works:**
```bash
# ~/.zshrc (add to end)
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi
```

```bash
# ~/canonical-repo-reminder.sh
#!/bin/zsh

# Only run in interactive shells
[[ $- != *i* ]] && return

# Check if in canonical repo
REPO=$(basename "$PWD" 2>/dev/null)
if [[ "$PWD" =~ (agent-skills|prime-radiant-ai|affordabot|llm-common)$ ]]; then
    # Check if in worktree
    if git rev-parse --git-dir 2>/dev/null | grep -q worktrees; then
        echo "✅ Worktree (safe to commit)"
    else
        echo ""
        echo "⚠️  CANONICAL REPO: ~/$REPO (read-only)"
        echo "   Use: dx-worktree create bd-xxx $REPO"
        echo ""
    fi
fi
```

**Triggers:**
- ✅ Every new shell session (zsh startup)
- ✅ Works for all IDEs (inherit from shell)
- ❌ No per-IDE hooks (removed)

**Result:** Agents see warning on session start, no custom IDE config needed

---

## AGENTS.md Structure (Hybrid Format)

**Target: 400-750 lines (goal, not hard stop)**

```markdown
# AGENTS.md
<!-- AUTO-GENERATED - Last updated: 2026-02-01 -->

## Part 1: Nakomi Protocol (50 lines)
- Decision autonomy tiers
- Cognitive load principles

## Part 2: Canonical Repo Rules (50 lines)
- Worktree workflow
- Pre-commit hook enforcement
- Recovery procedures

## Part 3: Skill Index (300-500 lines)

### Core Workflows (9 → 18 skills)
| Skill | Description | Example | Tags |
|-------|-------------|---------|------|
| **beads-workflow** | Create/track issues | `bd create "fix auth"` | [workflow, beads] |
| **sync-feature-branch** | Save WIP | `sync-feature "progress"` | [git, commit] |
| **worktree-workflow** | Work on canonical repos | `dx-worktree create bd-xxx repo` | [dx, worktree] |

### Extended Workflows (12 → 24 skills)
[Same format]

### Context Skills (15 → 30 per repo, repo-specific only)
[Same format]

## Part 4: Quick Reference (50 lines)
- Common commands
- Troubleshooting
```

**Each skill gets:**
- 1 table row (name, description, example, tags)
- Example command inline (not separate section)
- ~3-4 lines per skill

**Scaling:**
- 80 skills today: ~400 lines
- 200 skills future: ~750 lines
- Still <800 line goal

---

## Implementation (3 Hours Total)

### Phase 1: Create Fragments (30 min)

```bash
# 1.1 Create directories
mkdir -p ~/agent-skills/fragments
mkdir -p ~/prime-radiant-ai/fragments
mkdir -p ~/affordabot/fragments
mkdir -p ~/llm-common/fragments

# 1.2 Extract Nakomi protocol
sed -n '1,40p' ~/agent-skills/AGENTS.md > ~/agent-skills/fragments/nakomi-protocol.md

# 1.3 Extract canonical rules
sed -n '60,110p' ~/agent-skills/AGENTS.md > ~/agent-skills/fragments/canonical-rules.md

# 1.4 Create repo-specific fragment (prime-radiant-ai)
cat > ~/prime-radiant-ai/fragments/repo-specific.md <<'EOF'
## Verification Cheatsheet

| Target | Scope | Use For |
|--------|-------|---------|
| `make verify-local` | Local | Lint, unit tests (fast) |
| `make verify-dev` | Railway dev | Full E2E after merge |
| `make verify-pr PR=N` | Railway PR | P0/P1 PRs, multi-file |

## DX Bootstrap

**Session start:**
```bash
scripts/bd-context  # Runs dx-doctor + shows current work
```

## Railway Deployment

```bash
railway status
railway logs
railway up
```
EOF
```

---

### Phase 2: Write Generators (1 hour)

**2.1 Universal Generator (agent-skills)**

```bash
cat > ~/agent-skills/scripts/generate-agents-index.sh <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

OUTFILE="$HOME/agent-skills/AGENTS.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

# Header
cat > "$OUTFILE" <<EOF
# AGENTS.md — Agent Skills Index
<!-- AUTO-GENERATED from SKILL.md files -->
<!-- Last updated: $TIMESTAMP -->
<!-- DO NOT EDIT MANUALLY - Run: scripts/generate-agents-index.sh -->

EOF

# Nakomi protocol
cat "$HOME/agent-skills/fragments/nakomi-protocol.md" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Canonical rules
cat "$HOME/agent-skills/fragments/canonical-rules.md" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Function to extract skill metadata
extract_skill() {
    local skill_file="$1"
    local name=$(grep "^name:" "$skill_file" 2>/dev/null | cut -d: -f2- | xargs)
    [[ -z "$name" ]] && name=$(basename $(dirname "$skill_file"))
    
    local desc=$(grep "^description:" "$skill_file" -A3 2>/dev/null | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-80)
    [[ -z "$desc" ]] && desc="—"
    
    local tags=$(grep "^tags:" "$skill_file" 2>/dev/null | cut -d: -f2- | xargs)
    [[ -z "$tags" ]] && tags="—"
    
    # Extract first example command
    local example=$(grep -A10 "^## Example\|^### Example\|^\`\`\`bash" "$skill_file" 2>/dev/null | grep -E "^\s*[a-z-]+" | head -1 | xargs | cut -c1-50)
    [[ -z "$example" ]] && example="—"
    
    echo "| **$name** | $desc | \`$example\` | $tags |"
}

# Core Workflows
echo "## Core Workflows" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "| Skill | Description | Example | Tags |" >> "$OUTFILE"
echo "|-------|-------------|---------|------|" >> "$OUTFILE"

for skill in ~/agent-skills/core/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    extract_skill "$skill" >> "$OUTFILE"
done

# Extended Workflows
echo "" >> "$OUTFILE"
echo "## Extended Workflows" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "| Skill | Description | Example | Tags |" >> "$OUTFILE"
echo "|-------|-------------|---------|------|" >> "$OUTFILE"

for skill in ~/agent-skills/extended/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    extract_skill "$skill" >> "$OUTFILE"
done

# Infrastructure & Health
echo "" >> "$OUTFILE"
echo "## Infrastructure & Health" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "| Skill | Description | Example | Tags |" >> "$OUTFILE"
echo "|-------|-------------|---------|------|" >> "$OUTFILE"

for skill in ~/agent-skills/{health,infra,railway,dispatch}/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    extract_skill "$skill" >> "$OUTFILE"
done

# Footer
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"
cat >> "$OUTFILE" <<'EOF'

## Skill Discovery

**Auto-loaded from:** `~/agent-skills/{core,extended,health,infra,railway,dispatch}/*/SKILL.md`

**Full documentation:** Each SKILL.md contains detailed implementation and examples.

**Regenerate:** `~/agent-skills/scripts/generate-agents-index.sh`
EOF

# Warn if >800 lines (goal, not blocker)
LINES=$(wc -l < "$OUTFILE")
if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md is $LINES lines (goal: <800)"
    echo "   Consider reducing skill descriptions"
else
    echo "✅ Generated $OUTFILE ($LINES lines)"
fi
SCRIPT

chmod +x ~/agent-skills/scripts/generate-agents-index.sh
```

**2.2 Repo-Specific Generator (prime-radiant-ai)**

```bash
cat > ~/prime-radiant-ai/scripts/compile-agents-md.sh <<'SCRIPT'
#!/bin/zsh
set -euo pipefail

OUTFILE="$HOME/prime-radiant-ai/AGENTS.md"

# Start with universal AGENTS.md
cat ~/agent-skills/AGENTS.md > "$OUTFILE"

# Add repo-specific header
cat >> "$OUTFILE" <<'EOF'

---

# Prime Radiant — Repo-Specific Skills

EOF

# Context Skills
echo "## Context Skills (Domain Knowledge)" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "| Skill | Description | Keywords |" >> "$OUTFILE"
echo "|-------|-------------|----------|" >> "$OUTFILE"

for skill in ~/prime-radiant-ai/.claude/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    desc=$(grep "^description:" "$skill" -A5 2>/dev/null | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-80)
    [[ -z "$desc" ]] && desc="—"
    keywords=$(grep "Keywords:" "$skill" 2>/dev/null | cut -d: -f2- | xargs | cut -c1-60)
    [[ -z "$keywords" ]] && keywords="—"
    name=$(basename $(dirname "$skill"))
    echo "| **$name** | $desc | $keywords |" >> "$OUTFILE"
done

# Workflow Skills
echo "" >> "$OUTFILE"
echo "## Workflow Skills (Repo-Specific)" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "| Skill | Description | Tags |" >> "$OUTFILE"
echo "|-------|-------------|------|" >> "$OUTFILE"

for skill in ~/prime-radiant-ai/dx-workflow-system/dx-plugin/skills/*/SKILL.md; do
    [[ -f "$skill" ]] || continue
    name=$(grep "^name:" "$skill" 2>/dev/null | cut -d: -f2- | xargs)
    [[ -z "$name" ]] && name=$(basename $(dirname "$skill"))
    desc=$(grep "^description:" "$skill" -A3 2>/dev/null | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-80)
    [[ -z "$desc" ]] && desc="—"
    tags=$(grep "^tags:" "$skill" 2>/dev/null | cut -d: -f2- | xargs)
    [[ -z "$tags" ]] && tags="—"
    echo "| **$name** | $desc | $tags |" >> "$OUTFILE"
done

# Repo-specific fragment
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

if [[ -f ~/prime-radiant-ai/fragments/repo-specific.md ]]; then
    cat ~/prime-radiant-ai/fragments/repo-specific.md >> "$OUTFILE"
fi

# Warn if >800 lines
LINES=$(wc -l < "$OUTFILE")
if [[ $LINES -gt 800 ]]; then
    echo "⚠️  WARNING: AGENTS.md is $LINES lines (goal: <800)"
else
    echo "✅ Generated $OUTFILE ($LINES lines)"
fi
SCRIPT

chmod +x ~/prime-radiant-ai/scripts/compile-agents-md.sh
```

**2.3 Copy Template to Other Repos**

```bash
# affordabot
cp ~/prime-radiant-ai/scripts/compile-agents-md.sh ~/affordabot/scripts/
sed -i 's/prime-radiant-ai/affordabot/g' ~/affordabot/scripts/compile-agents-md.sh

# llm-common
cp ~/prime-radiant-ai/scripts/compile-agents-md.sh ~/llm-common/scripts/
sed -i 's/prime-radiant-ai/llm-common/g' ~/llm-common/scripts/compile-agents-md.sh
```

---

### Phase 3: Git Hooks (30 min)

**3.1 Create Post-Commit Hook Template**

```bash
cat > ~/agent-skills/scripts/post-commit-hook-template.sh <<'SCRIPT'
#!/bin/zsh
# Auto-regenerate AGENTS.md when SKILL.md changes

if git diff-tree --name-only -r HEAD | grep -q "SKILL.md\|fragments/"; then
    # Determine which generator to run
    REPO_ROOT=$(git rev-parse --show-toplevel)
    
    if [[ -f "$REPO_ROOT/scripts/generate-agents-index.sh" ]]; then
        "$REPO_ROOT/scripts/generate-agents-index.sh"
    elif [[ -f "$REPO_ROOT/scripts/compile-agents-md.sh" ]]; then
        "$REPO_ROOT/scripts/compile-agents-md.sh"
    fi
    
    # Amend commit if AGENTS.md changed
    if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
        git add AGENTS.md
        git commit --amend --no-edit --no-verify
        echo "✅ AGENTS.md regenerated and amended"
    fi
fi
SCRIPT

chmod +x ~/agent-skills/scripts/post-commit-hook-template.sh
```

**3.2 Deploy to All Repos**

```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/scripts/post-commit-hook-template.sh ~/$repo/.git/hooks/post-commit
    chmod +x ~/$repo/.git/hooks/post-commit
done
```

---

### Phase 4: Session-Start Reminder (30 min)

**4.1 Create Reminder Script**

```bash
cat > ~/canonical-repo-reminder.sh <<'SCRIPT'
#!/bin/zsh
# Session-start reminder for canonical repos

# Only run in interactive shells
[[ $- != *i* ]] && return

# Check if in canonical repo
REPO=$(basename "$PWD" 2>/dev/null)
if [[ "$PWD" =~ (agent-skills|prime-radiant-ai|affordabot|llm-common)$ ]]; then
    # Check if in worktree
    if git rev-parse --git-dir 2>/dev/null | grep -q worktrees; then
        echo "✅ Worktree: $(basename $PWD) (safe to commit)"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  CANONICAL REPO: ~/$REPO"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "This directory auto-resets to origin/master hourly."
        echo "Pre-commit hook will block commits."
        echo ""
        echo "✅ Correct workflow:"
        echo "   dx-worktree create bd-xxx $REPO"
        echo "   cd /tmp/agents/bd-xxx/$REPO"
        echo ""
        echo "📖 See: ~/agent-skills/AGENTS.md#canonical-repos"
        echo ""
    fi
fi
SCRIPT

chmod +x ~/canonical-repo-reminder.sh
```

**4.2 Add to .zshrc (All VMs)**

```bash
# homedesktop-wsl
grep -q 'canonical-repo-reminder.sh' ~/.zshrc || echo '
# Canonical repo reminder
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi' >> ~/.zshrc

# macmini
ssh fengning@macmini "grep -q 'canonical-repo-reminder.sh' ~/.zshrc || echo '
# Canonical repo reminder
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi' >> ~/.zshrc"

# epyc6
ssh feng@epyc6 "grep -q 'canonical-repo-reminder.sh' ~/.zshrc || echo '
# Canonical repo reminder
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi' >> ~/.zshrc"
```

---

### Phase 5: Generate Initial AGENTS.md (15 min)

```bash
# Generate universal
cd ~/agent-skills
./scripts/generate-agents-index.sh

# Generate repo-specific
cd ~/prime-radiant-ai
./scripts/compile-agents-md.sh

cd ~/affordabot
./scripts/compile-agents-md.sh

cd ~/llm-common
./scripts/compile-agents-md.sh

# Verify line counts
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    lines=$(wc -l ~/$repo/AGENTS.md | cut -d' ' -f1)
    echo "$repo: $lines lines"
done
```

---

### Phase 6: Deploy to All VMs (45 min)

**6.1 Package Deployment**

```bash
cd ~
tar czf /tmp/agents-md-deployment.tar.gz \
    canonical-repo-reminder.sh \
    agent-skills/scripts/generate-agents-index.sh \
    agent-skills/scripts/post-commit-hook-template.sh \
    agent-skills/fragments/ \
    prime-radiant-ai/scripts/compile-agents-md.sh \
    prime-radiant-ai/fragments/ \
    affordabot/scripts/compile-agents-md.sh \
    llm-common/scripts/compile-agents-md.sh
```

**6.2 Deploy to macmini**

```bash
scp /tmp/agents-md-deployment.tar.gz fengning@macmini:/tmp/
ssh fengning@macmini <<'SSH'
cd ~
tar xzf /tmp/agents-md-deployment.tar.gz

# Deploy git hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/scripts/post-commit-hook-template.sh ~/$repo/.git/hooks/post-commit
    chmod +x ~/$repo/.git/hooks/post-commit
done

# Add to .zshrc
grep -q 'canonical-repo-reminder.sh' ~/.zshrc || echo '
# Canonical repo reminder
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi' >> ~/.zshrc

# Generate AGENTS.md
cd ~/agent-skills && ./scripts/generate-agents-index.sh
cd ~/prime-radiant-ai && ./scripts/compile-agents-md.sh
cd ~/affordabot && ./scripts/compile-agents-md.sh
cd ~/llm-common && ./scripts/compile-agents-md.sh

echo "✅ macmini deployment complete"
SSH
```

**6.3 Deploy to epyc6**

```bash
scp /tmp/agents-md-deployment.tar.gz feng@epyc6:/tmp/
ssh feng@epyc6 <<'SSH'
cd ~
tar xzf /tmp/agents-md-deployment.tar.gz

# Deploy git hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/scripts/post-commit-hook-template.sh ~/$repo/.git/hooks/post-commit
    chmod +x ~/$repo/.git/hooks/post-commit
done

# Add to .zshrc
grep -q 'canonical-repo-reminder.sh' ~/.zshrc || echo '
# Canonical repo reminder
if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi' >> ~/.zshrc

# Generate AGENTS.md
cd ~/agent-skills && ./scripts/generate-agents-index.sh
cd ~/prime-radiant-ai && ./scripts/compile-agents-md.sh
cd ~/affordabot && ./scripts/compile-agents-md.sh
cd ~/llm-common && ./scripts/compile-agents-md.sh

echo "✅ epyc6 deployment complete"
SSH
```

---

### Phase 7: Verification (15 min)

```bash
# 7.1 Verify AGENTS.md generation
for vm in homedesktop-wsl macmini epyc6; do
    echo "=== $vm ==="
    ssh $vm "wc -l ~/agent-skills/AGENTS.md ~/prime-radiant-ai/AGENTS.md"
done

# 7.2 Verify git hooks
for vm in homedesktop-wsl macmini epyc6; do
    echo "=== $vm ==="
    ssh $vm "ls -la ~/agent-skills/.git/hooks/post-commit"
done

# 7.3 Verify .zshrc
for vm in homedesktop-wsl macmini epyc6; do
    echo "=== $vm ==="
    ssh $vm "grep -c 'canonical-repo-reminder.sh' ~/.zshrc"
done

# 7.4 Test post-commit hook
cd ~/agent-skills
touch core/test-skill/SKILL.md
git add core/test-skill/SKILL.md
git commit -m "test: trigger AGENTS.md regeneration"
# Expected: AGENTS.md regenerated and amended

# 7.5 Test session-start reminder
# Open new terminal in canonical repo
# Expected: Warning message appears
```

---

## Maintenance (Ongoing)

### Adding New Skills

```bash
# 1. Create skill
mkdir -p ~/agent-skills/core/new-skill
cat > ~/agent-skills/core/new-skill/SKILL.md <<'EOF'
---
name: new-skill
description: Does something useful
tags: [workflow, automation]
---

## Example
```bash
new-skill --help
```
EOF

# 2. Commit (auto-regenerates AGENTS.md)
git add core/new-skill/
git commit -m "feat: add new-skill"
# AGENTS.md automatically regenerated and amended
```

### Updating Fragments

```bash
# Edit static content
vim ~/agent-skills/fragments/canonical-rules.md

# Regenerate
~/agent-skills/scripts/generate-agents-index.sh

# Commit
git add fragments/canonical-rules.md AGENTS.md
git commit -m "docs: update canonical rules"
```

### Checking Line Counts

```bash
# Check all repos
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    lines=$(wc -l ~/$repo/AGENTS.md | cut -d' ' -f1)
    if [[ $lines -gt 800 ]]; then
        echo "⚠️  $repo: $lines lines (over goal)"
    else
        echo "✅ $repo: $lines lines"
    fi
done
```

---

## Component Summary

| Component | Files | Purpose | Maintenance |
|-----------|-------|---------|-------------|
| **Generator** | `scripts/generate-agents-index.sh` (per repo) | Auto-generate AGENTS.md from SKILL.md | Add skills → auto-regenerates |
| **Git Hook** | `.git/hooks/post-commit` (per repo) | Trigger regeneration on commit | None (auto-runs) |
| **Session Reminder** | `~/canonical-repo-reminder.sh` + `.zshrc` | Warn about canonical repos | None (auto-runs) |

**Total: 3 components, 5 files per repo**

---

## What Was Removed (Simplification)

**Removed from over-engineered plan:**
- ❌ Cron jobs (hourly regeneration) - Too complex
- ❌ GitHub Actions (CI regeneration) - Too complex
- ❌ Pre-push hooks (validation) - Too complex
- ❌ Per-IDE session hooks (Windsurf, Cursor, etc.) - Maintenance nightmare
- ❌ Hard stop on 800 lines - Changed to warning
- ❌ Session-start auto-worktree creation - Too aggressive
- ❌ Enhanced dx-check worktree status - Not needed

**What remains:**
- ✅ Git post-commit hook (immediate, local)
- ✅ zsh session reminder (shell-level, IDE-agnostic)
- ✅ AGENTS.md generator (per-repo)

**Result:** 3 components instead of 8, minimal maintenance

---

## Success Metrics

**Week 1:**
- ✅ AGENTS.md auto-generated on all VMs
- ✅ <800 lines (goal met)
- ✅ Session reminder working in all shells
- ✅ Git hooks regenerating on commit

**Week 2:**
- ✅ Zero manual AGENTS.md updates
- ✅ Skills added → AGENTS.md auto-updates
- ✅ Agents see canonical repo warnings

**Week 4:**
- ✅ All VMs in sync
- ✅ No maintenance required
- ✅ System running autonomously

---

## Rollback Plan

**If issues arise:**

```bash
# 1. Disable git hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    rm ~/$repo/.git/hooks/post-commit
done

# 2. Disable session reminder
sed -i 's/source ~\/canonical-repo-reminder.sh/# source ~\/canonical-repo-reminder.sh/' ~/.zshrc

# 3. Restore original AGENTS.md
cd ~/agent-skills
git checkout HEAD~1 AGENTS.md
git commit -m "rollback: restore manual AGENTS.md"
```

---

## Total Implementation Time

| Phase | Time |
|-------|------|
| 1. Create fragments | 30 min |
| 2. Write generators | 1 hour |
| 3. Git hooks | 30 min |
| 4. Session reminder | 30 min |
| 5. Generate initial | 15 min |
| 6. Deploy to VMs | 45 min |
| 7. Verification | 15 min |
| **Total** | **3 hours** |

**All-at-once rollout:** Complete all phases in one session

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  VM (homedesktop-wsl, macmini, epyc6)                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ~/.zshrc                                                    │
│    └─> source ~/canonical-repo-reminder.sh                  │
│          └─> Warns if in canonical repo                     │
│                                                              │
│  ~/agent-skills/                                             │
│    ├─ AGENTS.md (GENERATED, 300-500 lines)                  │
│    ├─ fragments/                                             │
│    │   ├─ nakomi-protocol.md                                │
│    │   └─ canonical-rules.md                                │
│    ├─ scripts/                                               │
│    │   └─ generate-agents-index.sh                          │
│    └─ .git/hooks/                                            │
│        └─ post-commit → regenerate on SKILL.md change       │
│                                                              │
│  ~/prime-radiant-ai/                                         │
│    ├─ AGENTS.md (GENERATED, 500-700 lines)                  │
│    │   = ~/agent-skills/AGENTS.md                           │
│    │     + context skills                                    │
│    │     + workflow skills                                   │
│    │     + fragments/repo-specific.md                        │
│    ├─ fragments/                                             │
│    │   └─ repo-specific.md                                  │
│    ├─ scripts/                                               │
│    │   └─ compile-agents-md.sh                              │
│    └─ .git/hooks/                                            │
│        └─ post-commit → regenerate on SKILL.md change       │
│                                                              │
│  [Same structure for affordabot, llm-common]                │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Triggers:
1. Commit with SKILL.md change → post-commit hook → regenerate → amend
2. New shell in canonical repo → .zshrc → reminder → warn agent
3. Add new skill → commit → auto-regenerate → done

No cron, no GitHub Actions, no per-IDE hooks.
```

---

**END OF SIMPLIFIED IMPLEMENTATION PLAN**
