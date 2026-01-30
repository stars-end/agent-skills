# AGENTS.md Sync Mechanics (Version C - Detailed)

This document answers three questions:
1. How do we mechanically integrate global + repo-specific AGENTS.md?
2. How does this work across VM × IDE matrix?
3. How is alignment maintained as skills change?

---

## Question 1: Mechanical Integration

### The File Structure

Each repo has ONE AGENTS.md file with TWO sections:

```markdown
# AGENTS.md

<!-- BEGIN_GLOBAL_ROUTING -->
[Synced from agent-skills - DO NOT EDIT MANUALLY]
<!-- END_GLOBAL_ROUTING -->

<!-- BEGIN_REPO_ROUTING -->
[Generated from .claude/skills/context-*/ - DO NOT EDIT MANUALLY]
<!-- END_REPO_ROUTING -->

<!-- BEGIN_REPO_SPECIFIC -->
[Repo-specific commands, verification, etc. - EDIT HERE]
<!-- END_REPO_SPECIFIC -->
```

### Source of Truth

```
agent-skills/AGENTS.md
├── Contains: Global skill routing table
├── Maintained by: Human or agent editing agent-skills
└── Synced to: All product repos (via GitHub Actions)

prime-radiant-ai/.claude/skills/context-*/
├── Contains: Context skill metadata (activation keywords)
├── Maintained by: pr-context-update.yml (existing)
└── Generates: REPO_ROUTING section in AGENTS.md
```

### Sync Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SYNC ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   agent-skills repo                                                         │
│   ┌──────────────────────┐                                                  │
│   │ AGENTS.md            │                                                  │
│   │ ├─ Global routing    │──────┬───────────────────────────────────────┐   │
│   │ └─ Skill definitions │      │                                       │   │
│   └──────────────────────┘      │                                       │   │
│                                 │                                       │   │
│   On push to master:            │ Flow 1: Global Sync                   │   │
│   sync-global-routing.yml       │ (GitHub Actions matrix)               │   │
│                                 ▼                                       ▼   │
│   ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────┐ │
│   │ prime-radiant-ai     │  │ affordabot           │  │ llm-common       │ │
│   │ AGENTS.md            │  │ AGENTS.md            │  │ AGENTS.md        │ │
│   │ ├─ GLOBAL_ROUTING ◄──┼──┼─ GLOBAL_ROUTING ◄────┼──┼─ GLOBAL_ROUTING  │ │
│   │ ├─ REPO_ROUTING      │  │ ├─ REPO_ROUTING      │  │ ├─ REPO_ROUTING  │ │
│   │ └─ REPO_SPECIFIC     │  │ └─ REPO_SPECIFIC     │  │ └─ REPO_SPECIFIC │ │
│   └──────────────────────┘  └──────────────────────┘  └──────────────────┘ │
│            ▲                          ▲                         ▲          │
│            │                          │                         │          │
│   Flow 2: Context Sync        Flow 2: Context Sync      Flow 2: Context    │
│   (pr-context-update.yml)     (pr-context-update.yml)   Sync               │
│            │                          │                         │          │
│   ┌────────┴────────┐        ┌────────┴────────┐       ┌────────┴────────┐ │
│   │.claude/skills/  │        │.claude/skills/  │       │.claude/skills/  │ │
│   │context-*/       │        │context-*/       │       │context-*/       │ │
│   └─────────────────┘        └─────────────────┘       └─────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flow 1: Global Sync (agent-skills → all repos)

**Trigger:** Push to `agent-skills/master` that modifies:
- `AGENTS.md`
- `core/**/SKILL.md`
- `dispatch/**/SKILL.md`
- `safety/**/SKILL.md`

**Workflow:** `agent-skills/.github/workflows/sync-global-routing.yml`

