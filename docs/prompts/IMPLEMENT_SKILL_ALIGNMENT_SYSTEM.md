# Implementation Prompt: AGENTS.md Skill Alignment System

**Epic:** `agent-skills-lq5`
**Ready tasks:** `agent-skills-otb`, `agent-skills-lyq`, `agent-skills-bey`

---

## Context

You're implementing a skill routing system to improve agent→skill alignment from ~79% to ~100% pass rate. The key insight from Vercel's research: agents fail when they have to *decide* whether to invoke a skill. Explicit routing eliminates this decision point.

**Design doc:** `~/agent-skills/docs/AGENTS_MD_ALIGNMENT_V3_REVISED.md`

---

## What You're Building

### Current State
```
compile_agent_context.sh merges:
  ~/agent-skills/AGENTS.md (global)
  + ./AGENTS.local.md (repo-specific)
  = ./AGENTS.md (compiled)
```

### Target State
```
compile_agent_context.sh merges:
  ~/agent-skills/AGENTS.md (global)
  + ./AGENTS.local.md (repo-specific)
  + extracted routing table from skill metadata
  = ./AGENTS.md (compiled, with routing table)
```

The routing table maps **task patterns** to **skills**:

```markdown
## Skill Routing

| When You See | Use This | Why |
|--------------|----------|-----|
| "create issue", "track work" | core/beads-workflow | Issue lifecycle |
| "save work", "sync branch" | core/sync-feature-branch | Git workflow |
| "deploy", "railway" | railway/deploy | Deployment |
```

---

## Tasks

### Task 1: Add activation keywords to core/ skills (agent-skills-otb)

Add `activation:` frontmatter to each skill in `~/agent-skills/core/`:

**Example: core/beads-workflow/SKILL.md**
```yaml
---
name: beads-workflow
activation:
  - "create issue"
  - "track work"
  - "start feature"
  - "finish feature"
  - "close issue"
purpose: Issue lifecycle management with dependency tracking
---

[rest of skill content unchanged]
```

**Skills to update:**
- core/beads-workflow
- core/sync-feature-branch
- core/create-pull-request
- core/finish-feature
- core/issue-first
- core/fix-pr-feedback
- Any other skills in core/

