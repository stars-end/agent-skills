# Cross-Repo Skill Consistency Implementation Plan

**Epic**: `agent-skills-aro`
**Reviewer**: Human (code review only)
**Implementer**: Dev agent (autonomous execution)

---

## Executive Summary

Standardize context skill locations across 3 product repos:
- **prime-radiant-ai**: Migrate `.agent/knowledge/` → `.claude/skills/`
- **affordabot**: Remove duplicated global skills
- **llm-common**: Add basic context skills

**Scope**:
- 3 repos × 3 VMs × 4 agent IDEs
- GitHub Actions auto-update in all repos
- Rollout via git push + ru sync

---

## Pre-Implementation Checklist

```bash
# 1. Verify access to all repos
ls ~/prime-radiant-ai ~/affordabot ~/llm-common

# 2. Verify git status is clean in all repos
cd ~/prime-radiant-ai && git status
cd ~/affordabot && git status
cd ~/llm-common && git status

# 3. Pull latest from all repos
cd ~/prime-radiant-ai && git pull --rebase
cd ~/affordabot && git pull --rebase
cd ~/llm-common && git pull --rebase

# 4. Verify agent-skills is synced
cd ~/agent-skills && git pull --rebase && bd sync
```

---

## Phase 1: Audit Current State

### Task 1.1: Document Current Skill Locations (aro.1)

**Run audit commands:**

```bash
echo "=== prime-radiant-ai ==="
echo "Location: .agent/knowledge/"
ls -la ~/prime-radiant-ai/.agent/knowledge/ 2>/dev/null | wc -l
ls ~/prime-radiant-ai/.agent/knowledge/ 2>/dev/null

echo -e "\n=== affordabot ==="
echo "Location: .claude/skills/"
ls -la ~/affordabot/.claude/skills/ 2>/dev/null | wc -l
ls ~/affordabot/.claude/skills/ 2>/dev/null

echo -e "\n=== llm-common ==="
ls ~/llm-common/.claude/skills/ 2>/dev/null || ls ~/llm-common/.agent/ 2>/dev/null || echo "No skills directory"

echo -e "\n=== GitHub Actions ==="
ls ~/prime-radiant-ai/.github/workflows/*context*.yml 2>/dev/null
ls ~/affordabot/.github/workflows/*context*.yml 2>/dev/null
ls ~/llm-common/.github/workflows/*context*.yml 2>/dev/null
```

**Document findings in a table:**

| Repo | Location | Skill Count | Pattern | GitHub Actions |
|------|----------|-------------|---------|----------------|
| prime-radiant-ai | `.agent/knowledge/` | 16 | `context_*.md` | ✅ pr-context-update.yml |
| affordabot | `.claude/skills/` | 29 | `context-*/SKILL.md` | ❓ |
| llm-common | (none) | 0 | N/A | ❌ |

**Mark complete:**
```bash
bd update agent-skills-aro.1 --status closed --reason "Audit complete: [SUMMARY]"
```

### Task 1.2: Identify Duplicated Skills in affordabot (aro.2)

**Find duplicates:**

```bash
# List affordabot skills
echo "=== affordabot skills ==="
ls ~/affordabot/.claude/skills/

# Compare with agent-skills core/
echo -e "\n=== Potential duplicates (exist in both) ==="
for skill in beads-workflow create-pull-request finish-feature area-context-create skill-creator docs-create parallelize-cloud-work; do
  if [ -d ~/affordabot/.claude/skills/$skill ] && [ -d ~/agent-skills/core/$skill -o -d ~/agent-skills/search/$skill -o -d ~/agent-skills/extended/$skill ]; then
    echo "DUPLICATE: $skill"
  fi
done
```

**Expected duplicates:**
- `beads-workflow` (duplicate of `core/beads-workflow`)
- `create-pull-request` (duplicate of `core/create-pull-request`)
- `finish-feature` (duplicate of `core/finish-feature`)
- `area-context-create` (duplicate of `search/area-context-create`)
- `skill-creator` (duplicate of `extended/skill-creator`)
- `docs-create` (duplicate of `search/docs-create`)
- `parallelize-cloud-work` (duplicate of `extended/parallelize-cloud-work`)

