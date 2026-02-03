# Comprehensive AGENTS.md Implementation Plan
## Multi-VM × Multi-IDE × Multi-Repo Architecture

**Date:** 2026-02-01  
**Scope:** 3 VMs × 5 IDEs × 4 repos = 60 deployment targets  
**Objective:** Zero-cognitive-load enforcement + auto-generated AGENTS.md <800 lines

---

## Critical Design Questions Answered

### Q1: Multi-VM × Multi-IDE Distribution

**Environment Matrix:**
```
VMs (3):
- homedesktop-wsl (Ubuntu 24.04)
- macmini (macOS)
- epyc6 (Ubuntu 22.04)

IDEs (5):
- Windsurf (Cascade)
- Cursor
- Antigravity
- Codex CLI
- Claude Code (OpenCode)

Repos (4):
- ~/agent-skills (universal skills)
- ~/prime-radiant-ai (15 context skills + 9 workflow skills)
- ~/affordabot (TBD context skills)
- ~/llm-common (TBD context skills)
```

**Distribution Strategy:**

**Layer 1: Shell-Level (VM-wide, IDE-agnostic)**
```bash
# ~/.bashrc on all VMs
# Works for: Codex CLI, Antigravity, any terminal-based agent

if [[ -f ~/canonical-repo-reminder.sh ]]; then
    source ~/canonical-repo-reminder.sh
fi

# Session-start hook (auto-creates worktrees)
if [[ -f ~/canonical-repo-session-start.sh ]]; then
    source ~/canonical-repo-session-start.sh
fi
```

**Deployment:**
```bash
# Deploy to all VMs
for vm in homedesktop-wsl macmini epyc6; do
    scp ~/canonical-repo-reminder.sh $vm:~/
    scp ~/canonical-repo-session-start.sh $vm:~/
    ssh $vm "grep -q 'canonical-repo-reminder.sh' ~/.bashrc || echo 'source ~/canonical-repo-reminder.sh' >> ~/.bashrc"
done
```

**Layer 2: IDE-Specific (Per-IDE configuration)**

**Windsurf/Cursor (Cascade-based):**
```json
// .windsurf/settings.json or .cursor/settings.json
{
  "cascade.sessionStart": {
    "script": "~/canonical-repo-session-start.sh"
  }
}
```

**Claude Code (OpenCode):**
```yaml
# .opencode/config.yml
session_hooks:
  on_start: ~/canonical-repo-session-start.sh
```

**Antigravity:**
```bash
# Uses shell hooks automatically (no special config)
```

**Codex CLI:**
```bash
# Uses shell hooks automatically (no special config)
```

**Layer 3: Git Hooks (Repo-level, IDE-agnostic)**
```bash
# Deployed to all canonical repos on all VMs
~/agent-skills/.git/hooks/pre-commit
~/prime-radiant-ai/.git/hooks/pre-commit
~/affordabot/.git/hooks/pre-commit
~/llm-common/.git/hooks/pre-commit
```

**Deployment:**
```bash
# Deploy pre-commit hooks to all canonical repos on all VMs
for vm in homedesktop-wsl macmini epyc6; do
    for repo in agent-skills prime-radiant-ai affordabot llm-common; do
        scp ~/agent-skills/scripts/canonical-pre-commit-hook.sh $vm:~/$repo/.git/hooks/pre-commit
        ssh $vm "chmod +x ~/$repo/.git/hooks/pre-commit"
    done
done
```

**Result:** All 5 IDEs on all 3 VMs get enforcement automatically.

---

### Q2: Token Optimization vs Skill Discovery

**Current State:**
- 56 universal skills (~/agent-skills)
- 15 context skills (prime-radiant-ai/.claude/skills)
- 9 workflow skills (prime-radiant-ai/dx-plugin/skills)
- **Total: 80 skills today**

**Projected Growth:**
- Universal skills: 56 → ~100 (doubles)
- Context skills per repo: 15 → ~30 (doubles)
- **Total: ~200 skills**

**Token Budget Analysis:**

| Approach | Current (80 skills) | Future (200 skills) | Discovery Quality |
|----------|---------------------|---------------------|-------------------|
| **Full docs** | 749 lines | ~1,800 lines | ❌ Too verbose |
| **Compressed table** | 120 lines | ~300 lines | ⚠️ Too terse |
| **Hybrid (recommended)** | 400 lines | ~750 lines | ✅ Optimal |

**Hybrid Structure (400-750 lines):**

