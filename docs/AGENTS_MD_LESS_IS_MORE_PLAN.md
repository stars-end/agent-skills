# AGENTS.md Less Is More Optimization Plan

> **Epic**: bd-v1wm
> **Created**: 2026-02-25
> **Priority**: P0 (Critical DX Improvement)
> **Research Source**: "Less Is More" agent context optimization study

## Executive Summary

Current AGENTS.md is **938 lines** with auto-generated content. Research shows this:
- Reduces success rates by **~3%**
- Increases inference cost by **>20%**
- Stronger models don't generate better context files
- Codebase overviews don't help navigation

**Target**: <100 lines, hand-written, progressive disclosure

---

## Current State Analysis

### Metrics

| File | Lines | Issue |
|------|-------|-------|
| AGENTS.md | 938 | 15x over target |
| docs/ total | ~93,000 | Redundant with AGENTS.md |
| Skill tables | ~400 | Duplicates SKILL.md |
| wooyun-legacy refs | 1.5M+ | Context bloat |

### Problems Identified

#### 1. Auto-Generated Content (Critical)
```markdown
<!-- AUTO-GENERATED -->
<!-- Source SHA: 790fc3190bc645e3b852afaa7076aac474019f6f -->
<!-- Regenerate: make publish-baseline -->
```
**Impact**: -3% success rate, +20% inference cost

#### 2. Skill Tables (400+ lines)
- Duplicates content in individual SKILL.md files
- Agents discover skills via SKILL.md automatically
- Paper: "Codebase overviews don't help navigation"

#### 3. Embedded Code Snippets
- Full command examples that could be pointers
- Paper: "Pointers over copies. Reference file:line"

#### 4. Redundant Documentation
- 12+ AGENTS_MD_*.md files in docs/
- SHARED_DX_CORE.md (298 lines) overlaps with AGENTS.md
- Multiple "implementation plans" that are outdated

#### 5. Large Reference Files
- wooyun-legacy/cases-*.md: 1.5MB total
- Inflates context unnecessarily

---

## Less Is More Principles (From Research)

### ✅ WHAT to Include
1. **Tech stack** - What tools/frameworks are used
2. **Project structure** - What each part does (for monorepos)
3. **Build/test commands** - How to verify changes
4. **Non-obvious tooling** - `uv` instead of `pip`, etc.

### ✅ WHY to Include
1. **Purpose** - What the project does
2. **Intent** - Why decisions were made

### ✅ HOW to Include
1. **Build commands**
2. **Test commands**
3. **Verification steps**

### ❌ What NOT to Include
1. **Detailed codebase overviews** - Agents discover structure
2. **Code style guidelines** - Use linters instead
3. **Task-specific instructions** - Keep in separate files
4. **Auto-generated content** - Hurts more than helps
5. **Directory listings** - Agents can explore

### 📐 Structure Guidelines
1. **<300 lines** (ideal: <60)
2. **Progressive disclosure** - Task-specific docs in separate files
3. **Pointers over copies** - `file:line` references
4. **Hand-written deliberately** - Bad lines cascade

---

## Proposed Architecture

### AGENTS.md (<100 lines)

```markdown
# AGENTS.md — Agent Skills

## What
Skills repository for AI coding agents. Provides:
- Core workflow skills (beads-workflow, create-pull-request, etc.)
- Extended skills (dx-runner, impeccable, etc.)
- Health checks (mcp-doctor, dx-cron, etc.)

## Why
Enable consistent DX across:
- prime-radiant-ai (main app)
- affordabot (Discord bot)
- llm-common (shared library)

## How
- Build: `make publish-baseline`
- Test: `pytest tests/`
- Lint: `ruff check .`

## Canonical Rules
1. Use worktrees: `dx-worktree create bd-xxx agent-skills`
2. Feature-Key required: every commit needs `Feature-Key: bd-xxx`
3. Secrets from 1Password: `op://dev/Agent-Secrets-Production/<FIELD>`

