# AGENTS.md Compilation and Maintenance Guide

**Purpose:** Document how AGENTS.md files are structured and maintained across all repositories.

---

## Architecture

### Two-Layer System

**Layer 1: AGENTS.md (High-Level Workflow)**
- Location: Each repo root (`~/agent-skills/AGENTS.md`, `~/prime-radiant-ai/AGENTS.md`, etc.)
- Purpose: Workflow documentation, commands, rules, quick reference
- Audience: Agents starting work, session initialization
- Size: 80-750 lines (concise)

**Layer 2: Skills (Detailed Implementation)**
- Location: `~/agent-skills/core/*/SKILL.md`, `~/agent-skills/extended/*/SKILL.md`, etc.
- Purpose: Step-by-step automation, detailed procedures
- Audience: Skill execution engine, deep implementation details
- Size: 50-600 lines per skill (comprehensive)

**Relationship:** AGENTS.md references skills by name; skills provide implementation details.

---

## AGENTS.md Structure Pattern

Each repo's AGENTS.md follows this pattern:

```markdown
# AGENTS.md — [Repo Name] V3 DX

## Part 1: Universal Sections (from agent-skills)
1. Nakomi Agent Protocol
   - Decision autonomy tiers (T0-T3)
   - Cognitive load principles
   - Intervention rules

2. Agent Skills V3 DX
   - Core tools (Beads, Skills)
   - Daily workflow
   - Quick start commands

3. ⚠️ CANONICAL REPOSITORY RULES (CRITICAL)
   - List of canonical repos
   - Worktree workflow
   - Pre-commit hook behavior
   - Recovery procedures

## Part 2: Repo-Specific Sections
- prime-radiant-ai: Verification cheatsheet, Railway context, DX bootstrap
- affordabot: Development workflow, QA patterns, make targets
- llm-common: Session completion rules, shared library constraints
- agent-skills: Skills architecture, global skills documentation
```

---

## Maintenance Process

### Updating Universal Sections

**When to update:**
- New canonical repository rules
- Changes to core workflow (Beads, Skills)
- Updates to Nakomi protocol

**Process:**
1. Update `~/agent-skills/AGENTS.md` (master copy)
2. Propagate changes to other repos:
   ```bash
   # Extract universal sections (lines 1-200 typically)
   # Manually copy to each repo's AGENTS.md
   # Preserve repo-specific sections
   ```

**Example:**
```bash
# After updating canonical repo rules in agent-skills/AGENTS.md
cd ~/prime-radiant-ai
# Edit AGENTS.md: Update canonical rules section
git add AGENTS.md
git commit -m "docs: sync canonical repo rules from agent-skills"
git push origin master

# Repeat for affordabot, llm-common
```

### Updating Repo-Specific Sections

**When to update:**
- New repo-specific commands
- Changes to development workflow
- Updates to verification procedures

**Process:**
1. Edit repo's AGENTS.md directly
2. Commit and push
3. No propagation needed (repo-specific)

**Example:**
```bash
cd ~/prime-radiant-ai
# Add new verification target to cheatsheet
git add AGENTS.md
git commit -m "docs: add new verification target"
git push origin master
```

---

## Current State (2026-02-01)

| Repo | AGENTS.md Status | Canonical Rules | Repo-Specific Content |
|------|------------------|-----------------|----------------------|
| **agent-skills** | ✅ Master copy (750 lines) | ✅ Present | Skills architecture, global docs |
| **prime-radiant-ai** | ⚠️ Needs update (101 lines) | ❌ Missing | Verification cheatsheet, Railway |
| **affordabot** | ⚠️ Needs update (110 lines) | ❌ Missing | Development workflow, QA |
| **llm-common** | ⚠️ Needs update (80 lines) | ❌ Missing | Session completion, library rules |

---

## Migration Plan

### Phase 1: Add Canonical Rules to All Repos

**prime-radiant-ai/AGENTS.md:**
```bash
cd ~/prime-radiant-ai
# Remove duplicate header (lines 1-16)
# Insert canonical repo rules section after line 17
# Keep verification cheatsheet and repo-specific content
git add AGENTS.md
git commit -m "docs: add canonical repository rules"
git push origin master
```

**affordabot/AGENTS.md:**
```bash
cd ~/affordabot
# Remove duplicate header
# Insert canonical repo rules section
# Keep development workflow
git add AGENTS.md
git commit -m "docs: add canonical repository rules"
git push origin master
```

**llm-common/AGENTS.md:**
```bash
cd ~/llm-common
# Remove duplicate header
# Insert canonical repo rules section
# Keep session completion rules
git add AGENTS.md
git commit -m "docs: add canonical repository rules"
git push origin master
```

### Phase 2: Verification

**Check all repos:**
```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    echo "=== $repo ==="
    grep -c "CANONICAL REPOSITORY RULES" ~/$repo/AGENTS.md
done
```

**Expected output:** All repos show count = 1

---

## Skills vs AGENTS.md