```markdown
# AGENTS.md (400-750 lines total)

## Part 1: Critical Rules (100 lines)
- Nakomi protocol (decision tiers)
- Canonical repo enforcement (worktree workflow)
- Session start protocol

## Part 2: Skill Index (200-500 lines)
### Core Workflows (9 skills → 18 skills)
| Skill | Use When | Example |
|-------|----------|---------|
| beads-workflow | Create/track issues | `bd create "fix auth"` |
| sync-feature-branch | Save WIP, commit changes | `sync-feature "progress"` |
| worktree-workflow | Work on canonical repos | `dx-worktree create bd-xxx repo` |

**Each skill gets 2-3 lines:**
- Name + description (1 line table row)
- Example command (inline)
- Tags for discovery

### Extended Workflows (12 skills → 24 skills)
[Same format]

### Context Skills (15 skills → 30 skills per repo)
[Same format]

## Part 3: Quick Reference (100 lines)
- Common commands
- Troubleshooting
- Recovery procedures
```

**Token Efficiency:**
- **Current:** 749 lines (all prose) → 400 lines (hybrid) = 47% reduction
- **Future:** 1,800 lines (all prose) → 750 lines (hybrid) = 58% reduction
- **Discovery:** Each skill visible with example = high discoverability

**Hard Stop: <800 lines enforced by generator:**
```bash
# In generate-agents-index.sh
LINES=$(wc -l < "$OUTFILE")
if [[ $LINES -gt 800 ]]; then
    echo "❌ ERROR: AGENTS.md exceeds 800 lines ($LINES)"
    echo "   Reduce skill descriptions or examples"
    exit 1
fi
```

---

### Q3: Repo-Specific vs Universal Skills

**Architecture:**

```
~/agent-skills/AGENTS.md (Universal)
├── Universal skills (56 → 100)
│   ├── core/ (workflow automation)
│   ├── extended/ (advanced workflows)
│   ├── health/ (diagnostics)
│   ├── infra/ (VM/deployment)
│   └── railway/ (deployment)
└── Canonical repo rules (universal)

~/prime-radiant-ai/AGENTS.md (Repo-Specific)
├── Universal skills (symlink or include)
├── Context skills (15 → 30)
│   ├── context-analytics
│   ├── context-api-contracts
│   ├── context-clerk-integration
│   └── ... (domain knowledge)
├── Workflow skills (9)
│   ├── dx-plugin/skills/ (repo-specific workflows)
└── Repo-specific rules
    ├── Verification cheatsheet
    ├── Railway deployment
    └── DX bootstrap

~/affordabot/AGENTS.md (Repo-Specific)
├── Universal skills (symlink or include)
├── Context skills (TBD)
└── Repo-specific rules

~/llm-common/AGENTS.md (Repo-Specific)
├── Universal skills (symlink or include)
├── Context skills (TBD)
└── Repo-specific rules
```

**Compilation Strategy:**

**Option A: Include (Recommended)**
```bash
# ~/prime-radiant-ai/AGENTS.md is GENERATED from:
cat ~/agent-skills/AGENTS.md \
    + ~/prime-radiant-ai/.claude/skills/*/SKILL.md (context skills) \
    + ~/prime-radiant-ai/dx-plugin/skills/*/SKILL.md (workflow skills) \
    + ~/prime-radiant-ai/fragments/repo-specific.md
```

**Option B: Symlink (Not Recommended)**
```bash
# Problem: Can't add repo-specific content
ln -s ~/agent-skills/AGENTS.md ~/prime-radiant-ai/AGENTS.md
```

**Verdict: Use Option A (Include)**

**File Structure:**
```
~/agent-skills/
├── AGENTS.md (GENERATED - universal only)
├── fragments/
│   ├── nakomi-protocol.md
│   └── canonical-rules.md
└── scripts/
    └── generate-agents-index.sh (generates universal AGENTS.md)

~/prime-radiant-ai/
├── AGENTS.md (GENERATED - universal + repo-specific)
├── fragments/
│   └── repo-specific.md (verification, Railway, etc.)
└── scripts/
    └── compile-agents-md.sh (generates repo AGENTS.md)
```

---

### Q4: Auto-Update Triggers

**Problem:** When to regenerate AGENTS.md?

**Triggers:**

**Trigger 1: Git Hook (Immediate, Local)**
```bash
# ~/agent-skills/.git/hooks/post-commit
#!/bin/bash
# Regenerate if any SKILL.md changed

if git diff-tree --name-only -r HEAD | grep -q "SKILL.md"; then
    ~/agent-skills/scripts/generate-agents-index.sh
    
    # Auto-commit if changed
    if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
        git add AGENTS.md
        git commit --amend --no-edit --no-verify
    fi
fi
```

