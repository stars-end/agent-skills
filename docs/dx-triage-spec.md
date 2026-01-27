# dx-triage System Specification

> **Target User**: Solo fintech developer managing 3 VMs × 2-3 agents per VM (6-9 agents total)
> 
> **Problem**: Agents inherit unknown repo states, spend minutes understanding context, sometimes work on abandoned branches

## The Reality (80/20 Split)

| Scenario | Frequency | What Happens |
|----------|-----------|--------------|
| Same VM, same repo, same agent continues | 60% | Smooth, context preserved |
| Same VM, different agent on same repo | 20% | Some context loss |
| Different VM, different repo | 15% | Complete context loss |
| Emergency/hotfix across VMs | 5% | Rushed, high risk |

The problem is the **20% crossover** where agents land on a VM and don't know:
- Is this uncommitted work mine or someone else's?
- Is this branch still active or already merged?
- Should I continue or reset?

## Current Pain Points

```
$ ssh macmini
$ cd ~/prime-radiant-ai
$ git status
On branch fix/update-llm-common-pin
Changes not staged for commit:
  modified:   Makefile

$ # Agent wonders: Is this my work? Is the branch merged?
$ # Has to manually check git log, git branch -r, GitHub...
$ # Wastes 3-5 minutes per session
```

## Solution: dx-triage System

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ CRON LAYER (runs every 4 hours, independent of agents)              │
├─────────────────────────────────────────────────────────────────────┤
│ 5 */4 * * * auto-checkpoint ~/agent-skills   # Save work first      │
│ 10 */4 * * * ru sync agent-skills             # Pull updates        │
│ 15 */4 * * * dx-triage-cron                   # Flag drifted repos  │
│                                              (creates .git/DX_TRIAGE_REQUIRED) │
├─────────────────────────────────────────────────────────────────────┤
│ GIT HOOK LAYER (fires when agent tries to commit)                   │
├─────────────────────────────────────────────────────────────────────┤
│ Agent runs: git commit -m "fix bug"                                 │
│      ↓                                                               │
│ pre-commit hook checks .git/DX_TRIAGE_REQUIRED                      │
│      ↓                                                               │
│ If exists: BLOCK + show diagnostic message                          │
│      ↓                                                               │
│ Agent sees:                                                          │
│   "⚠️ COMMIT BLOCKED - On branch 'fix/old-feature' for 26h"         │
│   "This branch appears abandoned. Choose:"                           │
│   "  dx-triage --fix      → Reset to trunk (safe)"                   │
│   "  dx-triage --continue → Stay on branch (I know what I'm doing)" │
└─────────────────────────────────────────────────────────────────────┘
```

### Drift Detection Criteria

| Condition | Threshold | Classification | Rationale |
|-----------|-----------|----------------|-----------|
| On feature branch + no commits | > 24h | STALE | Abandoned work or very long task |
| Behind origin/master | > 100 commits | STALE | Severely out of sync |
| On feature branch + branch merged in remote | ANY | ORPHANED | Leftover after PR merge |
| Uncommitted changes + not touched in 48h | ANY | NEEDS_ATTENTION | Should checkpoint or commit |

### Flag File Format

```
.git/DX_TRIAGE_REQUIRED
```

Contents:
```
FLAGGED_AT: 2026-01-27T15:00:00Z
BRANCH: fix/update-llm-common-pin
REASON: On feature branch with no commits for 26 hours
STATUS: Branch appears to be merged in origin/master
BEHIND: 47 commits behind origin/master

Last local commit: 8 hours ago by Feng Tao Ning
Last origin/master: 2 hours ago

Recommended action:
  dx-triage --fix      # Reset to origin/master (safe, branch is merged)
  dx-triage --continue # Stay on this branch (I know what I'm doing)

To investigate manually:
  git log --oneline -5
  git branch -r --contains HEAD
  gh pr view --web 2>/dev/null || echo "No PR found"