### Key Differences

| Aspect | AGENTS.md | Skills (SKILL.md) |
|--------|-----------|-------------------|
| **Purpose** | Workflow guide | Implementation details |
| **Audience** | Session start, quick reference | Skill execution engine |
| **Scope** | High-level commands | Step-by-step procedures |
| **Size** | 80-750 lines | 50-600 lines per skill |
| **Location** | Repo root | `~/agent-skills/*/SKILL.md` |
| **Compilation** | Manual sync | No compilation |

### Example Comparison

**AGENTS.md:**
```markdown
**Daily Workflow:**
1. `start-feature bd-xxx` - Start work.
2. Code...
3. `sync-feature "message"` - Save work.
4. `finish-feature` - Verify & PR.
```

**Skills (sync-feature-branch/SKILL.md):**
```markdown
## Workflow

### 1. Set Beads Context
```bash
bd-context
```

### 2. Get Current Issue
```bash
git branch --show-current
# Extract FEATURE_KEY from feature-<KEY> pattern
```

### 3. Analyze Diff for Discoveries
```bash
git diff HEAD
```
... (250 more lines of detailed implementation)
```

**Relationship:** AGENTS.md says "what to do", Skills say "how to do it in detail"

---

## No Automated Compilation

**Current approach:** Manual maintenance

**Rationale:**
1. **Flexibility:** Each repo can customize AGENTS.md
2. **Simplicity:** No build step, no compilation errors
3. **Clarity:** Direct editing, no template indirection
4. **Low churn:** Universal sections change infrequently

**Trade-off:** Manual propagation of universal section updates

**Future option:** Could create compilation script if maintenance burden increases

---

## Template Files (@AGENTS.md)

**Found in:**
- `~/agent-skills/@AGENTS.md` (41 lines, basic template)
- `~/llm-common/@AGENTS.md` (appears to be old version)

**Purpose:** Unclear, possibly:
- Legacy templates
- Deprecated files
- Backup copies

**Recommendation:** Clean up or document purpose in future maintenance pass

---

## Best Practices

### Do

✅ Update agent-skills/AGENTS.md first (master copy)  
✅ Propagate universal sections to other repos  
✅ Keep repo-specific sections unique  
✅ Test canonical repo rules after updates  
✅ Commit AGENTS.md changes with descriptive messages  

### Don't

❌ Duplicate universal content across repos (sync from master)  
❌ Remove repo-specific sections during updates  
❌ Forget to propagate critical rule changes  
❌ Compile skills into AGENTS.md (different layers)  

---

## Verification Commands

**Check canonical rules presence:**
```bash
grep -A 10 "CANONICAL REPOSITORY RULES" ~/*/AGENTS.md
```

**Check for duplicate headers:**
```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    echo "=== $repo ==="
    grep -c "^# AGENTS.md" ~/$repo/AGENTS.md
done
```

**Expected:** Each repo should have 1 main header (not duplicated)

**Check file sizes:**
```bash
wc -l ~/*/AGENTS.md
```

**Expected:** 
- agent-skills: 700-800 lines (master, most comprehensive)
- Other repos: 100-200 lines (universal + repo-specific)

---

## Future Enhancements (Optional)

### Compilation Script (Low Priority)

```bash
#!/bin/bash
# scripts/compile-agents-md.sh

MASTER="~/agent-skills/AGENTS.md"
UNIVERSAL_END_LINE=200  # Adjust as needed

for repo in prime-radiant-ai affordabot llm-common; do
    # Extract universal sections from master
    head -n $UNIVERSAL_END_LINE "$MASTER" > /tmp/universal.md
    
    # Extract repo-specific sections
    tail -n +201 ~/$repo/AGENTS.md > /tmp/repo-specific.md
    
    # Combine
    cat /tmp/universal.md /tmp/repo-specific.md > ~/$repo/AGENTS.md
    
    echo "Updated ~/$repo/AGENTS.md"
done
```

**Decision:** Defer until manual maintenance becomes burdensome

### CI Validation (Nice-to-Have)

```yaml
# .github/workflows/validate-agents-md.yml
name: Validate AGENTS.md

on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check canonical rules present
        run: |
          if ! grep -q "CANONICAL REPOSITORY RULES" AGENTS.md; then
            echo "Error: AGENTS.md missing canonical repository rules"
            exit 1
          fi
```

**Decision:** Defer, manual review sufficient for now

---

## Summary

**Current state:** Manual maintenance, working well  
**Migration needed:** Add canonical rules to 3 repos  
**Compilation:** No automation, intentional flexibility  
**Skills relationship:** Separate layer, no compilation needed  

**Total maintenance time:** ~5 minutes per universal section update

---

**Last Updated:** 2026-02-01  
**Related Docs:**
- `docs/CANONICAL_REPO_MIGRATION_ANALYSIS.md`
- `AGENTS.md` (this repo and all others)
- Skills: `core/*/SKILL.md`, `extended/*/SKILL.md`