**Pros:**
- ✅ Immediate (runs on commit)
- ✅ Local (no network)
- ✅ Automatic (no user action)

**Cons:**
- ⚠️ Only triggers on commits (not pulls)
- ⚠️ Amends commits (changes SHA)

**Trigger 2: Cron (Periodic, All VMs)**
```bash
# Crontab on all VMs
# Regenerate every hour (after canonical-sync)

# homedesktop: :15
15 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md" && git push

# macmini: :20
20 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md" && git push

# epyc6: :25
25 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md" && git push
```

**Pros:**
- ✅ Catches pulls (regenerates after sync)
- ✅ Runs on all VMs
- ✅ Pushes to origin (syncs across VMs)

**Cons:**
- ⚠️ Creates commits (noise in git log)
- ⚠️ Potential conflicts (if multiple VMs commit)

**Trigger 3: GitHub Actions (On Push, Centralized)**
```yaml
# .github/workflows/regenerate-agents-md.yml
name: Regenerate AGENTS.md

on:
  push:
    paths:
      - '**/SKILL.md'
      - 'fragments/*.md'

jobs:
  regenerate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Regenerate AGENTS.md
        run: ./scripts/generate-agents-index.sh
      
      - name: Commit if changed
        run: |
          if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
            git config user.name "GitHub Actions"
            git config user.email "actions@github.com"
            git add AGENTS.md
            git commit -m "chore: regenerate AGENTS.md [skip ci]"
            git push
          fi
```

**Pros:**
- ✅ Centralized (one source of truth)
- ✅ No local cron needed
- ✅ Triggers on any push (any VM)

**Cons:**
- ⚠️ Requires network (GitHub)
- ⚠️ Delay (CI pipeline time)

**Trigger 4: Pre-Push Hook (Before Push, Local)**
```bash
# ~/agent-skills/.git/hooks/pre-push
#!/bin/bash
# Regenerate before pushing

~/agent-skills/scripts/generate-agents-index.sh

if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
    echo "⚠️  AGENTS.md was regenerated. Commit it before pushing:"
    echo "   git add AGENTS.md"
    echo "   git commit -m 'chore: regenerate AGENTS.md'"
    exit 1
fi
```

**Pros:**
- ✅ Catches before push (prevents stale AGENTS.md)
- ✅ No auto-commits (user decides)

**Cons:**
- ⚠️ Blocks push (user must commit)
- ⚠️ Manual step (not automatic)

**Recommended: Hybrid Approach**

**Use all 4 triggers:**
1. **Git post-commit hook** - Immediate local regeneration
2. **Cron (hourly)** - Catch pulls and sync across VMs
3. **GitHub Actions** - Centralized enforcement
4. **Pre-push hook** - Final safety check

**Conflict Resolution:**
```bash
# In generate-agents-index.sh
# Add timestamp to prevent conflicts
echo "<!-- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) -->" >> AGENTS.md
```

**Stagger cron times:**
- homedesktop: :15 (after canonical-sync at :00)
- macmini: :20 (after canonical-sync at :05)
- epyc6: :25 (after canonical-sync at :10)

**Result:** AGENTS.md always up-to-date, minimal conflicts.

---

## Comprehensive Implementation Plan

### Phase 0: Preparation (30 min)

**0.1 Audit Current Skills**
```bash
# Count skills
find ~/agent-skills -name "SKILL.md" | wc -l  # 56
find ~/prime-radiant-ai/.claude/skills -name "SKILL.md" | wc -l  # 15
find ~/prime-radiant-ai/dx-plugin/skills -name "SKILL.md" | wc -l  # 9

# Verify all have frontmatter
for skill in ~/agent-skills/*/*/SKILL.md; do
    if ! grep -q "^name:" "$skill"; then
        echo "Missing frontmatter: $skill"
    fi
done
```

**0.2 Create Fragments Directory**
```bash
mkdir -p ~/agent-skills/fragments
mkdir -p ~/prime-radiant-ai/fragments
mkdir -p ~/affordabot/fragments
mkdir -p ~/llm-common/fragments
```

**0.3 Extract Canonical Rules to Fragment**
```bash
# Extract from current AGENTS.md lines 60-110
sed -n '60,110p' ~/agent-skills/AGENTS.md > ~/agent-skills/fragments/canonical-rules.md
```

**0.4 Extract Nakomi Protocol to Fragment**
```bash
# Extract from current AGENTS.md lines 1-40
sed -n '1,40p' ~/agent-skills/AGENTS.md > ~/agent-skills/fragments/nakomi-protocol.md
```

