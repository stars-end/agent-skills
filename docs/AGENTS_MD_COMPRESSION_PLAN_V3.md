# AGENTS.md Compression Plan (Version C)

**Epic**: `agent-skills-3vq`
**Goal**: Reduce context pollution by 70%+ while maintaining 100% agent capability.

---

## The Problem (30 seconds)

| Metric | Current | Target |
|--------|---------|--------|
| agent-skills/AGENTS.md | 408 lines / ~12KB | <150 lines / <4KB |
| prime-radiant/CLAUDE.md | 101 lines / ~3KB | <80 lines / <2KB |
| Agent decision points | Skills require invoke | Passive retrieval |

**Why this matters**: Every token of AGENTS.md loads on every turn. 12KB × 50 turns = 600KB of repeated context. Vercel proved compressed indexes beat verbose instructions (100% vs 79% pass rate).

---

## The Solution (2 minutes)

### 1. Two-Tier AGENTS.md

**Tier 1: Inline Index** (~100 lines, always loaded)
- Commands, decision tables, quick reference
- High-density, pipe-delimited format
- Points to Tier 2 for details

**Tier 2: Retrievable Fragments** (on-demand)
- `~/agent-skills/fragments/*.md`
- Full documentation, examples, edge cases
- Agent fetches when index triggers retrieval

### 2. Compression Format

Before (50 tokens):
```markdown
## When to Create Issues
Before starting any work, you should create a tracking issue using the Beads CLI.
Run `bd create "title" --type task` to create a new issue. This allows you to track
your work and enables other agents to see what you're doing...
```

After (12 tokens):
```markdown
| Task | Command | Fragment |
| Create issue | `bd create "title"` | [→ beads-workflow] |
```

### 3. Retrieval Instruction

One line in Tier 1 tells agent when to expand:
```markdown
**Retrieval Rule**: When task matches fragment tag, read `fragments/<tag>.md` first.
```

---

## Implementation (3 Phases)

### Phase 1: Create Fragments (Day 1)
Extract verbose content from AGENTS.md into fragments:

```bash
mkdir -p ~/agent-skills/fragments
```

| Fragment | Source | Tokens Saved |
|----------|--------|--------------|
| `beads-workflow.md` | Lines 42-93 | ~400 |
| `cross-vm-dispatch.md` | Lines 196-270 | ~600 |
| `session-completion.md` | Lines 383-408 | ~200 |
| `safety-tools.md` | Lines 150-165 | ~150 |
| `skill-discovery.md` | Lines 97-148 | ~400 |

### Phase 2: Compress AGENTS.md (Day 1)

Transform `~/agent-skills/AGENTS.md` to this structure:

```markdown
# Agent Skills Protocol

## Quick Reference
| Action | Command | Details |
|--------|---------|---------|
| Check env | `dx-check` | — |
| Create issue | `bd create "title"` | [→ beads] |
| Save work | `sync-feature "msg"` | [→ workflow] |
| Create PR | `finish-feature` | [→ workflow] |
| Cross-VM | `dx-dispatch <vm> "task"` | [→ dispatch] |

## Decision Autonomy
| Tier | Action | Examples |
|------|--------|----------|
| T0 | Proceed | Format, lint, git mechanics |
| T1 | Inform | Refactors, test additions |
| T2 | Propose | Architecture, dependencies |
| T3 | Halt | Irreversible, scope expansion |

## Fragment Index
| Tag | When to Retrieve | Path |
|-----|------------------|------|
| beads | Creating/managing issues | fragments/beads-workflow.md |
| workflow | Git workflow questions | fragments/git-workflow.md |
| dispatch | Cross-VM tasks | fragments/cross-vm-dispatch.md |
| safety | Checking dangerous commands | fragments/safety-tools.md |
| session | Ending work session | fragments/session-completion.md |

**Retrieval Rule**: When task matches tag, read the fragment before proceeding.

## Repo Integration
Global skills: `~/agent-skills/core/`, `extended/`, `dispatch/`
Repo context: `.claude/skills/context-*/`

Auto-discovery: Agents find global skills from ~/agent-skills, repo skills from .claude/skills/.
```