```yaml
name: Sync Global Routing

on:
  push:
    branches: [master]
    paths:
      - 'AGENTS.md'
      - 'core/**/SKILL.md'
      - 'dispatch/**/SKILL.md'
      - 'safety/**/SKILL.md'

jobs:
  extract-routing:
    runs-on: [self-hosted, linux, x64]
    outputs:
      routing_content: ${{ steps.extract.outputs.content }}
    steps:
      - uses: actions/checkout@v4

      - name: Extract global routing section
        id: extract
        run: |
          # Extract content between markers from AGENTS.md
          # Or generate from skill metadata
          python3 scripts/extract-global-routing.py \
            --source AGENTS.md \
            --output /tmp/global-routing.md

          # Base64 encode for passing between jobs
          CONTENT=$(base64 -w0 /tmp/global-routing.md)
          echo "content=$CONTENT" >> $GITHUB_OUTPUT

  sync-to-repos:
    needs: extract-routing
    strategy:
      matrix:
        repo: [prime-radiant-ai, affordabot, llm-common]
    runs-on: [self-hosted, linux, x64]
    steps:
      - name: Checkout target repo
        uses: actions/checkout@v4
        with:
          repository: stars-end/${{ matrix.repo }}
          token: ${{ secrets.REPO_SYNC_TOKEN }}

      - name: Inject global routing
        run: |
          # Decode routing content
          echo "${{ needs.extract-routing.outputs.routing_content }}" | base64 -d > /tmp/global-routing.md

          # Inject between markers
          python3 <<'EOF'
          import re

          with open('AGENTS.md', 'r') as f:
              content = f.read()

          with open('/tmp/global-routing.md', 'r') as f:
              routing = f.read()

          # Replace content between markers
          pattern = r'(<!-- BEGIN_GLOBAL_ROUTING -->).*?(<!-- END_GLOBAL_ROUTING -->)'
          replacement = f'\\1\n{routing}\n\\2'
          new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

          with open('AGENTS.md', 'w') as f:
              f.write(new_content)
          EOF

      - name: Create PR
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"

          BRANCH="chore/sync-global-routing-$(date +%Y%m%d)"
          git checkout -b "$BRANCH"
          git add AGENTS.md
          git commit -m "chore: sync global routing from agent-skills" || exit 0
          git push -u origin "$BRANCH"

          gh pr create \
            --title "chore: sync global routing from agent-skills" \
            --body "Auto-sync of global skill routing table." \
            --head "$BRANCH"
        env:
          GH_TOKEN: ${{ secrets.REPO_SYNC_TOKEN }}
```

### Flow 2: Context Sync (repo changes → repo AGENTS.md)

**Trigger:** PR merged to product repo (already exists: `pr-context-update.yml`)

**Addition:** After updating `.claude/skills/context-*/`, regenerate REPO_ROUTING section.

```yaml
# Add to existing _context-update.yml, after "Commit context updates" step:

- name: Regenerate repo routing section
  if: steps.route.outputs.should_update == 'true' && inputs.dry_run == false
  run: |
    python3 scripts/generate-repo-routing.py \
      --context-dir .claude/skills/context-*/ \
      --agents-md AGENTS.md

    git add AGENTS.md
    git commit -m "docs: update repo routing in AGENTS.md" || true
```

**Script: `scripts/generate-repo-routing.py`**

```python
#!/usr/bin/env python3
"""Generate REPO_ROUTING section from context skills."""

import re
import yaml
from pathlib import Path

def extract_activation(skill_path: Path) -> dict | None:
    """Parse SKILL.md frontmatter for activation keywords."""
    content = skill_path.read_text()

    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return None

    try:
        metadata = yaml.safe_load(match.group(1))
    except yaml.YAMLError:
        return None

    return {
        'name': metadata.get('name', skill_path.parent.name),
        'activation': metadata.get('activation', []),
        'purpose': metadata.get('purpose', metadata.get('description', ''))[:60]
    }

def generate_routing_table(context_dir: str) -> str:
    """Generate markdown routing table from context skills."""
    rows = []

    for skill_md in Path('.').glob(f'{context_dir}/SKILL.md'):
        info = extract_activation(skill_md)
        if info and info['activation']:
            patterns = ', '.join(f'"{p}"' for p in info['activation'][:3])
            rows.append(f"| {patterns} | {info['name']} | {info['purpose']} |")

    if not rows:
        return "No context skills with activation keywords found."

    header = "| When You See | Use This | Why |\n|--------------|----------|-----|\n"
    return header + '\n'.join(sorted(rows))

def inject_routing(agents_md: str, routing: str) -> str:
    """Inject routing table between markers."""
    pattern = r'(<!-- BEGIN_REPO_ROUTING -->).*?(<!-- END_REPO_ROUTING -->)'
    replacement = f'\\1\n{routing}\n\\2'
    return re.sub(pattern, replacement, agents_md, flags=re.DOTALL)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--context-dir', default='.claude/skills/context-*')
    parser.add_argument('--agents-md', default='AGENTS.md')
    args = parser.parse_args()

    routing = generate_routing_table(args.context_dir)

    with open(args.agents_md, 'r') as f:
        content = f.read()

    new_content = inject_routing(content, routing)

    with open(args.agents_md, 'w') as f:
        f.write(new_content)

    print(f"Updated {args.agents_md} with repo routing")
```