**Verify they are true duplicates:**
```bash
# Compare a sample
diff ~/affordabot/.claude/skills/beads-workflow/SKILL.md ~/agent-skills/core/beads-workflow/SKILL.md
```

**Mark complete:**
```bash
bd update agent-skills-aro.2 --status closed --reason "Identified [N] duplicates: [LIST]"
```

---

## Phase 2: Migrate prime-radiant-ai (aro.3)

**Goal**: Convert `.agent/knowledge/context_*.md` to `.claude/skills/context-*/SKILL.md`

### Step 2.1: Create Directory Structure

```bash
cd ~/prime-radiant-ai

# Create .claude/skills/ directory
mkdir -p .claude/skills

# List files to migrate
ls .agent/knowledge/context_*.md
```

### Step 2.2: Migration Script

Create and run this migration script:

```bash
cd ~/prime-radiant-ai

# Migration script
for file in .agent/knowledge/context_*.md; do
  # Extract name: context_database_schema.md -> database-schema
  basename=$(basename "$file" .md)
  name=${basename#context_}  # Remove context_ prefix
  name=${name//_/-}          # Replace _ with -

  skill_dir=".claude/skills/context-$name"

  echo "Migrating: $file -> $skill_dir/SKILL.md"

  # Create directory
  mkdir -p "$skill_dir"

  # Check if file already has frontmatter
  if head -1 "$file" | grep -q "^---"; then
    # Already has frontmatter, just copy
    cp "$file" "$skill_dir/SKILL.md"
  else
    # Add frontmatter
    {
      echo "---"
      echo "name: context-$name"
      echo "description: Context skill for $name area. Auto-generated from .agent/knowledge/."
      echo "tags: [context, $name]"
      echo "---"
      echo ""
      cat "$file"
    } > "$skill_dir/SKILL.md"
  fi
done
```

### Step 2.3: Handle agents.md Specially

The `.agent/knowledge/agents.md` file is the main CLAUDE.md content, not a context skill:

```bash
# Don't migrate agents.md as a skill - it's different
# Just verify it stays in place or is referenced correctly
ls -la ~/prime-radiant-ai/.agent/knowledge/agents.md
```

### Step 2.4: Update CLAUDE.md References

Check if CLAUDE.md references `.agent/knowledge/`:

```bash
grep -n "\.agent/knowledge" ~/prime-radiant-ai/CLAUDE.md
```

If found, update to reference `.claude/skills/`.

### Step 2.5: Create Backwards Compatibility Symlink (Optional)

```bash
# Optional: Keep old path working temporarily
# ln -s ../.claude/skills ~/prime-radiant-ai/.agent/knowledge-new
# (Skip if you want a clean break)
```

### Step 2.6: Commit and Push

```bash
cd ~/prime-radiant-ai

git add .claude/skills/
git status

git commit -m "refactor: migrate context skills to .claude/skills/ (aro.3)

Migrated 16 context files from .agent/knowledge/ to .claude/skills/context-*/SKILL.md:
- Follows agentskills.io specification
- Consistent with affordabot structure
- Enables standardized skill discovery

Part of Cross-Repo Skill Consistency epic (agent-skills-aro)"

git push
```

**Mark complete:**
```bash
bd update agent-skills-aro.3 --status closed --reason "Migrated 16 context skills to .claude/skills/"
```

---

## Phase 3: Clean Up affordabot (aro.4)

**Goal**: Remove duplicated global skills, keep repo-specific context-* skills.

### Step 3.1: Identify Skills to Remove

```bash
cd ~/affordabot

# Skills to REMOVE (duplicates of agent-skills):
TO_REMOVE=(
  "beads-workflow"
  "create-pull-request"
  "finish-feature"
  "area-context-create"
  "skill-creator"
  "docs-create"
  "parallelize-cloud-work"
  "backend-engineer"  # Check if this is a duplicate
)

# Skills to KEEP (repo-specific context):
# context-admin-ui
# context-analytics
# context-api-contracts
# context-database-schema
# context-dx-meta
# context-infrastructure
# context-llm-pipeline
# context-scrapers
# context-security-resolver
# context-testing-infrastructure
# context-ui-design
```