```

### Components

#### 1. dx-triage-cron (new script)

Location: `~/agent-skills/scripts/dx-triage-cron`

What it does:
- Runs every 4 hours (after auto-checkpoint + ru sync)
- Checks each product repo (agent-skills, prime-radiant-ai, affordabot, llm-common)
- If drift detected, creates .git/DX_TRIAGE_REQUIRED
- Fail-silent: if anything fails, logs but doesn't crash

#### 2. dx-triage (enhance existing script)

Location: `~/agent-skills/scripts/dx-triage`

Commands:
- `dx-triage` - Show current state (no changes)
- `dx-triage --fix` - Apply safe fixes AND clear flag
- `dx-triage --continue` - Clear flag without changes

Safe fixes (only applied with --fix):
- Reset ORPHANED branches to origin/master
- Reset STALE branches (>100 commits behind) to origin/master
- Pull updates for repos on trunk that are behind

#### 3. Pre-commit hook (new)

Location: `~/agent-skills/hooks/pre-commit`

Behavior:
- Installed globally: `git config --global core.hooksPath ~/agent-skills/hooks`
- Checks for .git/DX_TRIAGE_REQUIRED before allowing commit
- Chains to existing Beads hooks after triage check
- Can be bypassed with `git commit --no-verify`

### Integration with Existing Hooks

Current state:
- agent-skills: Has Beads pre-commit hook
- llm-common: Has Beads pre-commit hook
- prime-radiant-ai: Broken symlink, needs fixing
- affordabot: Broken symlink, needs fixing

Solution: Chain hooks
```
~/agent-skills/hooks/pre-commit (triage check)
  └─→ if no flag, call .git/hooks/pre-commit.beads
```

### Cron Entry

Add to `crontab -e`:
```cron
# Repo state triage (runs after auto-checkpoint and ru sync)
15 */4 * * * /home/feng/.local/bin/dx-triage-cron >/dev/null 2>&1
```

### Installation

```bash
# 1. Create hooks directory
mkdir -p ~/agent-skills/hooks

# 2. Install pre-commit hook (triage-aware)
# [Script will be created]

# 3. Set global hooks path
git config --global core.hooksPath ~/agent-skills/hooks

# 4. Ensure each repo has Beads hook as pre-commit.beads
# [Manual setup or script]

# 5. Add cron entry
# [Manual or via script]
```

## Safety Properties

| Property | How It's Achieved |
|----------|-------------------|
| Never loses work | auto-checkpoint saves before triage runs |
| Never auto-resets | Requires explicit --fix or --continue |
| Fail-open | If triage-cron fails, no flag = no block |
| Always bypassable | git commit --no-verify |
| Per-repo isolation | Each repo flagged independently |
| Agent decides | We inform and block, they choose action |

## Edge Cases & Behaviors

| Scenario | Behavior |
|----------|----------|
| Agent actively working | No flag until 24h of no commits (respects active work) |
| Multiple repos flagged | Each repo independent, triage one at a time |
| Hotfix needed | Use --continue or --no-verify to bypass quickly |
| Cron job fails | Logs error, continues; no flag means no disruption |
| Repo has no remote | Skipped (can't determine drift) |
| Worktree | Checks main repo's .git, flag affects all worktrees |

## Metrics (for evaluation)

Track success by:
- Time saved per session: Target < 30 seconds to understand repo state
- False positive rate: Flagged repos that should continue work
- Lost work incidents: Should be zero (auto-checkpoint safety)

## Future Enhancements (out of scope for v1)

- Slack notification when repos flagged
- Auto-PR for abandoned-but-valuable work
- Cross-VM coordination (don't flag if actively worked on another VM)
- ML-based prediction of which branches to keep

## Implementation Checklist

- [ ] Create scripts/dx-triage-cron
- [ ] Enhance scripts/dx-triage with --fix and --continue flags
- [ ] Create hooks/pre-commit with Beads chaining
- [ ] Fix broken hooks in prime-radiant-ai and affordabot
- [ ] Add cron entry
- [ ] Test: create stale branch, wait for flag, verify block
- [ ] Test: dx-triage --fix resets correctly
- [ ] Test: dx-triage --continue clears flag
- [ ] Test: --no-verify bypass works
- [ ] Test: auto-checkpoint runs before triage
- [ ] Document in AGENTS.md

