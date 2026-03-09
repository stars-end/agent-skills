# Skill: dx-loop

# dx-loop v1 - PR-Aware Orchestration Surface

## Overview

`dx-loop` is a PR-aware orchestration surface that reuses Ralph's proven patterns (baton, topological dependencies, checkpoint/resume) while replacing the control plane with governed `dx-runner` dispatch and enforcing PR artifact contracts.

## When To Use

- Running multi-wave Beads execution with PR artifact requirements
- Orchestrating implementer/reviewer cycles with governed dispatch
- Automating wave advancement with noise-suppressed notifications
- Enforcing PR artifact contract (PR_URL + PR_HEAD_SHA) for completion

## Quick Start

```bash
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

### status

```bash
dx-loop status [--wave-id <id>] [--json]
```

Shows wave status or lists all waves if no `--wave-id` provided.

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
