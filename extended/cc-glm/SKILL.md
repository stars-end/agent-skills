---
name: cc-glm
description: |
  Use cc-glm for batched delegation with plan-first execution.
  Batch by outcome (not file), use Task tool for dispatch, simplified monitoring.
  Trigger when user mentions cc-glm, delegation, parallel agents, or batch execution.
tags: [workflow, delegation, automation, claude-code, glm, parallel]
allowed-tools:
  - Bash
  - Task
---

# cc-glm: Plan-First Batched Dispatch (V8.3)

## Core Principle

**Batch by outcome, not by file.** One agent per coherent change set.

## When To Use

- Multi-file changes that form a coherent unit
- Backlog of independent tasks across repos
- Documentation + code changes that reference each other

## When NOT To Use

- Security-sensitive changes (auth, crypto, secrets)
- Architectural decisions
- High blast-radius refactors
- Single-file typo fixes (do it yourself)

---

## Pattern: Plan → Batch → Execute → Push

### Step 1: Plan (Required for Large/Cross-Repo)

**Threshold for plan file:**
- 6+ files, OR
- Cross-repo changes, OR
- High-risk changes

**Plan file template** (`<topic>-plan.md`):

```markdown
# Plan: [Task Name]

## Overview
[What we're doing]

## Tasks

### T1: [Batch Name]
- **depends_on**: []
- **repo**: [repo-name]
- **location**:
  - path/to/file1
  - path/to/file2
- **description**: [what to do]
- **validation**: [how to verify]
- **status**: Not Started
- **log**: [empty - agent fills]
- **files edited**: [empty - agent fills]

### T2: [Another Batch]
- **depends_on**: [T1]
...
```

**Fast path for small work** (1-2 files, single purpose):

Put mini-plan in Beads notes instead of file:

```markdown
## bd-xxx: Task Name
### Approach
- File: path/to/file
- Change: [what]
### Acceptance
- [ ] File modified
- [ ] Validation passed
```

### Step 2: Batch by Outcome

| Files | Approach | Agents |
|-------|----------|--------|
| 1-2, single purpose | Single agent | 1 |
| 3-5, coherent change | Single agent per repo | 1-2 |
| 6+ OR cross-repo | Batched by outcome | 2-3 |

**Rule**: 1 agent per repo or coherent change set, NOT 1 agent per file.

### Step 3: Execute with Task Tool

**Primary dispatch method** (dx-delegate is currently broken):

```yaml
Task:
  description: "T1: [batch name]"
  prompt: |
    You are implementing task T1 from plan.md

    ## Context
    - Plan: /path/to/plan.md
    - Dependencies: None (T1 has no depends_on)

    ## Your Task
    - **repo**: [repo-name]
    - **location**:
      - file1
      - file2
    - **description**: [what to do]
    - **validation**: [how to verify]

    ## Instructions
    1. cd to worktree: cd /tmp/agents/[beads-id]/[repo]
    2. Read ALL files in location first
    3. Implement changes for all acceptance criteria
    4. Keep work atomic and committable
    5. Update plan file:
       - status: Not Started → Completed
       - log: [your work summary]
       - files edited: [list of files you changed]
    6. Commit your work:
       - git add [specific files only]
       - git commit -m "..." (include Feature-Key and Agent trailers)
    7. DO NOT PUSH - orchestrator will push
    8. Return summary

  run_in_background: true
  subagent_type: general-purpose
```

### Step 4: Monitor (Simplified)

**Check every 5 minutes. Only 2 signals:**

1. **Process alive?** `ps -p [PID]`
2. **Log advancing?** `tail -20 [log]`

**Restart policy**: 1 restart max, then escalate.

```bash
# Quick status check
ps -p $(cat /tmp/cc-glm-jobs/bd-xxx.pid 2>/dev/null) >/dev/null 2>&1 && echo "Running" || echo "Done"

# Log check
tail -20 /tmp/cc-glm-jobs/bd-xxx.log
```

### Step 5: Review, Push, PR

After all agents complete:

1. Review commits in each worktree: `git log --oneline -5`
2. Push each batch: `git push -u origin feature-bd-xxx`
3. Create 1 PR per batch: `gh pr create --title "bd-xxx: [description]"`

---

## Wave Execution

For tasks with dependencies:

| Wave | Tasks | When to Start |
|------|-------|---------------|
| 1 | All tasks with `depends_on: []` | Immediately |
| 2 | Tasks depending on Wave 1 | After Wave 1 commits |
| 3 | Tasks depending on Wave 2 | After Wave 2 commits |

**Launch all Wave 1 tasks in parallel**, wait for completion, then Wave 2.

---

## Agent Prompt Template

Use this for Task tool dispatch:

```markdown
You are implementing a batched task from a development plan.

## Context
- Plan: [plan-file.md]
- Your Task: T[N]: [Name]
- Dependencies: [list or "None - this task has no dependencies"]

## Your Task
- **repo**: [repo-name]
- **location**:
  - path/to/file1
  - path/to/file2
- **description**: [full description]
- **validation**: [how to verify]

## Instructions
1. cd to repo: cd /tmp/agents/[beads-id]/[repo]
2. Read ALL files in location list first
3. Implement changes for all acceptance criteria
4. Keep work atomic and committable
5. Update plan file:
   - status: In Progress → Completed
   - log: [your work summary]
   - files edited: [list of files you changed]
6. Commit your work:
   - git add [specific files only]
   - git commit with Feature-Key and Agent trailers
7. DO NOT PUSH - orchestrator will push
8. Return summary of:
   - Files modified/created
   - Changes made
   - How criteria are satisfied
   - Validation performed or deferred

## Important
- Work only on files in your location list
- Other agents may be working in parallel
- Update plan file before yielding
- Commit, don't push
```

---

## Known Issues

### dx-delegate Broken
- **Symptom**: "Error: missing wrapper: /Users/fengning/extended/cc-glm/scripts/cc-glm-headless.sh"
- **Workaround**: Use Task tool directly (primary method above)
- **Status**: Deprecation pending

### Feature-Key Format
- **Issue**: `bd-epic.subtask` format rejected for large changes (190+ LOC)
- **Workaround**: Pre-create Beads ID with `bd create`
- **Hook expects**: `bd-xyz` format

---

## Anti-Patterns

| Anti-Pattern | Why Bad | Instead |
|--------------|---------|---------|
| 1 agent per file | Overhead explosion (11 PRs → 3 PRs) | Batch by repo/outcome |
| No plan file for cross-repo | Coordination chaos | Always plan first |
| Push per agent | PR explosion | Push once per batch |
| Multiple restarts | Brittle execution | 1 restart max |
| Complex state tracking | Cognitive overload | 2 signals only |

---

## Success Metrics

After 2 weeks, measure:
- Median PRs per epic: target 1-2
- Median worktrees per epic: target 1
- Blocked delegation rate: target <10%
- Founder intervention count: target 0

---

## Fallback

If Task tool unavailable, use direct cc-glm:

```bash
claude -p "YOUR PROMPT" --output-format text
```

Or with log capture:

```bash
nohup claude -p "$(cat /tmp/prompts/task.prompt)" \
  --output-format text \
  > /tmp/cc-glm-jobs/bd-xxx.log 2>&1 &
echo $! > /tmp/cc-glm-jobs/bd-xxx.pid
```
