# Tech Lead Review: AGENTS.md Skill Alignment System

**Epic**: `agent-skills-3vq`
**Goal**: Improve agent → skill alignment from ~79% to ~100% pass rate.

---

## The Problem (Not Tokens)

When an agent encounters a task, it faces a decision:
> "Should I invoke a skill, or just proceed with what I know?"

This decision point is where 21% of failures occur. The agent either:
1. Doesn't realize a skill exists for this task
2. Invokes the wrong skill
3. Proceeds without the skill and gets it wrong

**Current state:**
```
Agent sees: "create a tracking issue"
Agent thinks: "I know how to do this... or wait, is there a skill?"
Agent decides: [invoke skill | proceed without]
                    ↓              ↓
                  79% pass      ???% pass
```

**Target state:**
```
Agent sees: "create a tracking issue"
AGENTS.md says: "Issue tracking → use beads-workflow"
Agent knows: This matches, I'll use the skill.
Result: 100% pass
```

---

## The Insight (Vercel)

| Approach | Pass Rate | Why |
|----------|-----------|-----|
| Compressed index in AGENTS.md | 100% | No decision point - routing is explicit |
| Skills with active retrieval | 79% | Agent must decide "should I look this up?" |
| Skills without instructions | 53% | Agent doesn't know skills exist |

**The fix isn't compression - it's explicit routing.**

An agent with a clear "when you see X, use Y" map never has to guess.

---

## Proposed Architecture

### 1. Semantic Activation Index

AGENTS.md becomes a routing table that maps **task patterns** to **skills**:

```markdown
## Skill Routing

| When You See | Use This | Why |
|--------------|----------|-----|
| "create issue", "track work", "start feature" | core/beads-workflow | Issue lifecycle management |
| "save work", "commit changes", "sync branch" | core/sync-feature-branch | Git workflow with CI gates |
| "create PR", "ready for review", "merge" | core/create-pull-request | PR creation with templates |
| "dispatch", "another VM", "GPU task" | dispatch/multi-agent-dispatch | Cross-VM coordination |
| "deploy", "railway", "production" | railway/deploy | Railway deployment |
| "security", "auth", "credentials" | context-security-resolver | Security patterns |
| "database", "schema", "migration" | context-database-schema | Supabase schema |
| "plaid", "bank", "account linking" | context-plaid-integration | Plaid flows |
```

**Key difference from current state:**
- Current: "See /skill core/beads-workflow for issue tracking"
- Proposed: "When you see 'create issue' or 'track work', use core/beads-workflow"

The agent doesn't decide IF to use a skill. It pattern-matches and routes.

### 2. Two-Layer System