---

### Phase 1: Generate Universal AGENTS.md (1 hour)

**1.1 Write Generator Script**
```bash
cat > ~/agent-skills/scripts/generate-agents-index.sh <<'SCRIPT'
#!/bin/bash
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

# Nakomi protocol (static fragment)
cat "$HOME/agent-skills/fragments/nakomi-protocol.md" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Canonical rules (static fragment)
cat "$HOME/agent-skills/fragments/canonical-rules.md" >> "$OUTFILE"
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# Function to extract skill metadata
extract_skill() {
    local skill_file="$1"
    local name=$(grep "^name:" "$skill_file" | cut -d: -f2- | xargs)
    local desc=$(grep "^description:" "$skill_file" -A3 | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-100)
    local tags=$(grep "^tags:" "$skill_file" | cut -d: -f2- | xargs)
    
    # Extract first example command (if exists)
    local example=$(grep -A5 "^## Example\|^### Example\|^\`\`\`bash" "$skill_file" | grep -E "^\s*[a-z-]+" | head -1 | xargs | cut -c1-60)
    
    if [[ -n "$example" ]]; then
        echo "| **$name** | $desc | \`$example\` | $tags |"
    else
        echo "| **$name** | $desc | — | $tags |"
    fi
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

**Auto-loaded from:**
- `~/agent-skills/core/*/SKILL.md` - Core workflows
- `~/agent-skills/extended/*/SKILL.md` - Extended workflows
- `~/agent-skills/health/*/SKILL.md` - Health checks
- `~/agent-skills/infra/*/SKILL.md` - Infrastructure
- `~/agent-skills/railway/*/SKILL.md` - Deployment
- `~/agent-skills/dispatch/*/SKILL.md` - Cross-VM execution

**Full documentation:** Each SKILL.md contains detailed implementation, examples, and troubleshooting.

**Regenerate this index:**
```bash
~/agent-skills/scripts/generate-agents-index.sh
```

**Add new skill:**
1. Create `~/agent-skills/<category>/<skill-name>/SKILL.md`
2. Add frontmatter: `name:`, `description:`, `tags:`
3. Regenerate index (auto-triggered on commit)
EOF

# Enforce <800 line limit
LINES=$(wc -l < "$OUTFILE")
if [[ $LINES -gt 800 ]]; then
    echo "❌ ERROR: AGENTS.md exceeds 800 lines ($LINES)"
    echo "   Reduce skill descriptions or examples"
    exit 1
fi

echo "✅ Generated $OUTFILE ($LINES lines)"
SCRIPT

chmod +x ~/agent-skills/scripts/generate-agents-index.sh
```

**1.2 Generate First Index**
```bash
cd ~/agent-skills
./scripts/generate-agents-index.sh
# Expected: AGENTS.md is now 300-500 lines (from 749)
```

**1.3 Verify Output**
```bash
wc -l ~/agent-skills/AGENTS.md
head -50 ~/agent-skills/AGENTS.md
tail -50 ~/agent-skills/AGENTS.md
```

---

### Phase 2: Repo-Specific AGENTS.md Generators (1 hour)

**2.1 Create prime-radiant-ai Generator**
```bash
cat > ~/prime-radiant-ai/scripts/compile-agents-md.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail

OUTFILE="$HOME/prime-radiant-ai/AGENTS.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

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
    desc=$(grep "^description:" "$skill" -A5 | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-100)
    keywords=$(grep "Keywords:" "$skill" | cut -d: -f2- | xargs | cut -c1-80)
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
    name=$(grep "^name:" "$skill" | cut -d: -f2- | xargs)
    desc=$(grep "^description:" "$skill" -A3 | tail -n+2 | tr '\n' ' ' | sed 's/  */ /g' | xargs | cut -c1-100)
    tags=$(grep "^tags:" "$skill" | cut -d: -f2- | xargs)
    echo "| **$name** | $desc | $tags |" >> "$OUTFILE"
done

# Repo-specific fragment
echo "" >> "$OUTFILE"
echo "---" >> "$OUTFILE"
echo "" >> "$OUTFILE"

if [[ -f ~/prime-radiant-ai/fragments/repo-specific.md ]]; then
    cat ~/prime-radiant-ai/fragments/repo-specific.md >> "$OUTFILE"
fi

# Enforce <800 line limit
LINES=$(wc -l < "$OUTFILE")
if [[ $LINES -gt 800 ]]; then
    echo "❌ ERROR: AGENTS.md exceeds 800 lines ($LINES)"
    echo "   Reduce skill descriptions or repo-specific content"
    exit 1
fi

echo "✅ Generated $OUTFILE ($LINES lines)"
SCRIPT

chmod +x ~/prime-radiant-ai/scripts/compile-agents-md.sh
```

