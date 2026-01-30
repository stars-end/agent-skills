**Repo Context: Skills Registry**
- **Purpose**: Central store for all agent skills, scripts, and configurations.
- **Rules**:
  - Scripts must be idempotent.
  - `dx-hydrate.sh` is the single source of truth for setup.

## dx-* Commands Reference

### Core Commands (use frequently)

| Command | Purpose |
|---------|---------|
| `dx-check` | Verify environment (git, Beads, skills) |
| `dx-triage` | Diagnose repo state + safe recovery (see below) |
| `dx-dispatch` | Cross-VM and cloud dispatch |
| `dx-status` | Show repo and environment status |

### Optional Commands (use when needed)

| Command | Purpose |
|---------|---------|
| `dx-doctor` | Deep environment diagnostics |
| `dx-toolchain` | Verify toolchain consistency |
| `dx-worktree` | Manage git worktrees |
| `dx-fleet-status` | Check all VMs at once |

### dx-triage: Repo State Diagnosis

When repos are in mixed states (different branches, uncommitted work, staleness), use `dx-triage`:

```bash
# Show current state of all repos
dx-triage

# Apply safe fixes only (pull stale, reset merged branches)
dx-triage --fix

# Force reset ALL to trunk (DANGEROUS - stashes WIP first)
dx-triage --force
```

**States detected:**
| State | Meaning | Action |
|-------|---------|--------|
| OK | On trunk, clean, up-to-date | None needed |
| STALE | On trunk, behind origin | Safe to pull |
| DIRTY | Uncommitted changes | Review first |
| FEATURE-MERGED | On merged feature branch | Safe to reset |
| FEATURE-ACTIVE | On unmerged feature branch | Finish or discard |

**Key principle:** `dx-triage --fix` only does SAFE operations. It never touches DIRTY or FEATURE-ACTIVE repos.


---

## Product Repo Integration

The agent-skills repo provides global workflow skills, while each product repo has repo-specific context skills.

### Skill Architecture

| Location | Purpose | Managed By |
|----------|---------|------------|
| `~/agent-skills/` | Global workflows and automation | Centrally |
| `.claude/skills/context-*/` | Repo-specific domain knowledge | Per repo |

### Product Repos

| Repo | Context Location | Skills | Auto-Update |
|------|-----------------|--------|-------------|
| [prime-radiant-ai](https://github.com/stars-end/prime-radiant-ai) | `.claude/skills/context-*/` | 16 | ✅ |
| [affordabot](https://github.com/stars-end/affordabot) | `.claude/skills/context-*/` | 12 | ✅ |
| [llm-common](https://github.com/stars-end/llm-common) | `.claude/skills/context-*/` | 3 | ✅ |

### Key Principle

**Global skills in `~/agent-skills`** are for workflows that apply to all repos (issue tracking, PR creation, git operations).

**Context skills in `.claude/skills/context-*`** are for repo-specific domain knowledge (API contracts, database schema, infrastructure patterns).

Never duplicate global skills in product repos. They are auto-discovered from `~/agent-skills`.

---