## Progressive Disclosure
- Running tests: agent_docs/running_tests.md
- Dispatch workflows: agent_docs/dispatch_workflows.md
- Secrets management: agent_docs/secrets_management.md

## Skill Discovery
Auto-loaded from: {core,extended,health,infra,railway,dispatch}/*/SKILL.md
```

### Progressive Disclosure Structure

```
agent-skills/
├── AGENTS.md              # <100 lines, core context
├── agent_docs/            # Task-specific guides
│   ├── running_tests.md   # How to run tests
│   ├── dispatch_workflows.md  # Parallel dispatch patterns
│   ├── secrets_management.md  # 1Password + Railway
│   └── beads_operations.md    # Beads commands reference
├── core/*/SKILL.md        # Core workflow skills
├── extended/*/SKILL.md    # Extended skills
└── docs/                  # Reference docs (not context)
```

---

## Implementation Plan

### Phase 1: Audit (bd-v1wm.1)
- [ ] Count lines in all context files
- [ ] Identify auto-generated content
- [ ] Map redundant documentation
- [ ] Output: audit-report.md

### Phase 2: Redesign (bd-v1wm.2)
- [ ] Draft <100 line AGENTS.md
- [ ] Create agent_docs/ structure
- [ ] Define progressive disclosure files
- [ ] Review with team

### Phase 3: Implement (bd-v1wm.3)
- [ ] Replace AGENTS.md
- [ ] Remove auto-generation markers
- [ ] Delete skill tables
- [ ] Update symlinks (CLAUDE.md, GEMINI.md)

### Phase 4: Cleanup (bd-v1wm.4)
- [ ] Delete redundant docs/ files
- [ ] Archive old implementation plans
- [ ] Update references

### Phase 5: Progressive Disclosure (bd-v1wm.5)
- [ ] Create agent_docs/running_tests.md
- [ ] Create agent_docs/dispatch_workflows.md
- [ ] Create agent_docs/secrets_management.md
- [ ] Create agent_docs/beads_operations.md

### Phase 6: Optimize Skills (bd-v1wm.6)
- [ ] Audit SKILL.md files >300 lines
- [ ] Extract verbose content to reference files
- [ ] Keep concise guides in SKILL.md

---

## Beads Issues

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| bd-v1wm | AGENTS.md Less Is More Optimization (Epic) | P0 | open |
| bd-v1wm.1 | Audit: Identify context bloat | P0 | open |
| bd-v1wm.2 | Redesign: <100 line template | P0 | open |
| bd-v1wm.3 | Implement: Replace AGENTS.md | P1 | open |
| bd-v1wm.4 | Cleanup: Remove redundant docs | P1 | open |
| bd-v1wm.5 | Restructure: Progressive disclosure | P1 | open |
| bd-v1wm.6 | Optimize: Trim large skill files | P2 | open |

---

## Expected Impact

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| AGENTS.md lines | 938 | <100 | -89% |
| Context tokens | ~30K | ~3K | -90% |
| Inference cost | Baseline | -20% | $ saved |
| Success rate | Baseline | +3% | Quality |

---

## Review Prompt

```markdown
# AGENTS.md Optimization Review

Review the proposed AGENTS.md redesign against these criteria:

## Less Is More Checklist
- [ ] Under 100 lines
- [ ] Hand-written (no auto-generation markers)
- [ ] Includes WHAT (tech stack, structure)
- [ ] Includes WHY (purpose, intent)
- [ ] Includes HOW (build/test commands)
- [ ] No detailed codebase overviews
- [ ] No code style guidelines (use linters)
- [ ] No task-specific instructions (use progressive disclosure)
- [ ] Uses pointers over copies (file:line references)
- [ ] Progressive disclosure for specialized topics

## Specific Questions
1. Is the canonical rules section complete?
2. Are the progressive disclosure pointers clear?
3. Is anything critical missing?
4. Is there any redundancy?
```

---

## References

- Less Is More research (source: user-provided criteria)
- HumanLayer AGENTS.md example (60 lines)
- Current AGENTS.md analysis