**2.2 Create Repo-Specific Fragment**
```bash
cat > ~/prime-radiant-ai/fragments/repo-specific.md <<'EOF'
## Verification Cheatsheet

| Target | Scope | Use For |
|--------|-------|---------|
| `make verify-local` | Local | Lint, unit tests (fast) |
| `make verify-dev` | Railway dev | Full E2E after merge |
| `make verify-pr PR=N` | Railway PR | P0/P1 PRs, multi-file |

**Skip when:** typos, comments, .gitignore updates

## DX Bootstrap

**First-time setup:**
```bash
dx-doctor
```

**Session start:**
```bash
scripts/bd-context  # Runs dx-doctor + shows current work
```

## Railway Deployment

**Check status:**
```bash
railway status
railway logs
```

**Deploy:**
```bash
railway up
```
EOF
```

**2.3 Generate prime-radiant-ai AGENTS.md**
```bash
cd ~/prime-radiant-ai
./scripts/compile-agents-md.sh
# Expected: AGENTS.md is now 500-700 lines (universal + repo-specific)
```

**2.4 Repeat for affordabot and llm-common**
```bash
# Copy template
cp ~/prime-radiant-ai/scripts/compile-agents-md.sh ~/affordabot/scripts/
cp ~/prime-radiant-ai/scripts/compile-agents-md.sh ~/llm-common/scripts/

# Adjust paths in each script
# Generate
cd ~/affordabot && ./scripts/compile-agents-md.sh
cd ~/llm-common && ./scripts/compile-agents-md.sh
```

---

### Phase 3: Auto-Update Triggers (1 hour)

**3.1 Git Post-Commit Hook (agent-skills)**
```bash
cat > ~/agent-skills/.git/hooks/post-commit <<'SCRIPT'
#!/bin/bash
# Regenerate AGENTS.md if any SKILL.md changed

if git diff-tree --name-only -r HEAD | grep -q "SKILL.md\|fragments/"; then
    ~/agent-skills/scripts/generate-agents-index.sh
    
    if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
        git add AGENTS.md
        git commit --amend --no-edit --no-verify
        echo "✅ AGENTS.md regenerated and amended to commit"
    fi
fi
SCRIPT

chmod +x ~/agent-skills/.git/hooks/post-commit
```

**3.2 Git Post-Commit Hook (repo-specific)**
```bash
for repo in prime-radiant-ai affordabot llm-common; do
    cat > ~/$repo/.git/hooks/post-commit <<SCRIPT
#!/bin/bash
# Regenerate AGENTS.md if any SKILL.md changed

if git diff-tree --name-only -r HEAD | grep -q "SKILL.md\|fragments/"; then
    ~/$repo/scripts/compile-agents-md.sh
    
    if [[ -n "\$(git status --porcelain AGENTS.md)" ]]; then
        git add AGENTS.md
        git commit --amend --no-edit --no-verify
        echo "✅ AGENTS.md regenerated and amended to commit"
    fi
fi
SCRIPT
    chmod +x ~/$repo/.git/hooks/post-commit
done
```

**3.3 Cron (Hourly Regeneration)**
```bash
# Add to crontab on all VMs

# homedesktop-wsl
crontab -e
# Add:
15 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md
20 * * * * cd ~/prime-radiant-ai && ./scripts/compile-agents-md.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md

# macmini
ssh fengning@macmini 'crontab -e'
# Add (stagger by 5 min):
20 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md
25 * * * * cd ~/prime-radiant-ai && ./scripts/compile-agents-md.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md

# epyc6
ssh feng@epyc6 'crontab -e'
# Add (stagger by 10 min):
25 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md
30 * * * * cd ~/prime-radiant-ai && ./scripts/compile-agents-md.sh && git add AGENTS.md && git commit -m "chore: regenerate AGENTS.md [skip ci]" && git push 2>&1 | logger -t agents-md
```

