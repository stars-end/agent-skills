# AGENTS.md Skill Alignment - Version C (Revised)

**Key change:** Extend existing local compilation instead of adding GitHub Actions sync.

---

## Current System (Already Works)

```
dx-check → detects staleness → compile_agent_context.sh
                                      ↓
                   ~/agent-skills/AGENTS.md (global)
                              +
                   ./AGENTS.local.md (repo-specific)
                              =
                   ./AGENTS.md (compiled)
```

**This is robust.** Extend it rather than replace it.

---

## What We Add

### 1. Activation Keywords in Skills

Add `activation:` frontmatter to skills:

```yaml
# ~/agent-skills/core/beads-workflow/SKILL.md
---
name: beads-workflow
activation:
  - "create issue"
  - "track work"
  - "start feature"
purpose: Issue lifecycle with dependency tracking
---
```

### 2. Extend compile_agent_context.sh

```bash
#!/bin/bash
# scripts/compile_agent_context.sh (extended)

compile_agent_context() {
    REPO_DIR="${1:-.}"
    GLOBAL_SRC="$HOME/agent-skills/AGENTS.md"
    LOCAL_SRC="$REPO_DIR/AGENTS.local.md"
    CONTEXT_DIR="$REPO_DIR/.claude/skills"
    TARGET="$REPO_DIR/AGENTS.md"

    # ... existing validation ...

    # Extract global skill routing
    GLOBAL_ROUTING=$(extract_routing "$HOME/agent-skills/core" "$HOME/agent-skills/dispatch" "$HOME/agent-skills/safety")

    # Extract repo context skill routing
    CONTEXT_ROUTING=""
    if [ -d "$CONTEXT_DIR" ]; then
        CONTEXT_ROUTING=$(extract_routing "$CONTEXT_DIR/context-"*)
    fi

    get_hash() {
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$1" | cut -d' ' -f1
        else
            md5 -q "$1"
        fi
    }

    GLOBAL_HASH=$(get_hash "$GLOBAL_SRC")
    LOCAL_HASH=$(get_hash "$LOCAL_SRC")
    CONTEXT_HASH=$(find "$CONTEXT_DIR" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5sum | cut -d' ' -f1 || echo "none")

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

    # Append Global Content (without routing - it's now above)
    cat "$GLOBAL_SRC" >> "$TARGET"

    # Append Local Content
    echo -e "\n\n---\n\n# REPO-SPECIFIC CONTEXT\n" >> "$TARGET"
    cat "$LOCAL_SRC" >> "$TARGET"

    echo "✅ Compiled: $TARGET (global:${GLOBAL_HASH:0:8} local:${LOCAL_HASH:0:8} context:${CONTEXT_HASH:0:8})"
}

extract_routing() {
    # Extract activation keywords from skill frontmatter
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            skill_file="$dir/SKILL.md"
            [ -f "$skill_file" ] || skill_file=$(find "$dir" -name "SKILL.md" -type f 2>/dev/null | head -1)
            [ -f "$skill_file" ] || continue

            # Parse YAML frontmatter for activation keywords
            python3 - "$skill_file" << 'PYEOF'
import sys, re, yaml
content = open(sys.argv[1]).read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if match:
    meta = yaml.safe_load(match.group(1))
    if meta and meta.get('activation'):
        patterns = ', '.join(f'"{p}"' for p in meta['activation'][:3])
        name = meta.get('name', 'unknown')
        purpose = (meta.get('purpose') or meta.get('description', ''))[:50]
        print(f"| {patterns} | {name} | {purpose} |")
PYEOF
        fi
    done
}

compile_agent_context "$@"
```

### 3. Update dx-check for Context Skills

```bash
# In dx-check.sh, add context skill hash to staleness check:

CONTEXT_HASH=$(find ".claude/skills" -name "SKILL.md" -exec cat {} \; 2>/dev/null | md5sum | cut -d' ' -f1 || echo "none")
COMPILED_CONTEXT_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'context-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")

if [ "$CONTEXT_HASH" != "$COMPILED_CONTEXT_HASH" ]; then
    echo -e "${BLUE}⚠️  AGENTS.md stale (context changed) - recompiling...${RESET}"
    "${SCRIPT_DIR}/compile_agent_context.sh" .
fi
```

