---
name: dx-batch
description: |
  Deterministic orchestration over dx-runner for autonomous implement->review waves.
  Orchestrates 2-3 parallel tasks across 15-20 Beads items with strict lease locking,
  persistent ledger, and machine-readable contracts. Use for batch execution of
  implementation tasks with automatic review cycles.
tags: [workflow, orchestration, batch, dx-runner, governance, parallel]
allowed-tools:
  - Bash
---

# dx-batch: Deterministic Batch Orchestration

## Overview

`dx-batch` is a thin deterministic state machine that orchestrates parallel tasks using `dx-runner` as the ONLY execution backend. It provides:

- **Orchestration-only**: Never calls model APIs directly
- **Strict lease locking**: Per-item locks scoped by `beads_id + attempt`
- **Persistent ledger**: Immutable run records per item
- **Machine-readable contracts**: JSON schemas for implement/review phases
- **Separate review runs**: Review is always a separate dx-runner invocation
- **Deterministic retry policy**: opencode -> cc-glm -> blocked
- **Process hygiene**: Max child jobs, stale PID pruning, guaranteed cleanup
- **Exec saturation guard**: Hard cap check before dispatch (`--exec-process-cap`, default 60)
- **Preflight gates**: Provider/model/auth readiness checks before dispatch

## Commands

### start
```bash
dx-batch start --items bd-aaa,bd-bbb,bd-ccc [--max-parallel 3] [--wave-id <id>]
# Override saturation cap if needed:
dx-batch start --items bd-aaa,bd-bbb --exec-process-cap 40
```

### status
```bash
dx-batch status --wave-id <id> [--json]
```

### resume
```bash
dx-batch resume --wave-id <id>
```

### cancel
```bash
dx-batch cancel --wave-id <id>
```

### doctor
```bash
dx-batch doctor --wave-id <id> [--json]
```

## State Machine

```
PENDING -> IMPLEMENTING -> REVIEWING -> APPROVED
    |           |              |
    v           v              v
    |      REVISION_REQUIRED  BLOCKED
    |           |              
    v           v              
  BLOCKED    (retry)           
```

## Artifacts

```
/tmp/dx-batch/
├── waves/<wave-id>/wave_state.json
├── leases/<wave-id>/<beads-id>+attempt<n>.lock
├── ledgers/<wave-id>/<beads-id>.ledger.jsonl
└── jobs/<wave-id>/<pid>.pid
```

## Testing

```bash
pytest -q /Users/fengning/agent-skills/tests/dx_batch
```

## Runtime Safety Notes

- `dx-batch start` automatically runs `dx-runner prune` before queue start.
- Every run-loop cycle performs a doctor check before launching new items.
- If live dispatch/runner processes exceed cap, wave fails fast with `exec_saturation`.