**3.4 GitHub Actions (Centralized)**
```bash
cat > ~/agent-skills/.github/workflows/regenerate-agents-md.yml <<'YAML'
name: Regenerate AGENTS.md

on:
  push:
    paths:
      - '**/SKILL.md'
      - 'fragments/*.md'
      - 'scripts/generate-agents-index.sh'

jobs:
  regenerate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Regenerate AGENTS.md
        run: ./scripts/generate-agents-index.sh
      
      - name: Commit if changed
        run: |
          if [[ -n "$(git status --porcelain AGENTS.md)" ]]; then
            git config user.name "GitHub Actions"
            git config user.email "actions@github.com"
            git add AGENTS.md
            git commit -m "chore: regenerate AGENTS.md [skip ci]"
            git push
          fi
YAML

# Repeat for other repos
cp ~/agent-skills/.github/workflows/regenerate-agents-md.yml ~/prime-radiant-ai/.github/workflows/
# Adjust script path in prime-radiant-ai version
```

---

### Phase 4: Session-Start Automation (1 hour)

**4.1 Enhanced Session-Start Hook**
```bash
cat > ~/canonical-repo-session-start.sh <<'SCRIPT'
#!/bin/bash
# Session-start hook for canonical repo enforcement

# Only run in interactive shells
[[ $- != *i* ]] && return

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 Agent Session Initialized"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in a canonical repo
REPO=$(basename "$PWD" 2>/dev/null)
if [[ "$PWD" =~ (agent-skills|prime-radiant-ai|affordabot|llm-common)$ ]]; then
    echo "⚠️  You're in canonical repo: ~/$REPO"
    echo ""
    
    # Auto-detect issue from branch
    ISSUE_ID=$(git branch --show-current 2>/dev/null | grep -oE 'bd-[a-z0-9]+' | head -1)
    
    if [[ -z "$ISSUE_ID" ]]; then
        # Check for ready issues
        READY_ISSUES=$(bd ready 2>/dev/null | grep -oE 'bd-[a-z0-9]+' | head -3)
        if [[ -n "$READY_ISSUES" ]]; then
            echo "📋 Ready issues:"
            echo "$READY_ISSUES" | while read issue; do
                echo "   - $issue"
            done
            echo ""
            echo "💡 Start work: dx-worktree create <issue-id> $REPO"
        else
            echo "💡 No ready issues. Create one:"
            echo "   bd create 'your task description'"
        fi
    else
        # Auto-create worktree
        WORKTREE_PATH="/tmp/agents/$ISSUE_ID/$REPO"
        
        if [[ ! -d "$WORKTREE_PATH" ]]; then
            echo "✅ Creating worktree for $ISSUE_ID..."
            dx-worktree create "$ISSUE_ID" "$REPO" >/dev/null 2>&1
        fi
        
        if [[ -d "$WORKTREE_PATH" ]]; then
            cd "$WORKTREE_PATH"
            echo ""
            echo "📂 Working directory: $WORKTREE_PATH"
            echo "✅ Safe to commit here"
        fi
    fi
fi

# Show current context
echo ""
echo "Environment:"
if git rev-parse --git-dir 2>/dev/null | grep -q worktrees; then
    echo "  ✅ Worktree (safe to commit)"
else
    if [[ "$PWD" =~ (agent-skills|prime-radiant-ai|affordabot|llm-common) ]]; then
        echo "  ⚠️  Canonical repo (read-only)"
    else
        echo "  ✅ Development repo (safe to commit)"
    fi
fi

echo "  Branch: $(git branch --show-current 2>/dev/null || echo 'N/A')"
echo "  Repo: $(basename $(git rev-parse --show-toplevel 2>/dev/null || echo $PWD))"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SCRIPT

chmod +x ~/canonical-repo-session-start.sh
```

**4.2 Deploy to All VMs**
```bash
# Copy to all VMs
scp ~/canonical-repo-session-start.sh fengning@macmini:~/
scp ~/canonical-repo-session-start.sh feng@epyc6:~/

# Add to .bashrc on all VMs
for vm in homedesktop-wsl macmini epyc6; do
    ssh $vm "grep -q 'canonical-repo-session-start.sh' ~/.bashrc || echo 'source ~/canonical-repo-session-start.sh' >> ~/.bashrc"
done
```

**4.3 IDE-Specific Hooks**

**Windsurf/Cursor:**
```bash
# Add to .windsurf/settings.json
cat > ~/.windsurf/settings.json <<'JSON'
{
  "cascade.sessionStart": {
    "script": "~/canonical-repo-session-start.sh"
  }
}
JSON
```

**Claude Code (OpenCode):**
```bash
# Add to .opencode/config.yml (if exists)
cat > ~/.opencode/config.yml <<'YAML'
session_hooks:
  on_start: ~/canonical-repo-session-start.sh
YAML
```

---

### Phase 5: Upgrade to Hourly Sync (15 min)