### Step 3.2: Remove Duplicates

```bash
cd ~/affordabot

# Remove duplicates (VERIFY EACH ONE FIRST)
for skill in beads-workflow create-pull-request finish-feature area-context-create skill-creator docs-create parallelize-cloud-work; do
  if [ -d ".claude/skills/$skill" ]; then
    echo "Removing duplicate: $skill"
    rm -rf ".claude/skills/$skill"
  fi
done

# List what remains
ls .claude/skills/
```

### Step 3.3: Verify Only Context Skills Remain

```bash
# Should only see context-* directories
ls ~/affordabot/.claude/skills/ | grep -v "^context-"
# If anything shows up, investigate before removing
```

### Step 3.4: Commit and Push

```bash
cd ~/affordabot

git add -A .claude/skills/
git status

git commit -m "refactor: remove duplicated global skills (aro.4)

Removed skills that duplicate agent-skills:
- beads-workflow (use core/beads-workflow)
- create-pull-request (use core/create-pull-request)
- finish-feature (use core/finish-feature)
- area-context-create (use search/area-context-create)
- skill-creator (use extended/skill-creator)
- docs-create (use search/docs-create)
- parallelize-cloud-work (use extended/parallelize-cloud-work)

Kept repo-specific context-* skills (11 total).

Part of Cross-Repo Skill Consistency epic (agent-skills-aro)"

git push
```

**Mark complete:**
```bash
bd update agent-skills-aro.4 --status closed --reason "Removed 7 duplicate skills, kept 11 context-* skills"
```

---

## Phase 4: Add Skills to llm-common (aro.5)

**Goal**: Create basic context skills for llm-common.

### Step 4.1: Analyze llm-common Structure

```bash
cd ~/llm-common

# Understand the codebase
find . -name "*.py" -type f | grep -v __pycache__ | head -20
ls -la src/ 2>/dev/null || ls -la */
```

### Step 4.2: Create Skill Directories

```bash
cd ~/llm-common

mkdir -p .claude/skills/context-providers
mkdir -p .claude/skills/context-abstractions
mkdir -p .claude/skills/context-testing
```

### Step 4.3: Create context-providers Skill

```bash
cat > ~/llm-common/.claude/skills/context-providers/SKILL.md << 'EOF'
---
name: context-providers
description: |
  LLM provider implementations (OpenAI, Anthropic, Zhipu/GLM).
  Use when adding new providers, debugging provider issues, or understanding provider interfaces.
  Keywords: provider, openai, anthropic, zhipu, glm, llm, api
tags: [context, providers, llm]
---

# LLM Providers Context

## Overview
Provider implementations for different LLM APIs.

## Key Files
- `src/providers/` or `llm_common/providers/` - Provider implementations
- Look for classes inheriting from `BaseProvider`

## Adding a New Provider
1. Create new file in providers/
2. Implement BaseProvider interface
3. Register in provider factory
4. Add tests

## Common Patterns
- All providers implement `complete()` and `stream()` methods
- Configuration via environment variables or constructor args
- Error handling wraps provider-specific exceptions
EOF
```

### Step 4.4: Create context-abstractions Skill

```bash
cat > ~/llm-common/.claude/skills/context-abstractions/SKILL.md << 'EOF'
---
name: context-abstractions
description: |
  Core LLM interfaces and abstractions (BaseProvider, Message, Response).
  Use when understanding the library architecture or extending base classes.
  Keywords: interface, abstract, base, message, response, schema
tags: [context, abstractions, architecture]
---

# LLM Abstractions Context

## Overview
Core interfaces that all providers implement.

## Key Interfaces
- `BaseProvider` - Abstract base for all providers
- `Message` - Chat message format
- `Response` - Completion response format
- `StreamChunk` - Streaming response chunk

## Design Principles
- Provider-agnostic interfaces
- Strict typing (mypy enforced)
- No business logic - only LLM abstractions
EOF
```

