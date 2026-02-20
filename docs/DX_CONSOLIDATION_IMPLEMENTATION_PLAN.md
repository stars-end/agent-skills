# DX Consolidation Implementation Plan

**Epic**: `agent-skills-scu`
**Reviewer**: Human (code review only)
**Implementer**: Dev agent (autonomous execution)

---

## Executive Summary

This plan consolidates the agent-skills repo's DX infrastructure:
1. **Dispatch**: 4 tools → 1 canonical `dx-dispatch`
2. **Skills**: Flat 53 skills → 8 siloed categories
3. **Docs**: AGENTS.md gets Quick Start + Categories
4. **Cleanup**: Archive unused code, update symlinks

**Scope**: 3 canonical VMs × 4 canonical agent IDEs
**Constraint**: All skills must follow [agentskills.io](https://agentskills.io/specification)

---

## Pre-Implementation Checklist

Before starting, verify:

```bash
# 1. You're on master with clean state
git status  # Should show clean
git pull --rebase

# 2. Beads is synced
bd sync

# 3. Environment works
dx-check
```

---

## Phase 1: Dispatch Consolidation

> **MIGRATION COMPLETE (bd-xga8.14.8 - 2026-02-20)**
>
> The canonical dispatch surface is now `dx-runner`:
>   - **Primary**: `dx-runner start --provider opencode --beads <id> --prompt-file <path>`
>   - **Reliability backstop**: `dx-runner start --provider cc-glm --beads <id> --prompt-file <path>`
>   - **Break-glass only**: `dx-dispatch` (shell shim) or `dx-dispatch.py` (Python shim)
>
> See `docs/specs/dispatch-closeout-report.md` for complete migration details.
> Tasks 1.1-1.4 below are preserved for historical reference.

**Goal**: ~~`dx-dispatch` becomes THE canonical dispatch tool~~ → **`dx-runner` is THE canonical dispatch tool** with multi-provider support (opencode, cc-glm, gemini).

### Historical Reference: Task 1.1: Evaluate lib/fleet Usage (scu.19)

**Check if lib/fleet is actively used:**

```bash
# Find all imports of lib.fleet
grep -r "from lib.fleet" scripts/ --include="*.py"
grep -r "import lib.fleet" scripts/ --include="*.py"
grep -r "lib/fleet" . --include="*.py" | grep -v __pycache__
```

**Expected findings:**
- `fleet-dispatch.py` imports `lib.fleet.FleetDispatcher`
- `dx-dispatch.py` may import fleet backends

**Decision matrix:**

| Finding | Action |
|---------|--------|
| Only fleet-dispatch.py uses it | Archive lib/fleet with fleet-dispatch.py |
| dx-dispatch.py uses it | Keep lib/fleet, consolidate dispatch CLIs |
| Multiple active users | Keep lib/fleet as-is |

**Mark complete:**
```bash
bd update agent-skills-scu.19 --status closed --reason "Evaluated: [YOUR FINDING]"
```

### Task 1.2: Merge jules-dispatch Logic into dx-dispatch.py (scu.1)

**Current state:**
- `scripts/jules-dispatch.py` (136 lines): Dispatches Beads issues to Jules agents
- `scripts/dx-dispatch.py` (415 lines): SSH dispatch to VMs

**Target state:**
- `dx-dispatch.py` gains `--jules` flag that provides Jules dispatch functionality

**Implementation:**

1. **Read and understand jules-dispatch.py:**
   ```bash
   cat scripts/jules-dispatch.py
   ```

   Key functions to extract:
   - `get_beads_issue(issue_id)` - Fetch issue from Beads
   - `build_jules_prompt(issue)` - Build prompt for Jules
   - `dispatch_to_jules(prompt)` - Call `jules` CLI

2. **Add to dx-dispatch.py:**

   Add argument parsing for `--jules`:
   ```python
   parser.add_argument('--jules', action='store_true',
                       help='Dispatch to Jules Cloud instead of SSH')
   parser.add_argument('--issue', '-i', type=str,
                       help='Beads issue ID to dispatch (required for --jules)')
   ```

   Add Jules dispatch function (copy from jules-dispatch.py):
   ```python
   def dispatch_jules(issue_id: str, dry_run: bool = False) -> int:
       """Dispatch a Beads issue to Jules Cloud."""
       # Copy implementation from jules-dispatch.py
       # Key steps:
       # 1. bd show <issue_id> --json
       # 2. Build prompt with issue context
       # 3. Call: jules start --prompt "<prompt>"
       pass
   ```

   Update main() to route based on `--jules`:
   ```python
   if args.jules:
       if not args.issue:
           print("Error: --issue required with --jules", file=sys.stderr)
           return 1
       return dispatch_jules(args.issue, args.dry_run)
   else:
       # Existing SSH dispatch logic
       ...
   ```

3. **Test:**
   ```bash
   # Dry run
   python3 scripts/dx-dispatch.py --jules --issue agent-skills-scu.1 --dry-run

   # Verify help
   python3 scripts/dx-dispatch.py --help
   ```

4. **Mark complete:**
   ```bash
   bd update agent-skills-scu.1 --status closed --reason "Jules logic merged into dx-dispatch.py"
   ```

### Task 1.3: Merge fleet-dispatch Logic into dx-dispatch.py (scu.2)

**Depends on**: scu.19 (evaluate lib/fleet)

**If lib/fleet is actively used:**

1. Add `--fleet` flag to dx-dispatch.py:
   ```python
   parser.add_argument('--fleet', action='store_true',
                       help='Use Fleet dispatcher (OpenCode/Jules backends)')
   ```

2. Import and use FleetDispatcher:
   ```python
   if args.fleet:
       from lib.fleet import FleetDispatcher
       dispatcher = FleetDispatcher()
       # ... dispatch logic from fleet-dispatch.py
   ```

**If lib/fleet is NOT actively used:**
- Skip this task, mark as "N/A - lib/fleet archived"
- Proceed to archiving in scu.3

**Mark complete:**
```bash
bd update agent-skills-scu.2 --status closed --reason "[Merged/Skipped]: [REASON]"
```

### Task 1.4: Archive Legacy Dispatch Scripts (scu.3)

**Depends on**: scu.1, scu.2

**Create archive directory and move:**
```bash
mkdir -p archive/dispatch-legacy

# Move legacy scripts
mv scripts/jules-dispatch.py archive/dispatch-legacy/
mv scripts/fleet-dispatch.py archive/dispatch-legacy/
mv scripts/nightly_dispatch.py archive/dispatch-legacy/

# If lib/fleet is unused, archive it too
# mv lib/fleet archive/dispatch-legacy/

# Create README in archive
cat > archive/dispatch-legacy/README.md << 'EOF'
# Archived Dispatch Scripts

These scripts were consolidated into `scripts/dx-dispatch.py` as part of
the DX Consolidation epic (agent-skills-scu).

## Migration

| Old Script | New Command |
|------------|-------------|
| `jules-dispatch.py <issue>` | `dx-dispatch --jules --issue <issue>` |
| `fleet-dispatch.py dispatch <args>` | `dx-dispatch --fleet <args>` |
| `nightly_dispatch.py` | Functionality moved to cron/scheduler |

## Date Archived
$(date +%Y-%m-%d)
EOF
```

**Update dx-ensure-bins.sh:**
Remove the fleet-dispatch symlink:
```bash
# In scripts/dx-ensure-bins.sh, remove or comment out:
# link "$AGENTS_ROOT/scripts/fleet-dispatch.py" "$BIN_DIR/fleet-dispatch"
```

**Mark complete:**
```bash
bd update agent-skills-scu.3 --status closed --reason "Legacy dispatch scripts archived"
```

### Task 1.5: Update multi-agent-dispatch Skill (scu.4)

**Depends on**: scu.1, scu.3

**Edit `multi-agent-dispatch/SKILL.md`:**

1. Update the description to reference dx-dispatch as canonical:
   ```yaml
   ---
   name: multi-agent-dispatch
   description: Cross-VM task dispatch using dx-dispatch (canonical). Supports SSH dispatch to canonical VMs (homedesktop-wsl, macmini, epyc6), Jules Cloud dispatch for async work, and fleet orchestration.
   ---
   ```

2. Update the body to show dx-dispatch usage:
   ```markdown
   ## Usage

   ### SSH Dispatch (default)
   ```bash
   dx-dispatch epyc6 "Run make test in ~/affordabot"
   dx-dispatch macmini "Build the iOS app"
   dx-dispatch --list  # Check VM status
   ```

   ### Jules Cloud Dispatch
   ```bash
   dx-dispatch --jules --issue bd-123
   ```

   ### Fleet Dispatch (if enabled)
   ```bash
   dx-dispatch --fleet --backend opencode --prompt "..."
   ```
   ```

3. Remove any references to `jules-dispatch.py` or `fleet-dispatch.py`

**Mark complete:**
```bash
bd update agent-skills-scu.4 --status closed --reason "multi-agent-dispatch skill updated to use dx-dispatch only"
```

---

## Phase 2: Skill Siloing

**Goal**: Organize 53 skills into 8 categories following agentskills.io spec.

### Task 2.1: Create Skill Category Directories (scu.5)

```bash
mkdir -p core safety health infra dispatch search extended
```

**Category definitions:**

| Category | Purpose | Skills to Move |
|----------|---------|----------------|
| `core/` | Daily workflow - every agent needs | beads-workflow, sync-feature-branch, create-pull-request, finish-feature, issue-first, session-end, feature-lifecycle, fix-pr-feedback, merge-pr |
| `safety/` | Auto-loaded safety guards | dcg-safety, beads-guard |
| `health/` | Environment diagnostics | bd-doctor, mcp-doctor, railway-doctor, skills-doctor, ssh-key-doctor, lockfile-doctor, toolchain-health, verify-pipeline |
| `infra/` | VM setup and maintenance | vm-bootstrap, canonical-targets, github-runner-setup, devops-dx, dx-alerts |
| `dispatch/` | Cross-VM coordination | multi-agent-dispatch |
| `search/` | Context and history | cass-search, area-context-create, context-database-schema, docs-create |
| `extended/` | Optional advanced workflows | plan-refine, parallelize-cloud-work, coordinator-dx, jules-dispatch (deprecated), slack-coordination, cli-mastery, skill-creator, dirty-repo-bootstrap, worktree-workflow, lint-check, bv-integration |

**Note**: `railway/` already exists as a category - leave it as-is.

**Mark complete:**
```bash
bd update agent-skills-scu.5 --status closed --reason "Category directories created"
```

### Tasks 2.2-2.8: Move Skills to Categories (scu.6 - scu.12)

**IMPORTANT**: Use `git mv` to preserve history.

**scu.6: Move core workflow skills to core/**
```bash
git mv beads-workflow core/
git mv sync-feature-branch core/
git mv create-pull-request core/
git mv finish-feature core/
git mv issue-first core/
git mv session-end core/
git mv feature-lifecycle core/
git mv fix-pr-feedback core/
git mv merge-pr core/
```

**scu.7: Move safety skills to safety/**
```bash
git mv dcg-safety safety/
git mv beads-guard safety/
git mv git-safety-guard safety/
```

**scu.8: Move health/doctor skills to health/**
```bash
git mv bd-doctor health/
git mv mcp-doctor health/
git mv railway-doctor health/
git mv skills-doctor health/
git mv ssh-key-doctor health/
git mv lockfile-doctor health/
git mv toolchain-health health/
git mv verify-pipeline health/
```

**scu.9: Move infra skills to infra/**
```bash
git mv vm-bootstrap infra/
git mv canonical-targets infra/
git mv github-runner-setup infra/
git mv devops-dx infra/
git mv dx-alerts infra/
```

**scu.10: Move dispatch skill to dispatch/**
```bash
git mv multi-agent-dispatch dispatch/
```

**scu.11: Move search/context skills to search/**
```bash
git mv cass-search search/
git mv area-context-create search/
git mv context-database-schema search/
git mv docs-create search/
```

**scu.12: Move extended workflows to extended/**
```bash
git mv plan-refine extended/
git mv parallelize-cloud-work extended/
git mv coordinator-dx extended/
git mv jules-dispatch extended/  # Mark as deprecated in SKILL.md
git mv slack-coordination extended/
git mv cli-mastery extended/
git mv skill-creator extended/
git mv dirty-repo-bootstrap extended/
git mv worktree-workflow extended/
git mv lint-check extended/
git mv bv-integration extended/
```

**After all moves, commit:**
```bash
git add -A
git commit -m "refactor: silo skills into categories (scu.6-12)

Moved 53 skills into 8 categories:
- core/: 9 daily workflow skills
- safety/: 3 safety guards
- health/: 8 diagnostic skills
- infra/: 5 VM/environment skills
- dispatch/: 1 dispatch skill
- search/: 4 context/search skills
- extended/: 11 optional workflows
- railway/: 12 Railway skills (unchanged)

Part of DX Consolidation epic (agent-skills-scu)"
```

**Mark tasks complete:**
```bash
bd update agent-skills-scu.6 --status closed --reason "Core skills moved"
bd update agent-skills-scu.7 --status closed --reason "Safety skills moved"
bd update agent-skills-scu.8 --status closed --reason "Health skills moved"
bd update agent-skills-scu.9 --status closed --reason "Infra skills moved"
bd update agent-skills-scu.10 --status closed --reason "Dispatch skill moved"
bd update agent-skills-scu.11 --status closed --reason "Search skills moved"
bd update agent-skills-scu.12 --status closed --reason "Extended skills moved"
```

### Task 2.9: Verify agentskills.io Spec Compliance (scu.13)

**Depends on**: scu.6-12

**Run compliance check on all skills:**

```bash
# Check all SKILL.md files for required fields
for skill in $(find . -name "SKILL.md" -type f | grep -v archive); do
  echo "=== Checking: $skill ==="

  # Check for name field
  if ! grep -q "^name:" "$skill"; then
    echo "  ERROR: Missing 'name' field"
  fi

  # Check for description field
  if ! grep -q "^description:" "$skill"; then
    echo "  ERROR: Missing 'description' field"
  fi

  # Check name length (max 64 chars)
  name=$(grep "^name:" "$skill" | sed 's/name: *//')
  if [ ${#name} -gt 64 ]; then
    echo "  ERROR: Name too long (${#name} > 64 chars)"
  fi

  # Check name format (lowercase, numbers, hyphens only)
  if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then
    echo "  WARNING: Name may not follow spec: $name"
  fi
done
```

**Fix any violations found**, then:

```bash
bd update agent-skills-scu.13 --status closed --reason "All skills verified agentskills.io compliant"
```

---

## Phase 3: Documentation Update

**Goal**: AGENTS.md gets clear Quick Start, Categories, and examples.

### Task 3.1: Add Quick Start Section (scu.14)

**Edit `AGENTS.md`** - Add after "Daily Workflow" section:

```markdown
---

## Quick Start (5 Commands)

Every agent session starts here:

| Step | Command | Purpose |
|------|---------|---------|
| 1 | `dx-check` | Verify environment |
| 2 | `bd list` | See current issues |
| 3 | `bd create "title" --type task` | Create tracking issue |
| 4 | `/skill core/sync-feature-branch` | Save work |
| 5 | `/skill core/create-pull-request` | Create PR |

### Example: Fix a Bug

```bash
# 1. Check environment
dx-check

# 2. Create tracking issue
bd create "Fix auth timeout bug" --type bug --priority 2

# 3. Start work (creates branch)
/skill core/beads-workflow
# Select: start-feature bd-xxx

# 4. Make your changes...

# 5. Save work
/skill core/sync-feature-branch
# Enter: sync-feature "fixed auth timeout"

# 6. Create PR when done
/skill core/create-pull-request
```

---
```

**Mark complete:**
```bash
bd update agent-skills-scu.14 --status closed --reason "Quick Start section added to AGENTS.md"
```

### Task 3.2: Add Skill Categories Table (scu.15)

**Depends on**: scu.5

**Edit `AGENTS.md`** - Add after "Skills (agentskills.io Format)" section:

```markdown
## Skill Categories

Skills are organized into categories for easy discovery:

| Category | Purpose | When to Use |
|----------|---------|-------------|
| `core/` | Daily workflow | Every session - creating issues, syncing work, PRs |
| `safety/` | Safety guards | Auto-loaded - prevents destructive commands |
| `health/` | Diagnostics | When something isn't working right |
| `infra/` | VM/environment | Setting up new VMs or debugging environment |
| `dispatch/` | Cross-VM work | When task needs another VM (GPU, macOS) |
| `railway/` | Railway deployment | Deploying to Railway |
| `search/` | Context/history | Finding past solutions or building context |
| `extended/` | Advanced workflows | Optional - parallelization, planning, etc. |

### Finding Skills by Need

| Need | Skill | Category |
|------|-------|----------|
| Create/track issues | `/skill core/beads-workflow` | core/ |
| Save work | `/skill core/sync-feature-branch` | core/ |
| Create PR | `/skill core/create-pull-request` | core/ |
| Dispatch to another VM | `/skill dispatch/multi-agent-dispatch` | dispatch/ |
| Deploy to Railway | `/skill railway/deploy` | railway/ |
| Search past sessions | `/skill search/cass-search` | search/ |
| Debug environment | `/skill health/bd-doctor` | health/ |
| Set up new VM | `/skill infra/vm-bootstrap` | infra/ |

---
```

**Mark complete:**
```bash
bd update agent-skills-scu.15 --status closed --reason "Skill Categories table added to AGENTS.md"
```

### Task 3.3: Add "When You Need More" Section (scu.16)

**Depends on**: scu.13

**Edit `AGENTS.md`** - Add after Skill Categories:

```markdown
## When You Need More

### Cross-VM Dispatch

Use when task needs specific VM capabilities:

```bash
# SSH dispatch to canonical VMs
dx-dispatch epyc6 "Run GPU tests in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch homedesktop-wsl "Run integration tests"

# Check VM status
dx-dispatch --list

# Jules Cloud dispatch (async)
dx-dispatch --jules --issue bd-123
```

### Environment Issues

```bash
# Quick health check
dx-check

# Full diagnostics
/skill health/bd-doctor
/skill health/mcp-doctor
/skill health/toolchain-health
```

---
```

**Mark complete:**
```bash
bd update agent-skills-scu.16 --status closed --reason "'When You Need More' section added"
```

### Task 3.4: Update dx-dispatch Documentation (scu.17)

**Depends on**: scu.1, scu.2

**Edit `AGENTS.md`** - Update the "Multi-Agent Dispatch" section:

```markdown
## Multi-Agent Dispatch

`dx-dispatch` is the canonical tool for cross-VM and cloud dispatch.

### SSH Dispatch (default)

```bash
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch --list  # Check VM status
```

### Jules Cloud Dispatch

```bash
dx-dispatch --jules --issue bd-123
dx-dispatch --jules --issue bd-123 --dry-run  # Preview prompt
```

### Canonical VMs

| VM | User | Capabilities |
|----|------|--------------|
| homedesktop-wsl | fengning | Primary dev, DCG, CASS |
| macmini | fengning | macOS builds, iOS |
| epyc6 | feng | GPU work, ML training |

---
```

**Mark complete:**
```bash
bd update agent-skills-scu.17 --status closed --reason "dx-dispatch documentation updated"
```

### Task 3.5: Ensure CLAUDE.md and GEMINI.md Stay in Sync (scu.18)

**Depends on**: scu.14, scu.15, scu.16

**Check current state:**
```bash
md5sum AGENTS.md CLAUDE.md GEMINI.md
```

**If they're already identical (same hash)**, make them symlinks:
```bash
rm CLAUDE.md GEMINI.md
ln -s AGENTS.md CLAUDE.md
ln -s AGENTS.md GEMINI.md
git add CLAUDE.md GEMINI.md
```

**Mark complete:**
```bash
bd update agent-skills-scu.18 --status closed --reason "CLAUDE.md and GEMINI.md are symlinks to AGENTS.md"
```

---

## Phase 4: Archive/Cleanup

### Task 4.1: Consolidate dx-* Commands Documentation (scu.20)

**Depends on**: scu.17

**Add to AGENTS.md**:

```markdown
## dx-* Commands Reference

### Core Commands (use frequently)

| Command | Purpose |
|---------|---------|
| `dx-check` | Verify environment (git, Beads, skills) |
| `dx-dispatch` | Cross-VM and cloud dispatch |
| `dx-status` | Show repo and environment status |

### Optional Commands (use when needed)

| Command | Purpose |
|---------|---------|
| `dx-doctor` | Deep environment diagnostics |
| `dx-toolchain` | Verify toolchain consistency |
| `dx-worktree` | Manage git worktrees |
| `dx-fleet-status` | Check all VMs at once |

---
```

**Mark complete:**
```bash
bd update agent-skills-scu.20 --status closed --reason "dx-* commands documented"
```

### Task 4.2: Update dx-hydrate.sh for New Skill Locations (scu.22)

**Depends on**: scu.13

Skills are discovered via glob patterns. Verify the pattern supports subdirectories:

```bash
# Test that skills in subdirectories are discoverable
find ~/agent-skills -name "SKILL.md" -type f | wc -l
# Should find all 53 skills including those in subdirectories
```

**Mark complete:**
```bash
bd update agent-skills-scu.22 --status closed --reason "Skill discovery verified for new locations"
```

### Task 4.3: Clean Up ~/bin Symlinks on All VMs (scu.21)

**Depends on**: scu.13, scu.22

**On each canonical VM, run:**

```bash
ssh fengning@homedesktop-wsl "cd ~/agent-skills && git pull && ./scripts/dx-ensure-bins.sh"
ssh fengning@macmini "cd ~/agent-skills && git pull && ./scripts/dx-ensure-bins.sh"
ssh feng@epyc6 "cd ~/agent-skills && git pull && ./scripts/dx-ensure-bins.sh"
```

**Mark complete:**
```bash
bd update agent-skills-scu.21 --status closed --reason "~/bin symlinks updated on all VMs"
```

---

## Final Verification

```bash
# 1. Verify structure
tree -L 2 -d | head -20

# 2. Verify dispatch
dx-dispatch --help
dx-dispatch --list

# 3. Verify skills discoverable
find . -name "SKILL.md" -type f | wc -l  # Should be 53

# 4. Verify AGENTS.md
grep -c "Quick Start" AGENTS.md
grep -c "Skill Categories" AGENTS.md

# 5. Push and sync
git push
bd sync

# 6. Close epic
bd update agent-skills-scu --status closed --reason "All subtasks complete"
```

---

## Appendix: Complete Skill Category Mapping

| Original Location | New Location |
|-------------------|--------------|
| `beads-workflow` | `core/beads-workflow` |
| `sync-feature-branch` | `core/sync-feature-branch` |
| `create-pull-request` | `core/create-pull-request` |
| `finish-feature` | `core/finish-feature` |
| `issue-first` | `core/issue-first` |
| `session-end` | `core/session-end` |
| `feature-lifecycle` | `core/feature-lifecycle` |
| `fix-pr-feedback` | `core/fix-pr-feedback` |
| `merge-pr` | `core/merge-pr` |
| `dcg-safety` | `safety/dcg-safety` |
| `beads-guard` | `safety/beads-guard` |
| `git-safety-guard` | *(removed; use `safety/dcg-safety`)* |
| `bd-doctor` | `health/bd-doctor` |
| `mcp-doctor` | `health/mcp-doctor` |
| `railway-doctor` | `health/railway-doctor` |
| `skills-doctor` | `health/skills-doctor` |
| `ssh-key-doctor` | `health/ssh-key-doctor` |
| `lockfile-doctor` | `health/lockfile-doctor` |
| `toolchain-health` | `health/toolchain-health` |
| `verify-pipeline` | `health/verify-pipeline` |
| `vm-bootstrap` | `infra/vm-bootstrap` |
| `canonical-targets` | `infra/canonical-targets` |
| `github-runner-setup` | `infra/github-runner-setup` |
| `devops-dx` | `infra/devops-dx` |
| `dx-alerts` | `infra/dx-alerts` |
| `multi-agent-dispatch` | `dispatch/multi-agent-dispatch` |
| `cass-search` | `search/cass-search` |
| `area-context-create` | `search/area-context-create` |
| `context-database-schema` | `search/context-database-schema` |
| `docs-create` | `search/docs-create` |
| `plan-refine` | `extended/plan-refine` |
| `parallelize-cloud-work` | `extended/parallelize-cloud-work` |
| `coordinator-dx` | `extended/coordinator-dx` |
| `jules-dispatch` | `extended/jules-dispatch` |
| `slack-coordination` | `extended/slack-coordination` |
| `cli-mastery` | `extended/cli-mastery` |
| `skill-creator` | `extended/skill-creator` |
| `dirty-repo-bootstrap` | `extended/dirty-repo-bootstrap` |
| `worktree-workflow` | `extended/worktree-workflow` |
| `lint-check` | `extended/lint-check` |
| `bv-integration` | `extended/bv-integration` |
| `railway/*` | `railway/*` (unchanged) |