**5.1 Update Crontabs**
```bash
# homedesktop-wsl
crontab -e
# Change: 0 3 * * * → 0 * * * *
# Result: Runs every hour at :00

# macmini
ssh fengning@macmini 'crontab -e'
# Change: 5 3 * * * → 5 * * * *
# Result: Runs every hour at :05

# epyc6
ssh feng@epyc6 'crontab -e'
# Change: 10 3 * * * → 10 * * * *
# Result: Runs every hour at :10
```

**5.2 Verify Cron Logs**
```bash
# Check logs after 1 hour
tail -f ~/logs/canonical-sync.log
```

---

### Phase 6: Enhanced dx-check (15 min)

**6.1 Add Worktree Status Check**
```bash
# Find dx-check.sh
find ~/agent-skills -name "dx-check.sh" -o -name "dx_doctor.sh"

# Add to end of dx-check.sh
cat >> ~/agent-skills/scripts/dx-check.sh <<'SCRIPT'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Workspace Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if git rev-parse --git-dir 2>/dev/null | grep -q worktrees; then
    echo "✅ Worktree (safe to commit)"
    echo "   Path: $PWD"
    echo "   Branch: $(git branch --show-current)"
else
    REPO=$(basename "$PWD" 2>/dev/null)
    if [[ "$PWD" =~ (agent-skills|prime-radiant-ai|affordabot|llm-common)$ ]]; then
        echo "⚠️  Canonical repo (read-only)"
        echo "   Use: dx-worktree create bd-xxx $REPO"
    else
        echo "✅ Development repo (safe to commit)"
    fi
fi
SCRIPT
```

---

### Phase 7: Deploy to All VMs (1 hour)

**7.1 Package All Scripts**
```bash
cd ~/agent-skills
tar czf /tmp/canonical-enforcement.tar.gz \
    scripts/generate-agents-index.sh \
    scripts/canonical-pre-commit-hook.sh \
    fragments/ \
    ~/canonical-repo-session-start.sh \
    ~/canonical-sync.sh \
    ~/repo-status.sh
```

**7.2 Deploy to macmini**
```bash
scp /tmp/canonical-enforcement.tar.gz fengning@macmini:/tmp/
ssh fengning@macmini <<'SSH'
cd ~
tar xzf /tmp/canonical-enforcement.tar.gz

# Deploy pre-commit hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/scripts/canonical-pre-commit-hook.sh ~/$repo/.git/hooks/pre-commit
    chmod +x ~/$repo/.git/hooks/pre-commit
done

# Deploy post-commit hooks
cp ~/agent-skills/.git/hooks/post-commit ~/agent-skills/.git/hooks/post-commit
chmod +x ~/agent-skills/.git/hooks/post-commit

# Add to .bashrc
grep -q 'canonical-repo-session-start.sh' ~/.bashrc || echo 'source ~/canonical-repo-session-start.sh' >> ~/.bashrc

# Update crontab (hourly sync + regeneration)
(crontab -l 2>/dev/null | grep -v canonical-sync; echo "5 * * * * ~/canonical-sync.sh") | crontab -
(crontab -l 2>/dev/null | grep -v generate-agents-index; echo "20 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m 'chore: regenerate AGENTS.md [skip ci]' && git push 2>&1 | logger -t agents-md") | crontab -

echo "✅ macmini deployment complete"
SSH
```

**7.3 Deploy to epyc6**
```bash
scp /tmp/canonical-enforcement.tar.gz feng@epyc6:/tmp/
ssh feng@epyc6 <<'SSH'
cd ~
tar xzf /tmp/canonical-enforcement.tar.gz

# Deploy pre-commit hooks
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    cp ~/agent-skills/scripts/canonical-pre-commit-hook.sh ~/$repo/.git/hooks/pre-commit
    chmod +x ~/$repo/.git/hooks/pre-commit
done

# Deploy post-commit hooks
cp ~/agent-skills/.git/hooks/post-commit ~/agent-skills/.git/hooks/post-commit
chmod +x ~/agent-skills/.git/hooks/post-commit

# Add to .bashrc
grep -q 'canonical-repo-session-start.sh' ~/.bashrc || echo 'source ~/canonical-repo-session-start.sh' >> ~/.bashrc

# Update crontab (hourly sync + regeneration)
(crontab -l 2>/dev/null | grep -v canonical-sync; echo "10 * * * * ~/canonical-sync.sh") | crontab -
(crontab -l 2>/dev/null | grep -v generate-agents-index; echo "25 * * * * cd ~/agent-skills && ./scripts/generate-agents-index.sh && git add AGENTS.md && git commit -m 'chore: regenerate AGENTS.md [skip ci]' && git push 2>&1 | logger -t agents-md") | crontab -

echo "✅ epyc6 deployment complete"
SSH
```