### Step 4.5: Create context-testing Skill

```bash
cat > ~/llm-common/.claude/skills/context-testing/SKILL.md << 'EOF'
---
name: context-testing
description: |
  Test utilities and patterns for llm-common.
  Use when writing tests, understanding test fixtures, or debugging test failures.
  Keywords: test, pytest, mock, fixture, coverage
tags: [context, testing]
---

# Testing Context

## Overview
Test infrastructure for llm-common.

## Running Tests
```bash
make test        # Run all tests
make ci-lite     # Lint + tests
pytest -v        # Verbose output
```

## Test Patterns
- Mock external API calls
- Use fixtures for common provider setups
- Test both sync and async methods
EOF
```

### Step 4.6: Commit and Push

```bash
cd ~/llm-common

git add .claude/skills/
git status

git commit -m "feat: add context skills for llm-common (aro.5)

Added basic context skills:
- context-providers: LLM provider implementations
- context-abstractions: Core interfaces
- context-testing: Test patterns

Follows agentskills.io specification.
Part of Cross-Repo Skill Consistency epic (agent-skills-aro)"

git push
```

**Mark complete:**
```bash
bd update agent-skills-aro.5 --status closed --reason "Added 3 context skills to llm-common"
```

---

## Phase 5: GitHub Actions (aro.6, aro.7)

### Task 5.1: Verify/Add to affordabot (aro.6)

```bash
# Check if affordabot has the workflow
ls ~/affordabot/.github/workflows/*context*.yml

# If missing, copy from prime-radiant-ai
if [ ! -f ~/affordabot/.github/workflows/_context-update.yml ]; then
  cp ~/prime-radiant-ai/.github/workflows/_context-update.yml ~/affordabot/.github/workflows/
fi

if [ ! -f ~/affordabot/.github/workflows/pr-context-update.yml ]; then
  cp ~/prime-radiant-ai/.github/workflows/pr-context-update.yml ~/affordabot/.github/workflows/
fi

# Commit if changes made
cd ~/affordabot
git add .github/workflows/
git status
# If changes:
git commit -m "ci: add context update workflows (aro.6)"
git push
```

**Mark complete:**
```bash
bd update agent-skills-aro.6 --status closed --reason "[Verified existing / Added new]"
```

### Task 5.2: Add to llm-common (aro.7)

```bash
cd ~/llm-common

# Create workflows directory if needed
mkdir -p .github/workflows

# Copy workflows from prime-radiant-ai
cp ~/prime-radiant-ai/.github/workflows/_context-update.yml .github/workflows/
cp ~/prime-radiant-ai/.github/workflows/pr-context-update.yml .github/workflows/

# Verify ANTHROPIC_AUTH_TOKEN secret exists in repo settings
# (Manual step - check GitHub repo settings)

git add .github/workflows/
git commit -m "ci: add context update workflows (aro.7)

Added:
- _context-update.yml (reusable workflow)
- pr-context-update.yml (trigger on PR merge)

Requires ANTHROPIC_AUTH_TOKEN secret in repo settings.
Part of Cross-Repo Skill Consistency epic (agent-skills-aro)"

git push
```

**Mark complete:**
```bash
bd update agent-skills-aro.7 --status closed --reason "Added GitHub Actions workflows"
```

---

## Phase 6: Documentation (aro.8, aro.9)

### Task 6.1: Update CLAUDE.md in All Repos (aro.8)

**Add this section to each repo's CLAUDE.md:**

```markdown
---

## Skills Architecture

### Global Skills (in ~/.agent/skills)
Workflow and utility skills from agent-skills repo:
- `core/beads-workflow` - Issue tracking
- `core/sync-feature-branch` - Git workflow
- `core/create-pull-request` - PR creation
- `dispatch/multi-agent-dispatch` - Cross-VM dispatch
- `health/bd-doctor` - Diagnostics

### Repo-Specific Context (in .claude/skills/)
Domain knowledge skills specific to THIS repo:
[CUSTOMIZE FOR EACH REPO]

**Auto-Update**: Context skills are automatically updated via GitHub Actions when PRs are merged.

---
```

