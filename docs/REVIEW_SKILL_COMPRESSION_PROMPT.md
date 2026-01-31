# Tech Lead Review: AGENTS.md Skill Compression Proposal

## Context

We operate a multi-repo ecosystem with standardized agent workflows:

| Repo | Purpose | Lines of Code |
|------|---------|---------------|
| agent-skills | Global DX workflows (issue tracking, PRs, sync) | ~15K |
| prime-radiant-ai | Main product (trading platform) | ~150K |
| affordabot | Bot platform | ~80K |
| llm-common | Shared AI libraries | ~25K |

**Canonical Environment:**
- 3 VMs: homedesktop-wsl, macmini, epyc6
- 4 IDEs: Claude Code, Codex CLI, Antigravity, OpenCode
- 12 possible configurations, all supporting agentskills.io natively

## Current Architecture

### Skills Format (agentskills.io)

We use a standardized skill format:

```
~/agent-skills/core/sync-feature-branch/SKILL.md
.claude/skills/context-analytics/SKILL.md
```

Each skill has metadata (title, purpose, keywords, examples).

### Documentation Hierarchy

**Currently:** AGENTS.md references skills, but skills are the primary source.

```
agent-skills/AGENTS.md (~300 lines)
├── References: "See core/beads-workflow skill"
├── References: "See dispatch/multi-agent-dispatch skill"
└── ...30+ more skills

prime-radiant-ai/AGENTS.md (~100 lines)
├── "Auto-update via GitHub Actions" (references context skills)
└── Skills Index: 16 context skills listed
```

### Auto-Update Mechanism (Current)

**What exists:** `prime-radiant-ai/.github/workflows/pr-context-update.yml`

```yaml
PR Merged → context-router.py (analyze changes)
           → area-context-update (regenerate .claude/skills/context-*/)
           → Commit and push
           → Does NOT update AGENTS.md
```

**Current "auto-update" only updates skill files, NOT AGENTS.md.**

## The Proposal (from Vercel)

### Vercel's Finding