**Layer 1: Global Routing (in every repo's AGENTS.md)**
- Universal skills from agent-skills
- Same across all repos
- Synced automatically

**Layer 2: Repo-Specific Routing (appended per repo)**
- Context skills specific to that codebase
- Different per repo
- Updated on PR merge

```
prime-radiant-ai/AGENTS.md:
├── [Global Routing Table]     ← From agent-skills, synced
├── [Repo-Specific Routing]    ← From .claude/skills/context-*
└── [Repo-Specific Commands]   ← Verification, deployment, etc.
```

### 3. Activation Keywords

Each skill declares its activation patterns in metadata:

```yaml
# core/beads-workflow/SKILL.md
---
name: beads-workflow
activation:
  - "create issue"
  - "track work"
  - "start feature"
  - "close issue"
  - "issue dependencies"
purpose: Issue lifecycle with dependency tracking
---
```

The sync process extracts these into the routing table.

---

## Sync Mechanism

### Flow 1: Global Skills → All Repos

**Trigger:** Push to agent-skills/master affecting core/, safety/, dispatch/

```yaml
# agent-skills/.github/workflows/sync-skill-routing.yml
on:
  push:
    branches: [master]
    paths:
      - 'core/**/SKILL.md'
      - 'safety/**/SKILL.md'
      - 'dispatch/**/SKILL.md'
      - 'AGENTS.md'

jobs:
  sync:
    strategy:
      matrix:
        repo: [prime-radiant-ai, affordabot, llm-common]
    steps:
      - uses: actions/checkout@v4
        with:
          repository: stars-end/${{ matrix.repo }}
          token: ${{ secrets.REPO_SYNC_TOKEN }}

      - name: Extract global routing table
        run: |
          python3 scripts/extract-skill-routing.py \
            --skills-dir ~/agent-skills \
            --output /tmp/global-routing.md

      - name: Merge into AGENTS.md
        run: |
          python3 scripts/merge-agents-md.py \
            --global-routing /tmp/global-routing.md \
            --target AGENTS.md \
            --preserve-sections "Repo-Specific,Verification,Commands"

      - name: Create PR
        run: |
          gh pr create \
            --title "chore: sync global skill routing from agent-skills" \
            --body "Auto-sync of skill activation patterns."
```

### Flow 2: Context Skills → Repo AGENTS.md

**Trigger:** PR merge in product repo

```yaml
# Extend existing pr-context-update.yml

- name: Update skill routing in AGENTS.md
  run: |
    python3 scripts/update-context-routing.py \
      --context-dir .claude/skills/context-*/ \
      --agents-md AGENTS.md

    git add AGENTS.md
    git commit -m "docs: update context skill routing" || true
```

---

## Implementation

### extract-skill-routing.py

```python
"""Extract activation patterns from skills into routing table."""

from pathlib import Path
import yaml
import re

def extract_activation(skill_path: Path) -> dict:
    """Parse SKILL.md frontmatter for activation keywords."""
    content = skill_path.read_text()

    # Extract YAML frontmatter
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return None

    metadata = yaml.safe_load(match.group(1))
    return {
        'name': metadata.get('name'),
        'activation': metadata.get('activation', []),
        'purpose': metadata.get('purpose', metadata.get('description', ''))
    }

def generate_routing_table(skills_dir: Path) -> str:
    """Generate markdown routing table from all skills."""
    rows = []

    for skill_md in skills_dir.glob('**/SKILL.md'):
        info = extract_activation(skill_md)
        if info and info['activation']:
            patterns = ', '.join(f'"{p}"' for p in info['activation'][:3])
            rows.append(f"| {patterns} | {info['name']} | {info['purpose'][:50]} |")

    header = "| When You See | Use This | Why |\n|--------------|----------|-----|\n"
    return header + '\n'.join(rows)

if __name__ == '__main__':
    import sys
    print(generate_routing_table(Path(sys.argv[1])))
```

### Adding Activation to Existing Skills

For each skill in agent-skills, add activation keywords:

```bash
# Example: Update core/beads-workflow/SKILL.md
```

```yaml
---
name: beads-workflow
activation:
  - "create issue"
  - "track work"
  - "start feature"
  - "finish feature"
  - "issue blocked"
  - "dependency"
purpose: Issue lifecycle management with dependency tracking
---
```

**Effort:** ~30 minutes to add activation keywords to 15-20 skills.

---

## What Changes for Agents

### Before (Decision Required)

```
User: "I need to track this bug"
Agent: [internal] Is there a skill for this? Let me check...
       [internal] I see beads-workflow mentioned... should I use it?
       [internal] I'll just create a git commit message...
Result: Misaligned - bug isn't tracked properly
```

### After (Pattern Match)

```
User: "I need to track this bug"
Agent: [reads AGENTS.md] "track" matches → beads-workflow
       [invokes] /skill core/beads-workflow
       [executes] bd create "Bug: ..." --type bug
Result: Aligned - proper issue created
```

The routing table eliminates the "should I?" decision.

---

## Repo-Specific Routing Example

For prime-radiant-ai, the context skills get their own routing section:

```markdown
## Prime Radiant Context Routing

| When You See | Use This | Why |
|--------------|----------|-----|
| "plaid", "bank link", "institution" | context-plaid-integration | Plaid OAuth flows |
| "snaptrade", "brokerage", "trading" | context-snaptrade-integration | SnapTrade API |
| "schema", "migration", "table" | context-database-schema | Supabase patterns |
| "clerk", "auth", "user session" | context-clerk-integration | Clerk auth |
| "railway", "deploy", "environment" | context-infrastructure | Railway config |
| "holdings", "positions", "portfolio" | context-portfolio | Portfolio management |
| "symbol", "ISIN", "ticker" | context-symbol-resolution | Security identifiers |
```

This is auto-generated from the context skill metadata on each PR merge.

---

## Review Questions

### Alignment

1. **Does explicit routing actually improve pass rate?**
   - Vercel says yes (100% vs 79%)
   - Our hypothesis: pattern-matching beats decision-making

2. **Are activation keywords the right abstraction?**
   - Alternative: Full semantic embedding (overkill for 20 skills?)
   - Alternative: Hierarchical categories (too rigid?)

3. **How specific should patterns be?**
   - Too broad: "work" matches everything
   - Too narrow: "create beads issue" is too specific
   - Recommendation: 3-5 patterns per skill, natural language

### Operations

4. **Who maintains activation keywords?**
   - Proposal: Skill author adds them, PR review validates
   - Risk: Keywords drift from actual usage

5. **How do we measure alignment improvement?**
   - Before/after on sample tasks?
   - Agent session analysis?

6. **What if patterns conflict?**
   - "deploy" could match railway/deploy OR context-infrastructure
   - Resolution: More specific pattern wins, or list both

### Architecture

7. **Should skills still be invokable directly?**
   - Yes - routing is guidance, not restriction
   - `/skill core/beads-workflow` still works

8. **How does this interact with IDE skill discovery?**
   - Claude Code, Codex, etc. have native skill loading
   - Routing table is additive, not replacement

9. **Is two-layer (global + repo) the right split?**
   - Alternative: Single merged file
   - Alternative: Three layers (global, domain, repo)

10. **Should we version the routing table?**
    - Helps with debugging alignment issues
    - `<!-- ROUTING_VERSION: 2024-01-30 -->`

---

## Expected Outcome

| Metric | Current | Target |
|--------|---------|--------|
| Agent → skill alignment | ~79% (estimated) | ~95%+ |
| "Wrong skill" errors | Common | Rare |
| "Skill not used when needed" | Common | Rare |
| Onboarding time for new agent | Read skills | Read AGENTS.md |

**Not measured by tokens saved, measured by correct skill usage.**

---

## Implementation Plan

### Phase 1: Add Activation Keywords (Day 1)
- Add `activation:` to all core/, safety/, dispatch/ skills
- ~20 skills × 2 minutes = 40 minutes

### Phase 2: Build Routing Extractor (Day 1)
- `extract-skill-routing.py` (shown above)
- `merge-agents-md.py` (preserve repo sections)
- Test on agent-skills repo

### Phase 3: Update AGENTS.md (Day 1)
- Generate routing table for agent-skills/AGENTS.md
- Manual review of patterns

### Phase 4: Sync Workflow (Day 2)
- Add GitHub Actions for Flow 1 (global → repos)
- Extend pr-context-update for Flow 2 (context → AGENTS.md)
- Test with dry-run PRs

### Phase 5: Validate (Day 2-3)
- Run sample tasks through agent
- Compare: Does it pick the right skill?
- Adjust patterns based on misses

---

## Alternatives Considered

| Option | Alignment | Maintenance | Complexity |
|--------|-----------|-------------|------------|
| **A: Routing table (proposed)** | High | Medium | Low |
| B: Keep current (skill references) | Low | Low | Low |
| C: Full RAG over skills | High | High | High |
| D: LLM-generated routing | Variable | Low | Medium |

**Recommendation: Option A** - Best alignment/complexity trade-off for a 3-person team.

---

## Request

As tech lead, please review:

1. **Does explicit routing solve the alignment problem?**
2. **Is the two-flow sync architecture sound?**
3. **Are activation keywords maintainable long-term?**

Provide: Approve, reject, or requested changes.