---

### Phase 8: Verification (30 min)

**8.1 Verify AGENTS.md Generation**
```bash
# Check line counts
wc -l ~/agent-skills/AGENTS.md  # Should be 300-500
wc -l ~/prime-radiant-ai/AGENTS.md  # Should be 500-700

# Verify <800 line limit
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    lines=$(wc -l ~/$repo/AGENTS.md | cut -d' ' -f1)
    if [[ $lines -gt 800 ]]; then
        echo "❌ $repo AGENTS.md exceeds 800 lines ($lines)"
    else
        echo "✅ $repo AGENTS.md: $lines lines"
    fi
done
```

**8.2 Verify Auto-Update Triggers**
```bash
# Test post-commit hook
cd ~/agent-skills
touch core/test-skill/SKILL.md
git add core/test-skill/SKILL.md
git commit -m "test: trigger AGENTS.md regeneration"
# Expected: AGENTS.md regenerated and amended

# Test cron (wait 1 hour)
# Check logs
tail ~/logs/canonical-sync.log
journalctl -t agents-md | tail -20
```

**8.3 Verify Session-Start Hook**
```bash
# Open new terminal
# Expected: Session-start message appears
# If in canonical repo: Auto-creates worktree or shows ready issues
```

**8.4 Verify Pre-Commit Hook**
```bash
cd ~/agent-skills
echo "test" >> README.md
git add README.md
git commit -m "test: trigger pre-commit hook"
# Expected: Blocked with worktree instructions
```

**8.5 Verify All VMs**
```bash
for vm in homedesktop-wsl macmini epyc6; do
    echo "=== $vm ==="
    ssh $vm "wc -l ~/agent-skills/AGENTS.md"
    ssh $vm "crontab -l | grep -E 'canonical-sync|generate-agents-index'"
    ssh $vm "ls -la ~/agent-skills/.git/hooks/pre-commit ~/agent-skills/.git/hooks/post-commit"
done
```

---

## Success Metrics

### Week 1

**AGENTS.md:**
- ✅ All repos <800 lines
- ✅ Auto-generated from SKILL.md files
- ✅ Updated hourly across all VMs
- ✅ Includes universal + repo-specific skills

**Enforcement:**
- ✅ Zero commits to canonical repos (pre-commit hook blocks)
- ✅ Session-start auto-creates worktrees
- ✅ Hourly sync auto-heals mistakes

**Cognitive Load:**
- ✅ Zero user reminders about worktrees
- ✅ Zero manual AGENTS.md updates
- ✅ Zero manual cleanup

### Week 2

**Agent Compliance:**
- ✅ 100% (impossible to violate)
- ✅ All work in worktrees
- ✅ All canonical repos clean

**Token Efficiency:**
- ✅ 47-58% reduction (749 → 400 lines)
- ✅ Skill discovery maintained (examples included)

### Week 4

**System Health:**
- ✅ All VMs in sync
- ✅ All IDEs enforcing rules
- ✅ Zero manual interventions

---

## Rollback Plan

If issues arise:

**Rollback AGENTS.md generation:**
```bash
# Restore original AGENTS.md
git checkout HEAD~1 AGENTS.md
git commit -m "rollback: restore manual AGENTS.md"
```

**Disable auto-update:**
```bash
# Remove cron jobs
crontab -e
# Comment out regeneration lines

# Remove git hooks
rm ~/agent-skills/.git/hooks/post-commit
```

**Disable session-start hook:**
```bash
# Comment out in .bashrc
sed -i 's/source ~\/canonical-repo-session-start.sh/# source ~\/canonical-repo-session-start.sh/' ~/.bashrc
```

---

## Summary

**Total Implementation Time:** 5-6 hours

**Components:**
1. ✅ AGENTS.md generator (universal + repo-specific)
2. ✅ Auto-update triggers (git hooks + cron + GitHub Actions)
3. ✅ Session-start automation (auto-creates worktrees)
4. ✅ Hourly sync (reduces mistake window to 1 hour)
5. ✅ Enhanced dx-check (shows worktree status)
6. ✅ Multi-VM × Multi-IDE deployment

**Result:**
- **100% agent compliance** (impossible to violate)
- **Zero cognitive load** (system enforces, not user)
- **<800 line AGENTS.md** (token efficient, high discoverability)
- **Always in sync** (auto-generated from SKILL.md)
- **Scales to 200+ skills** (hybrid format maintains <800 lines)

**Ready to proceed?**
