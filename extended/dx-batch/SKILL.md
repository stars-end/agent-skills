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

### check
```bash
dx-batch check --wave-id <id> [--json]
```

### report
```bash
dx-batch report --wave-id <id> [--format json|markdown]
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
pytest -q ~/agent-skills/tests/dx_batch
```

## Runtime Safety Notes

- `dx-batch start` automatically runs `dx-runner prune` before queue start.
- Every run-loop cycle performs a doctor check before launching new items.
- If live dispatch/runner processes exceed cap, wave fails fast with `exec_saturation`.

## Exec Saturation Incident Runbook (bd-cbsb.27)

```bash
# 1) Diagnose wave state + stale leases/pids
dx-batch doctor --wave-id <wave-id> --json

# 2) Prune stale dx-runner records
dx-runner prune --json

# 3) Re-run in degraded mode for containment
dx-batch start --items <bd-a,bd-b,...> --max-parallel 1 --exec-process-cap 20
```

Stop conditions before redispatch:
- `doctor` returns critical issues you cannot clear
- `dx-runner prune` keeps reporting stale jobs repeatedly
- external process count remains above cap after cleanup

## Capability Fallback (dx-wave wrapper)

- Preferred batch entrypoint: `dx-wave batch-start ...`
- If `dx-batch` is unavailable on PATH, wrapper emits:
  - `WARN_CODE=dx_batch_unavailable_fallback_runner`
- Fallback behavior is deterministic:
  - dispatch each beads item through `dx-runner start`
  - preserve profile/provider policy
