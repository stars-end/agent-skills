# Skill: dx-loop

# dx-loop v1 - PR-Aware Orchestration Surface

## Overview

`dx-loop` is a PR-aware orchestration surface that reuses Ralph's proven patterns (baton, topological dependencies, checkpoint/resume) while replacing the control plane with governed `dx-runner` dispatch and enforcing PR artifact contracts.

Current baton contract:
- implement prompts are shaped using the `prompt-writing` outbound structure
- implementers must return a `tech-lead-handoff` compatible `MODE: implementation_return`
- review prompts consume that structured return and enforce the `dx-loop-review-contract`

## When To Use

- Running multi-wave Beads execution with PR artifact requirements
- Orchestrating implementer/reviewer cycles with governed dispatch
- Automating wave advancement with noise-suppressed notifications
- Enforcing PR artifact contract (PR_URL + PR_HEAD_SHA) for completion

## Quick Start

```bash
# Install or refresh canonical operator shims in ~/bin
dx-ensure-bins.sh

# Start wave from Beads epic
dx-loop start --epic bd-5w5o

# Check wave status
dx-loop status --wave-id wave-2026-03-08T12-00-00Z

# Get JSON output
dx-loop status --wave-id <id> --json
```

## Commands

### start

```bash
dx-loop start --epic <epic-id> [--wave-id <id>] [--config <path>]
```

Starts a wave from a Beads epic, loading tasks and computing topological layers.

Default operator protection:
- if the initial frontier has zero dispatchable tasks, `dx-loop` persists the
  blocked state and exits instead of sitting resident for hours with no
  implementation progress

### status

```bash
dx-loop status [--wave-id <id>] [--json]
```

Shows wave status or lists all waves if no `--wave-id` provided.

For zero-dispatch waves, status now distinguishes generic pending from
dependency-blocked frontiers. When no task is dispatchable because upstream
dependencies are still unmet, operators see:

- `State: waiting_on_dependency`
- `Blocker Code: waiting_on_dependency`
- `Waiting on dependencies:` with the blocked task ids and unmet dependency ids

The JSON state includes the same detail under `wave_status.blocked_details` for
automation.

When this happens on the very first frontier, the reason text explains that the
loop exited without becoming a resident unattended process.

## Ralph Reuse

dx-loop reuses from Ralph (scripts/ralph/beads-parallel.sh):

| Concept | Ralph Lines | dx-loop Module |
|---------|-------------|----------------|
| Topological dependency layering | 138-268 | beads_integration.py |
| Implementer/reviewer baton | 210-312 | baton.py |
| Checkpoint/resume | 123-134, 507-520 | state_machine.py |
| Orchestrator-owned completion | 369-375 | beads_integration.py |

## Ralph Replacement

dx-loop replaces from Ralph:

| Ralph | Replacement |
|-------|-------------|
| Curl/session control plane | dx-runner substrate |
| Implicit success semantics | Explicit PR artifact contract |
| Temp-workdir assumptions | Worktree-first with bootstrap gates |
| Hardcoded runtime | Configurable profiles |

## dx-loop Additions

| Addition | Description |
|----------|-------------|
| dx-runner substrate | All execution via dx-runner adapters |
| Bootstrap gates | Host/worktree/prompt locality checks |
| PR artifact contract | PR_URL + PR_HEAD_SHA required |
| Structured handoff contract | `implementation_return` required before review |
| Merge-ready detection | Predicate over PR + CI checks |
| Blocker taxonomy | 6 codes with deterministic classification |
| Unchanged suppression | Only emit when state materially changes |
| Low-noise notifications | Interrupt only for actionable states |
| Wave advancement | Beads-driven next-wave selection |

## Blocker Taxonomy

| Code | Meaning | Next Action |
|------|---------|-------------|
| `kickoff_env_blocked` | Bootstrap/worktree/host gates failed | Fix bootstrap environment |
| `run_blocked` | dx-runner execution blocked | Wait or switch provider |
| `review_blocked` | Reviewer verdict blocked | Address review findings |
| `waiting_on_dependency` | No ready tasks because upstream deps are unmet | Wait for upstream work to complete |
| `deterministic_redispatch_needed` | Stalled/timeout, safe to retry | Automatic redispatch |
| `needs_decision` | Requires human decision | Human intervention required |
| `merge_ready` | PR artifacts present, checks passing | Human merge approval |