---

## Question 2: VM × IDE Matrix

### The Universe

```
VMs:  homedesktop-wsl, macmini, epyc6  (3)
IDEs: Claude Code, Codex CLI, Antigravity, OpenCode  (4)
─────────────────────────────────────────────────────
Total configurations: 12
```

### Why No Per-VM or Per-IDE Logic

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   GitHub (Cloud)                                                            │
│   ┌───────────────────────────────────────────────────────────────────────┐ │
│   │  Sync happens HERE                                                    │ │
│   │  - agent-skills pushes → sync-global-routing.yml runs                 │ │
│   │  - Creates PRs to product repos                                       │ │
│   │  - PRs merged → AGENTS.md updated in remote                           │ │
│   └───────────────────────────────────────────────────────────────────────┘ │
│                              │                                              │
│                              │ git pull                                     │
│                              ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                     Local Filesystem                                │   │
│   │                                                                     │   │
│   │   ~/prime-radiant-ai/AGENTS.md  ← Same file on all VMs              │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                              │                                              │
│        ┌─────────────────────┼─────────────────────┐                        │
│        │                     │                     │                        │
│        ▼                     ▼                     ▼                        │
│   ┌─────────┐          ┌─────────┐          ┌─────────┐                     │
│   │ Claude  │          │ Codex   │          │Antigrav │                     │
│   │ Code    │          │ CLI     │          │ity      │                     │
│   └─────────┘          └─────────┘          └─────────┘                     │
│        │                     │                     │                        │
│        └─────────────────────┴─────────────────────┘                        │
│                              │                                              │
│                    All read same file                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key insight: AGENTS.md is just a file.**

- All sync happens at GitHub layer (cloud)
- `git pull` propagates to all VMs
- All IDEs read from local filesystem
- No IDE-specific or VM-specific configuration needed

### Sync to VMs

**Option A: Manual pull** (current)
```bash
# Developer runs on each VM
cd ~/prime-radiant-ai && git pull
```

**Option B: Automated via `ru sync`** (existing tool)
```bash
# Syncs all repos on all VMs
ru sync
```

**Option C: Cron job** (optional)
```bash
# On each VM, add to crontab
0 * * * * cd ~/prime-radiant-ai && git pull --rebase 2>/dev/null
```

**Recommendation:** Option B is sufficient. Developers already use `ru sync`.

---

## Question 3: Maintenance Over Time

### Scenario A: Skill Added/Changed in agent-skills

```
1. Developer adds new skill: agent-skills/core/new-skill/SKILL.md
   - Includes `activation:` keywords in frontmatter

2. Developer updates agent-skills/AGENTS.md with routing entry
   - Or: Script auto-generates from skill metadata

3. Push to master triggers sync-global-routing.yml

4. GitHub Actions:
   - Extracts global routing section
   - Creates PR to prime-radiant-ai, affordabot, llm-common

5. PRs reviewed and merged (or auto-merged if no conflicts)

6. Product repo AGENTS.md now has new routing entry

7. Developers pull → all VMs updated
```

**Time from skill change to all VMs updated:** ~5 minutes (if auto-merge) to ~1 day (if manual review)

### Scenario B: Context Skill Changed in Product Repo

```
1. Developer updates prime-radiant-ai/frontend/components/...

2. PR merged to master

3. pr-context-update.yml triggers (existing):
   - Analyzes changed files
   - Updates .claude/skills/context-*/SKILL.md

4. NEW: generate-repo-routing.py runs:
   - Reads activation keywords from context skills
   - Updates REPO_ROUTING section in AGENTS.md

5. Commit pushed to master

6. Developers pull → updated
```

**Time from code change to AGENTS.md updated:** ~2 minutes (automated)

### Scenario C: Conflict Between Global and Repo Routing

```
What if:
- Global routing says: "deploy" → railway/deploy
- Repo routing says: "deploy" → context-infrastructure

Resolution: Repo-specific wins for that repo.

Implementation:
- REPO_ROUTING section appears AFTER GLOBAL_ROUTING
- Agent reads top-to-bottom, last match wins
- Or: More specific pattern wins

Better approach: Namespace patterns
- Global: "railway deploy", "deploy to production"
- Repo: "infrastructure", "deployment config"
```