From [Vercel's blog post](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals):

| Format | Pass Rate |
|--------|-----------|
| Compressed AGENTS.md (docs index) | 100% |
| Individual skills (active retrieval) | 79% |

**Why:** Passive context (always available, no retrieval decision) beats active retrieval (requires decision point, ordering issues, context switching).

### Proposed Change

**Before:** AGENTS.md references skills (skills are primary source)

```markdown
## Skills
- Issue tracking: See /skill core/beads-workflow
- Save work: See /skill core/sync-feature-branch
```

**After:** AGENTS.md contains compressed docs index (skills become implementation detail)

```markdown
## Skills Index

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| core/beads-workflow | Issue tracking with dependencies | Every session - create/start/finish issues |
| core/sync-feature-branch | Git workflows with Feature-Key | After code changes - save progress to remote |
| core/create-pull-request | Automated PR creation | When feature complete - create PR with template |
```

The full skill content still exists, but AGENTS.md becomes the primary interface.

## Mechanical Design

### Two Sync Flows Required

#### Flow 1: Global Skills Sync (agent-skills → all repos)

**Trigger:** Changes to agent-skills/AGENTS.md or core/ skill directories

**Mechanism:**

```yaml
# agent-skills/.github/workflows/sync-agents-md.yml

on:
  push:
    branches: [master]
    paths:
      - 'AGENTS.md'
      - 'core/**'
      - 'safety/**'
      - 'health/**'

jobs:
  sync:
    strategy:
      matrix:
        repo: ['prime-radiant-ai', 'affordabot', 'llm-common']
    steps:
      - Checkout agent-skills
      - Checkout target repo (stars-end/${{ matrix.repo }})
      - Extract global skills index from agent-skills/AGENTS.md
      - Merge with target repo's AGENTS.md (preserve repo-specific sections)
      - Create PR: "chore: sync global skills from agent-skills"
```

**Key points:**
- Only triggers on agent-skills changes (not every push)
- Matrix updates all 3 repos in parallel
- Creates PRs (not direct pushes) for visibility
- Preserves repo-specific sections

#### Flow 2: Context Skills Sync (repo context changes → repo AGENTS.md)

**Trigger:** PR merge in product repo

**Mechanism:**

```yaml
# Modify existing: prime-radiant-ai/.github/workflows/_context-update.yml

# After "Update affected contexts" step, add:
- name: Generate compressed AGENTS.md index
  run: |
    python3 scripts/generate-agents-index.py \
      --context-skills .claude/skills/context-*/ \
      --global-index ~/agent-skills/AGENTS.md \
      --output AGENTS.md

- name: Commit AGENTS.md updates
  run: |
    git add AGENTS.md
    git commit -m "docs: update AGENTS.md index" || echo "No changes"
```

**New script: scripts/generate-agents-index.py**

```python
def generate_context_index(context_dir):
    """Scan .claude/skills/context-*/SKILL.md and generate table."""
    skills = []
    for skill_dir in Path(context_dir).glob("context-*/SKILL.md"):
        metadata = parse_skill_metadata(skill_dir)
        skills.append({
            "name": skill_dir.parent.name,
            "title": metadata.get("title"),
            "purpose": metadata.get("purpose"),
            "keywords": metadata.get("keywords", [])
        })
    return render_markdown_table(skills)

def merge_with_global(global_index, context_index, local_agents_md):
    """Merge global + context into local AGENTS.md."""
    # 1. Extract repo-specific sections (preserve)
    # 2. Replace "Skills Index" section with merged global + context
    # 3. Keep all other sections (Verification Cheatsheet, etc.)
    pass
```

### Cross-VM × IDE Consistency

**Important:** No per-VM or per-IDE logic required.

```
Sync happens at GitHub layer (cloud-based)
          │
          ▼
All repos updated (prime-radiant-ai/AGENTS.md, etc.)
          │
          ▼
Developer runs `git pull` on any VM
          │
          ▼
Any IDE reads AGENTS.md from local filesystem
```

**AGENTS.md is just a file.** All 12 configurations (4 IDEs × 3 VMs) read it identically.

## Questions for Review

### Robustness

1. **Is the two-flow design sound?**
   - Flow 1: agent-skills → product repos (global skills)
   - Flow 2: context changes → repo AGENTS.md (context skills)

2. **Are the triggers appropriate?**
   - Global: `on.push` to agent-skills master
   - Context: PR merge in product repo

3. **Is PR-based sync (vs direct push) the right choice?**
   - Pros: Visibility, reviewable, reversible
   - Cons: Requires manual merge, adds latency

4. **What if sync fails partially?** (e.g., 2 of 3 repos updated)

### Architecture

5. **Does this preserve separation of concerns?**
   - agent-skills: Universal workflows
   - Product repos: Domain-specific context

6. **Is "compressed index" the right abstraction?**
   - Table format (Skill | Purpose | When to Use)
   - How much detail is enough?

7. **What about backward compatibility?**
   - Old agents expecting `/skill core/beads-workflow`
   - Do we keep skill files as implementation detail?

### Operations

8. **Who merges the sync PRs?**
   - Auto-merge if no conflicts?
   - Require human review?

9. **How do we detect drift?**
   - Version header in AGENTS.md?
   - Periodic audit job?

10. **What's the rollback strategy?**
    - Revert sync commit?
    - Manual edit?

## Expected Outcome

If approved, this would:

1. **Improve agent reliability** (Vercel: 100% vs 79% pass rate)
2. **Simplify onboarding** (read one file instead of exploring skills)
3. **Maintain flexibility** (skills still exist as implementation detail)
4. **Require new automation** (sync flows above)

## Alternatives Considered

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Compressed AGENTS.md (proposed) | High reliability, simple | Requires sync automation |
| B | Keep current (skills as primary) | Works today | Lower pass rate |
| C | Git submodules | Native git sync | Complex for users |
| D | Centralized doc site | Single source of truth | Not in-repo, breaks offline |

## Request

Please review:

1. **Technical soundness** - Will this work? Are there failure modes we haven't considered?
2. **Operational viability** - Can we maintain this? What's the ongoing cost?
3. **Strategic fit** - Does this align with our DX philosophy?

Provide: Approval, rejection, or requested changes with rationale.