**Guidelines:**
- 3-5 activation patterns per skill
- Use natural language phrases an agent might see in user requests
- Patterns should be distinct (don't overlap with other skills)

### Task 2: Add activation keywords to dispatch/ and safety/ skills (agent-skills-lyq)

Same as Task 1, but for:
- dispatch/multi-agent-dispatch
- safety/dcg-safety
- health/bd-doctor
- health/mcp-doctor
- Any other non-core skills

### Task 3: Extend compile_agent_context.sh (agent-skills-abq)

**Blocked by:** Tasks 1 and 2

Modify `~/agent-skills/scripts/compile_agent_context.sh` to:

1. Extract activation keywords from skill YAML frontmatter
2. Generate a routing table
3. Include it in the compiled AGENTS.md
4. Add context-hash for .claude/skills/ staleness detection

**Implementation sketch:**

```bash
#!/bin/bash
# compile_agent_context.sh (extended)

compile_agent_context() {
    REPO_DIR="${1:-.}"
    GLOBAL_SRC="$HOME/agent-skills/AGENTS.md"
    LOCAL_SRC="$REPO_DIR/AGENTS.local.md"
    CONTEXT_DIR="$REPO_DIR/.claude/skills"
    TARGET="$REPO_DIR/AGENTS.md"

    # Skip if no AGENTS.local.md (repo not opted in)
    [ -f "$LOCAL_SRC" ] || return 0
    [ -f "$GLOBAL_SRC" ] || { echo "❌ Global AGENTS.md not found"; return 1; }

    # Extract routing tables
    GLOBAL_ROUTING=$(extract_skill_routing "$HOME/agent-skills/core" "$HOME/agent-skills/dispatch" "$HOME/agent-skills/safety")

    CONTEXT_ROUTING=""
    if [ -d "$CONTEXT_DIR" ]; then
        CONTEXT_ROUTING=$(extract_skill_routing "$CONTEXT_DIR"/context-*)
    fi

    # Compute hashes for staleness detection
    get_hash() { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1" 2>/dev/null; }

    GLOBAL_HASH=$(get_hash "$GLOBAL_SRC")
    LOCAL_HASH=$(get_hash "$LOCAL_SRC")
    CONTEXT_HASH=$(find "$CONTEXT_DIR" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5sum | cut -d' ' -f1 || echo "none")

    # Write compiled AGENTS.md
    cat > "$TARGET" << EOF
<!-- AUTO-COMPILED AGENTS.md -->
<!-- global-hash:$GLOBAL_HASH local-hash:$LOCAL_HASH context-hash:$CONTEXT_HASH -->
<!-- Source: ~/agent-skills/AGENTS.md + ./AGENTS.local.md + .claude/skills/context-*/ -->
<!-- DO NOT EDIT - edit AGENTS.local.md instead -->

## Skill Routing

When you see these patterns, use the corresponding skill:

### Global Skills
$GLOBAL_ROUTING

### Repo Context Skills
$CONTEXT_ROUTING

---

EOF

    cat "$GLOBAL_SRC" >> "$TARGET"
    echo -e "\n\n---\n\n# REPO-SPECIFIC CONTEXT\n" >> "$TARGET"
    cat "$LOCAL_SRC" >> "$TARGET"

    echo "✅ Compiled: $TARGET"
}

extract_skill_routing() {
    echo "| When You See | Use This | Why |"
    echo "|--------------|----------|-----|"

    for dir in "$@"; do
        [ -d "$dir" ] || continue
        skill_file=$(find "$dir" -name "SKILL.md" -type f 2>/dev/null | head -1)
        [ -f "$skill_file" ] || continue

        # Parse YAML frontmatter
        python3 - "$skill_file" << 'PYEOF'
import sys, re, yaml
from pathlib import Path

content = Path(sys.argv[1]).read_text()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if match:
    try:
        meta = yaml.safe_load(match.group(1))
        if meta and meta.get('activation'):
            patterns = ', '.join(f'"{p}"' for p in meta['activation'][:3])
            name = meta.get('name', Path(sys.argv[1]).parent.name)
            purpose = (meta.get('purpose') or meta.get('description', ''))[:50]
            print(f"| {patterns} | {name} | {purpose} |")
    except:
        pass
PYEOF
    done
}

compile_agent_context "$@"
```

### Task 4: Update dx-check.sh (agent-skills-rm5)

**Blocked by:** Task 3

Extend `~/agent-skills/scripts/dx-check.sh` to include context-hash in staleness check:

```bash
# Add after existing hash checks:

CONTEXT_HASH=$(find ".claude/skills" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5sum | cut -d' ' -f1 || echo "none")
COMPILED_CONTEXT_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'context-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")

if [ "$CONTEXT_HASH" != "$COMPILED_CONTEXT_HASH" ]; then
    echo -e "${BLUE}⚠️  AGENTS.md stale (context changed) - recompiling...${RESET}"
    "${SCRIPT_DIR}/compile_agent_context.sh" .
fi
```

### Task 5 & 6: Create AGENTS.local.md (agent-skills-4em, agent-skills-5qp)

**Blocked by:** Task 3

Create `AGENTS.local.md` in prime-radiant-ai and affordabot with repo-specific content:

**Example: prime-radiant-ai/AGENTS.local.md**
```markdown
# Prime Radiant Local Context

## Verification

| Target | Command | When |
|--------|---------|------|
| Local | `make verify-local` | Before commit |
| Dev | `make verify-dev` | After merge |
| PR | `make verify-pr PR=N` | P0/P1 PRs |

## Quick Start

```bash
dx-check
bd create "title" --type task
```

## Repo Layout

- `frontend/` - React TypeScript app
- `backend/` - FastAPI Python
- `supabase/migrations/` - Database migrations
```

### Task 7: Add activation keywords to context skills (agent-skills-bey)

Add `activation:` to `.claude/skills/context-*/SKILL.md` in product repos:

**Example: context-plaid-integration/SKILL.md**
```yaml
---
name: context-plaid-integration
activation:
  - "plaid"
  - "bank link"
  - "institution"
  - "account linking"
purpose: Plaid OAuth flows and account synchronization
---
```

### Task 8: Test and validate (agent-skills-39q)

**Blocked by:** All other tasks

1. Run `dx-check` in prime-radiant-ai, verify routing table appears
2. Test agent alignment: ask "I need to track this bug" - should route to beads-workflow
3. Test on multiple VMs to confirm deterministic compilation
4. Verify `diff` between VMs shows identical AGENTS.md

---

## Verification Checklist

```bash
# After all tasks:
cd ~/prime-radiant-ai
dx-check
head -50 AGENTS.md  # Should show routing table

# Test routing
grep -A 20 "Skill Routing" AGENTS.md

# Cross-VM consistency
ssh macmini "cd ~/prime-radiant-ai && dx-check && head -50 AGENTS.md" > /tmp/macmini.md
diff AGENTS.md /tmp/macmini.md  # Should be identical
```

---

## Completion

After completing all tasks:
```bash
bd update agent-skills-lq5 --status closed --reason "Skill alignment system implemented"
bd sync
```