### Scenario D: Skill Removed

```
1. Developer removes agent-skills/core/old-skill/

2. Developer removes routing entry from AGENTS.md
   - Or: Script detects missing skill, removes entry

3. Sync propagates removal to all repos

4. Old routing entry disappears from product repo AGENTS.md
```

### Drift Detection

Add version tracking to detect stale AGENTS.md:

```markdown
<!-- ROUTING_VERSION: 2024-01-30T15:30:00Z -->
<!-- BEGIN_GLOBAL_ROUTING -->
...
```

**dx-check enhancement:**
```bash
# In dx-check, add:
GLOBAL_VER=$(curl -s https://raw.githubusercontent.com/stars-end/agent-skills/master/AGENTS.md | grep ROUTING_VERSION)
LOCAL_VER=$(grep ROUTING_VERSION ~/prime-radiant-ai/AGENTS.md)

if [ "$GLOBAL_VER" != "$LOCAL_VER" ]; then
  echo "⚠️  AGENTS.md routing may be stale. Run: git pull"
fi
```

---

## Complete AGENTS.md Template

```markdown
# AGENTS.md — [Repo Name]

<!-- ROUTING_VERSION: 2024-01-30T15:30:00Z -->

## Skill Routing

<!-- BEGIN_GLOBAL_ROUTING -->
### Global Skills (from agent-skills)

| When You See | Use This | Why |
|--------------|----------|-----|
| "create issue", "track work" | core/beads-workflow | Issue lifecycle |
| "save work", "sync branch" | core/sync-feature-branch | Git workflow |
| "create PR", "ready for review" | core/create-pull-request | PR creation |
| "dispatch", "another VM" | dispatch/multi-agent-dispatch | Cross-VM |
| "dangerous", "force push" | safety/dcg-safety | Destructive guard |
<!-- END_GLOBAL_ROUTING -->

<!-- BEGIN_REPO_ROUTING -->
### Repo Context (auto-generated)

| When You See | Use This | Why |
|--------------|----------|-----|
| "plaid", "bank link" | context-plaid-integration | Plaid OAuth |
| "schema", "migration" | context-database-schema | Supabase |
| "clerk", "auth" | context-clerk-integration | Auth flows |
<!-- END_REPO_ROUTING -->

<!-- BEGIN_REPO_SPECIFIC -->
## Verification

| Target | Command | When |
|--------|---------|------|
| Local | `make verify-local` | Before commit |
| Dev | `make verify-dev` | After merge |

## Quick Start

```bash
dx-check
bd create "title" --type task
# ... repo-specific commands
```
<!-- END_REPO_SPECIFIC -->
```

---

## Implementation Checklist

### Phase 1: Prepare (1 hour)

- [ ] Add `activation:` to 15-20 skills in agent-skills
- [ ] Create `scripts/extract-global-routing.py` in agent-skills
- [ ] Create `scripts/generate-repo-routing.py` (can live in agent-skills, copied to repos)

### Phase 2: Bootstrap (30 min)

- [ ] Add markers to prime-radiant-ai/AGENTS.md
- [ ] Add markers to affordabot/AGENTS.md
- [ ] Add markers to llm-common/AGENTS.md
- [ ] Run initial generation to populate sections

### Phase 3: Automation (1 hour)

- [ ] Create `agent-skills/.github/workflows/sync-global-routing.yml`
- [ ] Extend `pr-context-update.yml` in each repo to update REPO_ROUTING
- [ ] Add REPO_SYNC_TOKEN secret to agent-skills repo

### Phase 4: Validate (30 min)

- [ ] Push test change to agent-skills, verify PR created in product repos
- [ ] Merge PR in product repo, verify AGENTS.md updated
- [ ] Test agent alignment: "I need to track this bug" → should route to beads-workflow

---

## Summary

| Question | Answer |
|----------|--------|
| **How to integrate?** | One AGENTS.md per repo with 3 sections (global, repo, custom), synced via markers |
| **How across VM × IDE?** | Sync at GitHub layer, git pull propagates, all IDEs read same file |
| **How maintained?** | Two GitHub Actions flows: global→repos (on agent-skills push), context→AGENTS.md (on PR merge) |
