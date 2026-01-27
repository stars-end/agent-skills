# dx-triage System Review Prompt

> You are reviewing a proposed system for managing repository state across multiple VMs and agents. Read the spec below and answer the questions at the end.

## Context

You work in fintech with:
- **1 human developer** managing everything
- **3 VMs**: homedesktop-wsl, macmini, epyc6
- **6-9 AI agents total** (2-3 per VM)
- **4 product repos**: agent-skills, prime-radiant-ai, affordabot, llm-common

Work pattern:
- 80% of time: Same VM, same repo, same agent continues (smooth)
- 20% of time: Crossover between agents/VMs/repos (context loss, confusion)

The Problem:
When an agent lands on a VM where another agent was working, they see:
```
$ cd ~/prime-radiant-ai
$ git status
On branch fix/update-llm-common-pin
Changes not staged for commit:
  modified:   Makefile
```

Questions the agent has:
- Is this my work from a previous session?
- Is this branch merged already?
- Should I continue or reset?
- What was the original task?

Currently, agents waste 3-5 minutes per session figuring this out.

## Proposed Solution: dx-triage

Two-layer system:

**Layer 1: Cron (runs every 4 hours)**
1. auto-checkpoint saves any uncommitted work
2. ru sync pulls latest from origin
3. dx-triage-cron checks for drift and creates .git/DX_TRIAGE_REQUIRED if needed

**Layer 2: Git Hook (fires on commit)**
When agent tries to commit:
- Hook checks for .git/DX_TRIAGE_REQUIRED
- If exists: BLOCK commit + show diagnostic message
- Agent sees: "⚠️ COMMIT BLOCKED - On branch 'fix/old-feature' for 26h"
- Agent chooses: `dx-triage --fix` OR `dx-triage --continue`

## Drift Detection Criteria

| Condition | Threshold | Action |
|-----------|-----------|--------|
| On feature branch + no commits | > 24h | Flag as STALE |
| Behind origin/master | > 100 commits | Flag as STALE |
| On feature branch + branch merged | ANY | Flag as ORPHANED |
| Uncommitted changes + not touched | > 48h | Flag as NEEDS_ATTENTION |

## Example Flag File

```
FLAGGED_AT: 2026-01-27T15:00:00Z
BRANCH: fix/update-llm-common-pin
REASON: On feature branch with no commits for 26 hours
STATUS: Branch appears to be merged in origin/master
BEHIND: 47 commits behind origin/master

Recommended action:
  dx-triage --fix      # Reset to origin/master (safe)
  dx-triage --continue # Stay on branch (I know what I'm doing)
```

## Safety Guarantees

1. **Never loses work**: auto-checkpoint runs before triage
2. **Never auto-resets**: Requires explicit `--fix` or `--continue`
3. **Fail-open**: If cron fails, no flag = no disruption
4. **Always bypassable**: `git commit --no-verify`
5. **Per-repo isolation**: Each repo flagged independently

## Implementation

Three components:

1. **dx-triage-cron**: New script, runs every 4h, checks repos, creates flags
2. **dx-triage**: Enhance existing script, add `--fix` and `--continue` flags
3. **pre-commit hook**: Check flag, then chain to existing Beads hooks

Integration with existing hooks:
- agent-skills: Has Beads hook (flushes issues.jsonl)
- llm-common: Has Beads hook
- prime-radiant-ai: Broken symlink (needs fix)
- affordabot: Broken symlink (needs fix)

New chain: `triage check → if clear → Beads hook → allow commit`

---

## Review Questions

Please answer each question with **specific feedback**:

### 1. Is this solving the right problem?

Given the 80/20 work split, is repo state confusion actually causing issues, or is this over-engineering? 

Consider: 
- The macmini situation (two repos on fix/update-llm-common-pin for days)
- 3-5 minutes saved per crossover session
- 6-9 agents × multiple sessions per day

### 2. Is the approach safe?

Evaluate each safety claim:
- auto-checkpoint runs first → Does this actually guarantee no lost work?
- Never auto-resets → Does requiring `--fix` actually prevent mistakes?
- Fail-open → Is it safe for cron to fail silently?

### 3. Is 24 hours the right threshold?

If an agent works for 2 hours, then stops, then another agent comes 4 hours later... they inherit the state without warning. Is 24h too long? Too short? What about varying thresholds by repo type?

### 4. Does this work WITH agents or AGAINST them?

From a junior agent's perspective:
- They commit their work → Suddenly blocked → "What do I do?"
- Is the error message clear enough?
- Will they learn to just bypass with --no-verify?
- Is the hook helping them or slowing them down?

### 5. Is cron the right mechanism?

Alternatives:
- Run dx-triage-check at shell login
- Run via agent session start hooks
- Run manually with dx-check

Is cron (every 4h) actually the best time to check? What if agent starts work 1 minute after cron runs?

### 6. What's missing?

What scenarios or edge cases aren't addressed?
- Hotfixes that need to bypass quickly
- Cross-VM coordination (don't flag if actively worked on another VM)
- Worktrees
- Detached HEAD state
- Offline work

### 7. Would YOU want this as an agent?

If you were an agent starting work on macmini tomorrow:
- Would you be happy to see a triage block?
- Would the message be helpful?
- Would you know what to do?
- Or would you just run `git commit --no-verify` and move on?

---

## Final Verdict

After answering the questions, provide:

1. **Approval status**: [APPROVE / REQUEST CHANGES / REJECT]
2. **Critical issues** (must fix before implementing)
3. **Nice-to-haves** (future enhancements)
4. **Alternative approaches** (if you have a better idea)