**Customize for each repo:**

**prime-radiant-ai:**
```markdown
### Repo-Specific Context (in .claude/skills/)
- `context-database-schema` - Supabase schema, migrations
- `context-brokerage` - Brokerage integrations
- `context-clerk-integration` - Auth system
- `context-plaid-integration` - Banking connections
- `context-snaptrade-integration` - Trading API
- `context-infrastructure` - Railway deployment
- `context-api-contracts` - API interfaces
- `context-ui-design` - Frontend patterns
```

**affordabot:**
```markdown
### Repo-Specific Context (in .claude/skills/)
- `context-admin-ui` - Admin dashboard
- `context-analytics` - Analytics pipeline
- `context-database-schema` - Database structure
- `context-llm-pipeline` - LLM orchestration
- `context-scrapers` - Data scraping
- `context-security-resolver` - Security features
- `context-infrastructure` - Deployment config
```

**llm-common:**
```markdown
### Repo-Specific Context (in .claude/skills/)
- `context-providers` - LLM provider implementations
- `context-abstractions` - Core interfaces
- `context-testing` - Test patterns
```

**Commit to each repo:**
```bash
for repo in prime-radiant-ai affordabot llm-common; do
  cd ~/$repo
  git add CLAUDE.md
  git commit -m "docs: add Skills Architecture section to CLAUDE.md (aro.8)"
  git push
done
```

**Mark complete:**
```bash
bd update agent-skills-aro.8 --status closed --reason "Updated CLAUDE.md in all 3 repos"
```

### Task 6.2: Update agent-skills AGENTS.md (aro.9)

**Add this section to ~/agent-skills/AGENTS.md:**

```markdown
---

## Product Repo Integration

agent-skills provides **global workflow skills**. Product repos have **repo-specific context skills**.

### Architecture

```
~/.agent/skills (symlink) → ~/agent-skills
├── core/           → Workflow skills (beads, sync, PR)
├── dispatch/       → Cross-VM dispatch
├── health/         → Diagnostics
└── ...

~/prime-radiant-ai/.claude/skills/
├── context-database-schema/  → Repo-specific
├── context-brokerage/        → Repo-specific
└── ...
```

### Repo Summary

| Repo | Context Location | Skills | Auto-Update |
|------|-----------------|--------|-------------|
| prime-radiant-ai | `.claude/skills/context-*/` | 16 | ✅ pr-context-update.yml |
| affordabot | `.claude/skills/context-*/` | 11 | ✅ pr-context-update.yml |
| llm-common | `.claude/skills/context-*/` | 3 | ✅ pr-context-update.yml |

### Creating New Context Skills

Use `search/area-context-create` skill to generate new context skills:
```
/skill search/area-context-create
```

This analyzes codebase areas and generates SKILL.md files with proper structure.

---
```

**Commit:**
```bash
cd ~/agent-skills
git add AGENTS.md
git commit -m "docs: add Product Repo Integration section (aro.9)"
git push
bd sync
```

**Mark complete:**
```bash
bd update agent-skills-aro.9 --status closed --reason "Added Product Repo Integration docs"
```

---

## Phase 7: Rollout (aro.10)

### Step 7.1: Sync All VMs

```bash
# On homedesktop-wsl (or via SSH from current machine)
ssh fengning@homedesktop-wsl "cd ~/agent-skills && git pull && cd ~/prime-radiant-ai && git pull && cd ~/affordabot && git pull && cd ~/llm-common && git pull"

# On macmini
ssh fengning@macmini "cd ~/agent-skills && git pull && cd ~/prime-radiant-ai && git pull && cd ~/affordabot && git pull && cd ~/llm-common && git pull"

# On epyc6
ssh feng@epyc6 "cd ~/agent-skills && git pull && cd ~/prime-radiant-ai && git pull && cd ~/affordabot && git pull && cd ~/llm-common && git pull"
```