**Result**: ~80 lines vs 408 lines. Same capability, 80% less context.

### Phase 3: Sync to Product Repos (Day 2)

Product repos get even smaller CLAUDE.md:

```markdown
# Prime Radiant DX

## Quick Start
| Action | Command |
|--------|---------|
| Check env | `dx-check` |
| Run tests | `make verify-local` |
| Full E2E | `make verify-dev` |

## Skills
Global: [~/agent-skills/AGENTS.md](link)
Repo: `.claude/skills/context-*/`

## Context Skills
| Skill | When |
|-------|------|
| context-database-schema | Schema/migration changes |
| context-api-contracts | API endpoints |
| context-plaid-integration | Plaid flows |
| context-infrastructure | Railway/CI |

**Rule**: Load relevant context-* skill before domain work.
```

**Result**: ~40 lines vs 101 lines.

---

## Sync Mechanism

### Version Tag
```markdown
<!-- DX_INDEX_VERSION: 2024-01-30-v1 -->
```

### Drift Detection (dx-check)
```bash
# In dx-check, add:
SOURCE_VER=$(grep DX_INDEX_VERSION ~/agent-skills/fragments/GLOBAL_INDEX.md | cut -d: -f2)
TARGET_VER=$(grep DX_INDEX_VERSION ~/current-repo/CLAUDE.md | cut -d: -f2)
[ "$SOURCE_VER" != "$TARGET_VER" ] && echo "⚠️ DX index drift: run dx-sync"
```

### Injection (dx-sync)
```bash
# dx-sync: inject fragment between markers
sed -i '/<!-- BEGIN_DX_INDEX -->/,/<!-- END_DX_INDEX -->/{//!d}' CLAUDE.md
sed -i '/<!-- BEGIN_DX_INDEX -->/r ~/agent-skills/fragments/GLOBAL_INDEX.md' CLAUDE.md
```

---

## What We're NOT Doing

1. **8-phase rollout** - Overkill for 3 repos
2. **Complex migration scripts** - Just edit the files
3. **Backwards compatibility symlinks** - Clean break
4. **Per-IDE configuration** - All IDEs read same files
5. **Elaborate directory moves** - Files stay where they are

---

## Verification Checklist

```bash
# After compression:
wc -l ~/agent-skills/AGENTS.md          # Should be <150
wc -l ~/prime-radiant-ai/CLAUDE.md      # Should be <80
ls ~/agent-skills/fragments/            # Should have 5-6 files

# Agent test:
# 1. Start fresh session in prime-radiant-ai
# 2. Ask: "How do I dispatch work to another VM?"
# 3. Agent should: read AGENTS.md → see [→ dispatch] → read fragment → answer correctly
```

---

## Decision Points for Review

1. **Retrieval trigger**: Should agents auto-read fragments, or only when prompted?
   - Recommendation: Auto-read when task matches tag (passive > active)

2. **Fragment granularity**: 5 large fragments or 15 small ones?
   - Recommendation: 5-6 large (less retrieval overhead)

3. **Product repo CLAUDE.md**: Include inline index or just point to agent-skills?
   - Recommendation: Minimal inline + pointer (repo-specific context only)

---

## Timeline

| Day | Task | Owner |
|-----|------|-------|
| 1 | Create fragments, compress AGENTS.md | Agent |
| 1 | Test in single repo | Agent |
| 2 | Roll out to prime-radiant, affordabot | Agent |
| 2 | Update dx-check with drift detection | Agent |

**Total effort**: ~2 hours of agent work, 10 minutes of human review.

---

## Appendix: Token Math

| Document | Before | After | Saved |
|----------|--------|-------|-------|
| agent-skills/AGENTS.md | ~3000 tokens | ~900 tokens | 2100 |
| prime-radiant/CLAUDE.md | ~800 tokens | ~300 tokens | 500 |
| affordabot/CLAUDE.md | ~600 tokens | ~250 tokens | 350 |
| **Per-turn total** | ~4400 tokens | ~1450 tokens | **67% reduction** |

Over 50-turn session: **147,500 tokens saved**.
