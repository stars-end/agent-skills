# Canonical Repository Migration Analysis
## Skills & AGENTS.md Compilation Review

**Date:** 2026-02-01  
**Scope:** Review agent-skills structure, AGENTS.md compilation, and migration needs

---

## Executive Summary

**Good News:** The skills and scripts are already worktree-aware and don't need migration.

**Action Required:** Update AGENTS.md files in all 4 repos to include canonical repository rules.

---

## Part 1: Skills Analysis

### Skills Reviewed

Analyzed 56 skills across categories:
- **core/**: beads-workflow, create-pull-request, feature-lifecycle, finish-feature, fix-pr-feedback, issue-first, merge-pr, session-end, sync-feature-branch
- **extended/**: worktree-workflow, dirty-repo-bootstrap, skill-creator, plan-refine, etc.
- **health/**: bd-doctor, railway-doctor, toolchain-health, etc.
- **infra/**: canonical-targets, devops-dx, vm-bootstrap, etc.
- **railway/**: deploy, database, environment, etc.

### Key Findings

#### ✅ Skills Are Already Worktree-Aware

**Evidence:**

1. **worktree-workflow/SKILL.md** explicitly documents worktree usage:
   ```bash
   dx-worktree create <beads-id> <repo>
   # Returns: /tmp/agents/<beads-id>/<repo>
   ```

2. **Core skills use relative paths** (not hardcoded canonical paths):
   - `sync-feature-branch/SKILL.md`: Uses `git branch --show-current` (works in any repo)
   - `finish-feature/SKILL.md`: Uses `git checkout master` (relative, not `cd ~/repo`)
   - `create-pull-request/SKILL.md`: Uses `gh pr create` (works in current directory)

3. **No hardcoded canonical paths in skills:**
   ```bash
   grep -r "cd ~/agent-skills\|cd ~/prime-radiant-ai" /home/fengning/agent-skills/core/
   # Result: No matches
   ```

4. **Scripts that DO reference canonical paths are infrastructure scripts:**
   - `dx-fleet-status.sh` - Monitoring script (reads canonical repos, doesn't modify)
   - `dx-status.sh` - Status checking (read-only)
   - `verify-event-bus.sh` - Verification script (read-only)
   - `linux-migrate-ubuntu24.sh` - One-time migration script

**Conclusion:** Skills already follow worktree-first pattern. No migration needed.

---

## Part 2: AGENTS.md Compilation Analysis

### Current State

#### agent-skills/AGENTS.md (Master)
- **Location:** `/home/fengning/agent-skills/AGENTS.md`
- **Size:** 750 lines
- **Status:** ✅ Updated with canonical repo rules (commit `1cd3bc1`)
- **Sections:**
  - Nakomi Agent Protocol (decision autonomy, cognitive load)
  - Agent Skills V3 DX (core tools, workflow)
  - **⚠️ CANONICAL REPOSITORY RULES (CRITICAL)** ← Added
  - Quick Start, Session Bootstrap, etc.

#### prime-radiant-ai/AGENTS.md
- **Location:** `/home/fengning/prime-radiant-ai/AGENTS.md`
- **Size:** 101 lines
- **Status:** ❌ Missing canonical repo rules
- **Content:** Duplicated header (appears twice), repo-specific verification cheatsheet
- **Issue:** No canonical repository rules section

#### affordabot/AGENTS.md
- **Location:** `/home/fengning/affordabot/AGENTS.md`
- **Size:** 110 lines
- **Status:** ❌ Missing canonical repo rules
- **Content:** Duplicated header, repo-specific development workflow
- **Issue:** No canonical repository rules section

#### llm-common/AGENTS.md
- **Location:** `/home/fengning/llm-common/AGENTS.md`
- **Size:** 80 lines
- **Status:** ❌ Missing canonical repo rules
- **Content:** Duplicated header, "Landing the Plane" session completion rules
- **Issue:** No canonical repository rules section

### Compilation Process Discovery

**Current compilation appears to be manual/ad-hoc:**

1. **No automated compilation script found:**
   ```bash
   find /home/fengning/agent-skills -name "*compile*" -o -name "*build-agents*"
   # Result: No compilation scripts
   ```

2. **Each repo has independent AGENTS.md:**
   - Not symlinked
   - Not auto-generated
   - Manually maintained with repo-specific content

3. **@AGENTS.md files exist:**
   - `/home/fengning/agent-skills/@AGENTS.md` (41 lines, basic template)
   - `/home/fengning/llm-common/@AGENTS.md` (appears to be old version)
   - Purpose unclear (possibly templates or deprecated)

**Hypothesis:** AGENTS.md files are manually maintained per-repo with:
- **Common header** (from agent-skills/AGENTS.md)
- **Repo-specific sections** (verification, development, rules)

---

## Part 3: Migration Plan

### Goal
Add canonical repository rules to all repo AGENTS.md files without breaking existing content.

### Strategy
**Hybrid approach:** Keep repo-specific AGENTS.md files, but ensure all include canonical repo rules.

### Phase 1: Update Repo AGENTS.md Files (15 min)

#### 1.1 prime-radiant-ai/AGENTS.md
**Action:** Add canonical repo rules section after header

**Changes:**
1. Remove duplicate header (lines 1-16 duplicate lines 19-50)
2. Insert canonical repo rules section (from agent-skills/AGENTS.md lines 60-110)
3. Keep repo-specific verification cheatsheet

**Result:** Unified AGENTS.md with canonical rules + Prime Radiant specifics

#### 1.2 affordabot/AGENTS.md
**Action:** Add canonical repo rules section after header

**Changes:**
1. Remove duplicate header
2. Insert canonical repo rules section
3. Keep repo-specific development workflow

**Result:** Unified AGENTS.md with canonical rules + Affordabot specifics

#### 1.3 llm-common/AGENTS.md
**Action:** Add canonical repo rules section after header

**Changes:**
1. Remove duplicate header
2. Insert canonical repo rules section
3. Keep "Landing the Plane" session completion rules

**Result:** Unified AGENTS.md with canonical rules + LLM Common specifics

### Phase 2: Create Compilation Documentation (10 min)

**Document the AGENTS.md structure:**

```markdown
# AGENTS.md Compilation Pattern

## Structure

Each repo's AGENTS.md follows this pattern:

1. **Universal Header** (from agent-skills/AGENTS.md)
   - Nakomi Agent Protocol
   - Agent Skills V3 DX
   - Canonical Repository Rules ← CRITICAL

2. **Repo-Specific Sections**
   - prime-radiant-ai: Verification cheatsheet, Railway context
   - affordabot: Development workflow, QA patterns
   - llm-common: Session completion rules, shared library rules

## Maintenance

- **Universal sections:** Update in agent-skills/AGENTS.md, then propagate
- **Repo-specific sections:** Update directly in each repo
- **No automation:** Manual sync (intentional, allows repo customization)
```

### Phase 3: Optional - Create Compilation Script (Future)

**Not required now, but could create:**

```bash
#!/bin/bash
# scripts/compile-agents-md.sh
# Compiles AGENTS.md for all repos from templates

HEADER="agent-skills/AGENTS.md:1-200"  # Universal sections
REPOS=(prime-radiant-ai affordabot llm-common)

for repo in "${REPOS[@]}"; do
    # Extract header from agent-skills
    # Append repo-specific sections from @AGENTS.md
    # Write to $repo/AGENTS.md
done
```

**Decision:** Defer this. Manual maintenance is working fine.

---

## Part 4: Skills->AGENTS.md Compilation

### Current Process (Inferred)

**Skills are NOT compiled into AGENTS.md.**

**Evidence:**
1. AGENTS.md is high-level workflow documentation
2. Skills are detailed implementation guides (SKILL.md files)
3. No compilation script exists
4. AGENTS.md references skills by name, doesn't include their content

**Relationship:**
- **AGENTS.md:** "What to do" (workflow, commands, rules)
- **Skills:** "How to do it" (detailed implementation, automation)

**Example:**
```markdown
# AGENTS.md
**Daily Workflow:**
1. `start-feature bd-xxx` - Start work.
2. Code...
3. `sync-feature "message"` - Save work.

# Skills (core/sync-feature-branch/SKILL.md)
## Workflow
### 1. Set Beads Context
### 2. Get Current Issue
### 3. Analyze Diff for Discoveries
... (254 lines of detailed implementation)
```

**Conclusion:** Skills and AGENTS.md are separate layers. No compilation needed.

---

## Part 5: Recommendations

### Immediate Actions (Required)

1. ✅ **Update prime-radiant-ai/AGENTS.md** - Add canonical repo rules
2. ✅ **Update affordabot/AGENTS.md** - Add canonical repo rules
3. ✅ **Update llm-common/AGENTS.md** - Add canonical repo rules
4. ✅ **Document AGENTS.md structure** - Create maintenance guide

### Future Enhancements (Optional)

1. ⚠️ **Create compilation script** - Automate AGENTS.md updates (low priority)
2. ⚠️ **Consolidate @AGENTS.md files** - Clean up template files (low priority)
3. ⚠️ **Add AGENTS.md validation** - CI check for canonical rules presence (nice-to-have)

### Non-Actions (Not Needed)

1. ❌ **Migrate skills** - Already worktree-aware
2. ❌ **Compile skills into AGENTS.md** - Different abstraction layers
3. ❌ **Update infrastructure scripts** - Read-only, no migration needed

---

## Part 6: Implementation Plan

### Step 1: Update prime-radiant-ai/AGENTS.md
```bash
cd ~/prime-radiant-ai
# Edit AGENTS.md:
# - Remove duplicate header (lines 1-16)
# - Insert canonical repo rules after line 17
# - Keep verification cheatsheet
git add AGENTS.md
git commit -m "docs: add canonical repository rules to AGENTS.md"
git push origin master
```

### Step 2: Update affordabot/AGENTS.md
```bash
cd ~/affordabot
# Edit AGENTS.md:
# - Remove duplicate header
# - Insert canonical repo rules
# - Keep development workflow
git add AGENTS.md
git commit -m "docs: add canonical repository rules to AGENTS.md"
git push origin master
```

### Step 3: Update llm-common/AGENTS.md
```bash
cd ~/llm-common
# Edit AGENTS.md:
# - Remove duplicate header
# - Insert canonical repo rules
# - Keep session completion rules
git add AGENTS.md
git commit -m "docs: add canonical repository rules to AGENTS.md"
git push origin master
```

### Step 4: Document AGENTS.md Structure
```bash
cd ~/agent-skills
# Create docs/AGENTS_MD_STRUCTURE.md
# Document compilation pattern and maintenance
git add docs/AGENTS_MD_STRUCTURE.md
git commit -m "docs: document AGENTS.md structure and maintenance"
git push origin master
```

---

## Part 7: Verification

### After Migration

**Check all repos have canonical rules:**
```bash
for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    echo "=== $repo ==="
    grep -A 5 "CANONICAL REPOSITORY RULES" ~/$repo/AGENTS.md
done
```

**Expected output:** All 4 repos show canonical repository rules section

---

## Summary

| Component | Status | Action Required |
|-----------|--------|-----------------|
| **Skills** | ✅ Already worktree-aware | None |
| **agent-skills/AGENTS.md** | ✅ Has canonical rules | None |
| **prime-radiant-ai/AGENTS.md** | ❌ Missing canonical rules | Add section |
| **affordabot/AGENTS.md** | ❌ Missing canonical rules | Add section |
| **llm-common/AGENTS.md** | ❌ Missing canonical rules | Add section |
| **Skills compilation** | N/A (separate layers) | None |
| **AGENTS.md compilation** | Manual (working) | Document process |

**Total work:** 3 AGENTS.md updates + 1 documentation file = ~25 minutes

---

**END OF ANALYSIS**