## PR Artifact Contract

dx-loop enforces that implementations produce PR artifacts:

```
PR_URL: https://github.com/<org>/<repo>/pull/<number>
PR_HEAD_SHA: <40-char-sha>
```

Missing PR artifacts means incomplete, not success.

## Wave 0 Pilot: Operator Notification Contract

The Wave 0 pilot established the actionable notification contract and proved MVP viability through two acceptance tests.

### Actionable Notification States

dx-loop interrupts operators **only** for actionable states:

| State | Interrupt? | Reason |
|-------|------------|--------|
| `merge_ready` | YES | PR ready for human merge |
| `blocked` (kickoff_env, run, review) | YES | Intervention required |
| `needs_decision` | YES | Human decision required |
| `waiting_on_dependency` | NO | Automatic resolution when upstream completes |
| `deterministic_redispatch_needed` | NO | Auto-retry handles it |
| `healthy/pending` | NO | No intervention needed |

**Suppression**: Unchanged blocker repeats are suppressed. Only first occurrence emits.

### CLI Notification Format

Notifications include the exact Beads ID for takeover/resume commands:

```
[BLOCKED] Worktree missing for task
  Task: Implement OAuth flow (bd-abc123)
  Next: Fix bootstrap environment
```

Format rules:
- When `task_title` is present: `Task: <title> (<beads_id>)`
- When no title: `Task: <beads_id>`

The Beads ID is always visible for operators to use with `takeover`/`resume`.

### Human Takeover / Resume

When automation stalls, operators can take over and resume later:

```bash
# Take over a stalled task (stops automation for that task)
dx-loop takeover --wave-id wave-2026-03-08T12-00-00Z --beads-id bd-abc123 --note "Fixing manually"

# Resume automation after manual fix
dx-loop resume --wave-id wave-2026-03-08T12-00-00Z --beads-id bd-abc123
```

**What happens on takeover**:
- Task enters `manual_takeover` phase
- Scheduler clears active/blocked state for that task
- Loop skips dispatch and progress checks for takeover tasks
- Operator can work in the worktree without loop interference

**What happens on resume**:
- Task restores to previous phase (`implement` or `review`)
- Scheduler state cleared for clean redispatch
- Loop resumes normal dispatch cycle

### MVP Acceptance Tests

**Test A: Unattended Default-Path Wave** — *PASSED*

A 2-task stacked wave where Task B depends on Task A:
1. Task A: Implemented by OpenCode, reviewed by cc-glm → merge-ready
2. Task B: Implemented off Task A's PR branch, reviewed → merge-ready
3. Wave exited gracefully without operator babysitting

**Proved**: The unattended automation gap is closed for nominal execution paths.

**Test B: Human Takeover / Resume Path** — *PASSED*

A single task designed to stall:
1. Task A implemented but operator intervenes during revision
2. Operator uses `dx-loop takeover` to pause automation
3. Operator fixes manually and runs `dx-loop resume`
4. Loop adopts the resolution and exits cleanly

**Proved**: The glass-box escape hatch works — operators never feel trapped by the loop.

## Configuration

Default: `configs/dx-loop/default_config.yaml`

Override with `--config` flag or environment variables.

## Artifacts

```
/tmp/dx-loop/
├── waves/<wave-id>/
│   ├── loop_state.json          # Loop state
│   ├── logs/                     # Wave logs
│   └── outcomes/                 # Wave outcomes
└── prompts/                      # Generated prompts
```

## Related

- ADR: docs/adr/ADR-DX-LOOP-V1.md
- Ralph: scripts/ralph/beads-parallel.sh
- dx-runner: extended/dx-runner/SKILL.md
- Epic: bd-5w5o

Base directory for this skill: file:///home/fengning/.agents/skills/dx-loop
Relative paths in this skill (e.g., scripts/, configs/) are relative to this base directory.