### 4. Create AGENTS.local.md in Product Repos

```markdown
# prime-radiant-ai/AGENTS.local.md

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

- `frontend/` - React app
- `backend/` - FastAPI
- `supabase/` - Database migrations
```

---

## How It Works Across VMs

```
All VMs have:
- ~/agent-skills (git repo, synced via ru sync)
- ~/prime-radiant-ai (git repo, synced via ru sync)

On session start:
1. Developer runs dx-check (or it auto-runs)
2. dx-check compares hashes
3. If any source changed, compile_agent_context.sh runs
4. AGENTS.md regenerated locally

Result: All VMs have same AGENTS.md content (deterministic compilation)
```

**No GitHub Actions needed.** All VMs compile the same output because:
- Same ~/agent-skills content (via git)
- Same AGENTS.local.md (via git)
- Same .claude/skills/context-*/ (via git)
- Deterministic compilation script

---

## Failure Modes

| Failure | What Happens | Recovery |
|---------|--------------|----------|
| agent-skills not present | compile_agent_context.sh no-ops | Run dx-hydrate |
| AGENTS.local.md missing | No compilation (repo not opted in) | Create the file |
| Compilation script error | Immediate error message | Fix script, re-run dx-check |
| Context skill malformed YAML | Routing row missing | Fix skill frontmatter |
| VM out of sync | Stale AGENTS.md until dx-check | Run ru sync && dx-check |

**All failures are:**
- Immediately visible (not silent)
- Locally recoverable (no GitHub intervention)
- Idempotent (re-run fixes it)

---

## Interaction with Existing Processes

### dx-hydrate
- Sets up ~/.agent/skills symlink ✓
- Creates GEMINI.md symlink ✓
- Does NOT touch AGENTS.md content ✓
- **No conflict**

### dx-check
- Already calls compile_agent_context.sh ✓
- We extend hash check to include context-hash ✓
- **Natural extension**

### pr-context-update.yml
- Updates .claude/skills/context-*/ ✓
- After PR merge, context skills change ✓
- Next dx-check will detect and recompile ✓
- **Works together**

### ru sync
- Pulls all repos on all VMs ✓
- After sync, dx-check detects staleness ✓
- **Works together**

---

## What About AGENTS.md in Git?

**Current behavior:** Compiled AGENTS.md is NOT in .gitignore, so it gets committed.

**Options:**

A) **Keep in git** (recommended)
   - Consistent for new clones
   - Visible in code review
   - Slightly redundant (can be regenerated)

B) **Add to .gitignore**
   - Pure compilation model
   - New clones must run dx-check first
   - Agents without dx-check see nothing

**Recommendation:** Keep in git, but add comment that it's auto-generated.

---

## Migration Plan

### Step 1: Add Activation Keywords (30 min)
```bash
# For each skill in agent-skills/core/, dispatch/, safety/:
# Add activation: list to frontmatter
```

### Step 2: Extend compile_agent_context.sh (30 min)
```bash
# Add routing table generation
# Add context skill hash tracking
```

### Step 3: Create AGENTS.local.md (20 min per repo)
```bash
# prime-radiant-ai: Extract repo-specific content from current AGENTS.md
# affordabot: Same
# llm-common: Same
```

### Step 4: Test (20 min)
```bash
# On one VM:
cd ~/prime-radiant-ai
dx-check
cat AGENTS.md | head -50  # Verify routing table present

# On another VM:
ru sync
dx-check
diff <(ssh vm1 cat ~/prime-radiant-ai/AGENTS.md) <(cat ~/prime-radiant-ai/AGENTS.md)
# Should be identical
```

---

## Summary

| Aspect | GitHub Actions Approach | Local Compilation (Chosen) |
|--------|-------------------------|----------------------------|
| Complexity | High | Low |
| Failure modes | Many, some silent | Few, all visible |
| Recovery | Manual GitHub intervention | Re-run dx-check |
| Network dependency | Yes | No |
| Token management | Yes | No |
| Works offline | No | Yes |
| Consistency | Via PR merge | Via deterministic compilation |

**Local compilation is more robust for your setup.**