Or use `ru sync`:
```bash
# On each VM
ru sync
```

### Step 7.2: Verify on Each VM

```bash
# Verification script (run on each VM)
echo "=== Checking ~/.agent/skills symlink ==="
ls -la ~/.agent/skills

echo -e "\n=== prime-radiant-ai skills ==="
ls ~/prime-radiant-ai/.claude/skills/ 2>/dev/null | head -10

echo -e "\n=== affordabot skills (should be context-* only) ==="
ls ~/affordabot/.claude/skills/ 2>/dev/null

echo -e "\n=== llm-common skills ==="
ls ~/llm-common/.claude/skills/ 2>/dev/null

echo -e "\n=== dx-check ==="
dx-check
```

**Mark complete:**
```bash
bd update agent-skills-aro.10 --status closed --reason "Synced all 3 VMs, verified skill structure"
```

---

## Phase 8: Verification (aro.11)

### Test Skill Discovery

**Claude Code:**
```bash
# In each repo, test skill discovery
cd ~/affordabot
# Then in Claude Code: /skill context-admin-ui
# Should find repo-specific skill

# Also test global skill
# /skill core/beads-workflow
# Should find from ~/.agent/skills
```

**Document any issues found.**

**Mark complete:**
```bash
bd update agent-skills-aro.11 --status closed --reason "Verified skill discovery in Claude Code. [OTHER IDES: status]"
```

---

## Final Checklist

```bash
# 1. All repos have .claude/skills/ with context-* skills
ls ~/prime-radiant-ai/.claude/skills/
ls ~/affordabot/.claude/skills/
ls ~/llm-common/.claude/skills/

# 2. affordabot has no duplicate global skills
ls ~/affordabot/.claude/skills/ | grep -v "^context-"
# Should return nothing

# 3. GitHub Actions in all repos
ls ~/prime-radiant-ai/.github/workflows/*context*.yml
ls ~/affordabot/.github/workflows/*context*.yml
ls ~/llm-common/.github/workflows/*context*.yml

# 4. All VMs synced
# (Run on each VM)
git -C ~/agent-skills log -1 --oneline
git -C ~/prime-radiant-ai log -1 --oneline
git -C ~/affordabot log -1 --oneline
git -C ~/llm-common log -1 --oneline

# 5. Close epic
bd update agent-skills-aro --status closed --reason "All subtasks complete"
```

---

## Appendix: Skill Mapping After Migration

### prime-radiant-ai

| Old Location | New Location |
|--------------|--------------|
| `.agent/knowledge/context_database_schema.md` | `.claude/skills/context-database-schema/SKILL.md` |
| `.agent/knowledge/context_api_contracts.md` | `.claude/skills/context-api-contracts/SKILL.md` |
| `.agent/knowledge/context_brokerage.md` | `.claude/skills/context-brokerage/SKILL.md` |
| `.agent/knowledge/context_clerk_integration.md` | `.claude/skills/context-clerk-integration/SKILL.md` |
| `.agent/knowledge/context_infrastructure.md` | `.claude/skills/context-infrastructure/SKILL.md` |
| ... (16 total) | ... |

### affordabot

| Action | Skill |
|--------|-------|
| REMOVE | `beads-workflow` (use `core/beads-workflow`) |
| REMOVE | `create-pull-request` (use `core/create-pull-request`) |
| REMOVE | `finish-feature` (use `core/finish-feature`) |
| REMOVE | `area-context-create` (use `search/area-context-create`) |
| REMOVE | `skill-creator` (use `extended/skill-creator`) |
| REMOVE | `docs-create` (use `search/docs-create`) |
| REMOVE | `parallelize-cloud-work` (use `extended/parallelize-cloud-work`) |
| KEEP | `context-admin-ui` |
| KEEP | `context-analytics` |
| KEEP | `context-database-schema` |
| KEEP | ... (11 context-* skills) |

### llm-common

| Action | Skill |
|--------|-------|
| CREATE | `context-providers` |
| CREATE | `context-abstractions` |
| CREATE | `context-testing` |
