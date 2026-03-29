# Skill: dx-loop

# dx-loop v1 - PR-Aware Orchestration Surface

## Overview

`dx-loop` is the default execution surface for chained Beads work, multi-step outcomes, and implement/review baton flows. It is a PR-aware orchestration surface that reuses Ralph's proven patterns (baton, topological dependencies, checkpoint/resume) while replacing the control plane with governed `dx-runner` dispatch and enforcing PR artifact contracts.

## Default Execution Policy

Use `dx-loop` as the default execution surface for:
- chained Beads work
- multi-step outcomes
- tasks expected to need implement -> review baton flow

Use direct/manual implementation only when:
- the task is an isolated single-task change with no meaningful baton benefit
- `dx-loop` itself is the active blocker

When `dx-loop` is the blocker, stop with a truthful blocker report and track the control-plane issue separately from the product epic.

Current baton contract:
- implement prompts are shaped using the `prompt-writing` outbound structure
- implementers must return a `tech-lead-handoff` compatible `MODE: implementation_return`
- review prompts consume that structured return and enforce the `dx-loop-review-contract`

## When To Use

- Default lane for chained and non-trivial Beads execution
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

# If the epic is single-repo but Beads metadata is repo-less, provide an explicit fallback
dx-loop start --epic bd-jx1t --repo prime-radiant-ai

# Check task-oriented status
dx-loop status --beads-id bd-5w5o.49

# Explain why a task is blocked or what to do next
dx-loop explain --beads-id bd-5w5o.49

# Get JSON output
dx-loop status --wave-id <id> --json
```

## Commands

### start

```bash
dx-loop start --epic <epic-id> [--wave-id <id>] [--config <path>] [--repo <repo>]
```

Starts a wave from a Beads epic, loading tasks and computing topological layers.

Default operator protection:
- if the initial frontier has zero dispatchable tasks, `dx-loop` persists the
  blocked state and exits instead of sitting resident for hours with no
  implementation progress
- `dx-loop` prints the wave id immediately and persists a minimal state record
  before bootstrap completes, so startup issues remain queryable

Use `--repo <repo>` when:
- the epic is known to target one repo
- but Beads task metadata does not currently resolve a unique repo

This sets a deterministic wave-level default repo for repo-less tasks without
changing mixed-repo behavior when task metadata is already explicit.

### status

```bash
dx-loop status [--wave-id <id> | --epic <id> | --beads-id <id>] [--json]
```

Shows wave status or lists all waves if no selector is provided.

Use:
- `--wave-id` when you already know the wave
- `--epic` to resolve the newest persisted wave for an epic
- `--beads-id` to resolve the newest persisted wave containing that task

When `--beads-id` is provided, status also surfaces the task title, repo, and baton phase so agents do not need to inspect raw state files.

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

### explain

```bash
dx-loop explain --beads-id <id>
dx-loop explain --epic <id>
dx-loop explain --wave-id <id>
```

Provides an agent-native explanation of the current state:
- wave id and epic id
- task-local title and phase when a task is selected
- blocker code
- surface classification: `product`, `control_plane`, `dependency`, or `none`
- next-action guidance

Use this as the first blocker diagnosis command before inspecting raw wave JSON or runner internals.

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

## Actionable Notification Contract

dx-loop emits notifications only for actionable states requiring operator attention.

**Emitted**:
- `merge_ready`: PR artifacts present, CI passing → Review and merge
- `blocked`: kickoff_env, run, review blocked → Fix environment or wait
- `needs_decision`: Human intervention required → Inspect logs

**Suppressed**:
- `waiting_on_dependency`: Automatic - upstream work in progress
- `deterministic_redispatch_needed`: Automatic retry in progress
- Unchanged blockers: Same state as last notification

**Notification payload fields**:
- `beads_id`: Task ID (e.g., `bd-5w5o.37.3`)
- `wave_id`: Wave identifier (e.g., `wave-2026-03-24T12:00:00Z`)
- `provider`: Execution provider (e.g., `opencode`, `cc-glm`)
- `phase`: Current phase (`implement`, `review`, `merge`)
- `pr_url`: PR link (merge_ready only)
- `pr_head_sha`: Commit SHA (merge_ready only)
- `next_action`: What operator should do

**Full documentation**: `docs/runbook/dx-loop/NOTIFICATION_CONTRACT.md`

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
- Notification Contract: docs/runbook/dx-loop/NOTIFICATION_CONTRACT.md
- Epic: bd-5w5o

Base directory for this skill: file:///home/fengning/.agents/skills/dx-loop
Relative paths in this skill (e.g., scripts/, configs/) are relative to this base directory.
