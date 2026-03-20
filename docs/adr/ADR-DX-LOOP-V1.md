# ADR: dx-loop v1 - PR-Aware Orchestration Surface

## Status
ACCEPTED - 2026-03-20

Functional contract frozen at `docs/dx-loop/DX-LOOP-V1-FUNCTIONAL-CONTRACT.md`

## Context

The current orchestration landscape has two systems:
1. **Ralph** (beads-parallel.sh): Proven baton/dependency logic but uses curl/session control plane
2. **dx-runner** + **dx-batch**: Governed dispatch with unified governance but lacks PR-aware orchestration

This creates a gap: Ralph's orchestration logic is sound, but its control plane is non-canonical and lacks PR artifact enforcement.

## Decision

Create **dx-loop v1** as a synthesis of Ralph's proven patterns with dx-runner's governed substrate:

### What we REUSE from Ralph

From `scripts/ralph/beads-parallel.sh`:

1. **Topological dependency layering** (lines 138-268)
   - Kahn's algorithm for execution layers
   - Parallel execution within layers
   - Dependency-aware dispatch

2. **Implementer/reviewer baton semantics** (lines 210-312)
   - Explicit IMPLEMENT → REVIEW phases
   - Structured verdicts (APPROVED, REVISION_REQUIRED, BLOCKED)
   - Retry bounds with deterministic termination

3. **Checkpoint/resume concepts** (lines 123-134, 507-520)
   - Wave state persistence after each layer
   - Resume from checkpoint on failure
   - Progress tracking across restarts

4. **Orchestrator-owned completion semantics** (lines 369-375)
   - Task closure owned by orchestrator, not implementers
   - Beads integration for status updates
   - Clean separation of concerns

### What we REPLACE from Ralph

1. **Curl/session control plane** (lines 108-161)
   - **Replace with:** `dx-runner` substrate
   - Use `dx-runner start/check/report` for all execution
   - Leverage unified governance (preflight, permission gates, heartbeat)

2. **Implicit success semantics** (lines 277-309)
   - **Replace with:** Explicit PR artifact contract
   - Missing `PR_URL` / `PR_HEAD_SHA` = incomplete, not success
   - Draft PR required after first real commit

3. **Temp-workdir assumptions** (lines 46-48)
   - **Replace with:** Worktree-first with hard bootstrap gates
   - Host/worktree/prompt locality checks before dispatch
   - Permission gate enforcement via dx-runner

4. **Hardcoded runtime behavior** (lines 33-41)
   - **Replace with:** Configurable profiles
   - `configs/dx-loop/default_config.yaml`
   - `configs/dx-loop/blocker_taxonomy.yaml`

### What we ADD (dx-loop specific)

1. **dx-runner substrate**
   - All execution goes through `dx-runner` adapters
   - Unified governance: preflight, permission gates, heartbeat, baseline/integrity gates

2. **Hard bootstrap gates**
   - Beads health check before wave start
   - Host reachability validation
   - Worktree validity and permission checks
   - Prompt-file locality enforcement

3. **PR artifact contract**
   - `PR_URL`: Required for completion
   - `PR_HEAD_SHA`: 40-char hex SHA, validated
   - Extracted from implementer output, not assumed

4. **Merge-ready detection**
   - Predicate over PR artifacts + CI checks
   - Merge-ready state classification
   - Human merge approval preserved (no auto-merge)

5. **Blocker taxonomy**
   ```
   kickoff_env_blocked      - Bootstrap/worktree/host gates failed
   run_blocked              - dx-runner execution blocked (not stalled)
   review_blocked           - Reviewer verdict blocked
   waiting_on_dependency    - zero-dispatch wave blocked on upstream deps
   deterministic_redispatch_needed - Stalled/timeout, safe to retry
   needs_decision           - Requires human decision
   merge_ready              - PR artifacts present, checks passing
   ```

6. **Unchanged-blocker suppression**
   - Hash-based detection of repeated identical states
   - Only emit every N occurrences (configurable)
   - Reduce operator noise from spam loops

7. **Low-noise operator notifications**
   - Interrupt only for: `merge_ready`, `blocked`, `needs_decision`
   - Suppress: unchanged blockers, healthy/pending states
   - Slack webhook support (optional)

8. **Beads-driven wave advancement**
   - Use Beads dependency graph for next-wave selection
   - Automatic ready-task discovery
   - Multi-wave execution without manual scheduling

## Architecture

```
dx-loop v1
├── scripts/dx_loop.py              # Main orchestration module
├── scripts/dx-loop                  # CLI wrapper
├── scripts/lib/dx_loop/
│   ├── state_machine.py            # Loop state with blocker taxonomy
│   ├── baton.py                    # Implementer/reviewer cycle
│   ├── blocker.py                  # Blocker classification + suppression
│   ├── pr_contract.py              # PR artifact enforcement
│   ├── beads_integration.py        # Wave dependency advancement
│   └── notifications.py            # Low-noise operator notifications
├── configs/dx-loop/
│   ├── default_config.yaml         # Default configuration
│   └── blocker_taxonomy.yaml       # Blocker classification rules
└── tests/dx_loop/                  # Unit tests
```

## Command Surface

```bash
dx-ensure-bins.sh
dx-loop start --epic <epic-id> [--config <path>]
dx-loop status [--wave-id <id>] [--json]
dx-loop check --wave-id <id> [--json]
dx-loop report --wave-id <id> [--format json|markdown]
```

Operator contract:
- `dx-loop` is installed into `~/bin` by `scripts/dx-ensure-bins.sh`
- operators should invoke `dx-loop` from the canonical shim, not by source-diving
- zero-dispatch dependency-blocked waves surface as `waiting_on_dependency`
  with blocker detail in human-readable status and persisted JSON state
- if the initial frontier is fully blocked, `dx-loop` persists the blocked
  state and exits instead of remaining resident with zero dispatches

## Consequences

### Positive
- **Reuse, not rewrite**: Leverages proven Ralph patterns
- **Governed execution**: dx-runner substrate provides unified governance
- **PR artifact enforcement**: Every implementation produces a PR artifact
- **Noise reduction**: Unchanged-blocker suppression + selective notifications
- **Deterministic classification**: 6-blocker taxonomy with clear actions

### Negative
- **Migration effort**: Existing Ralph workflows need migration
- **Complexity**: More components than simple Ralph invocation
- **Dependency on dx-runner**: Requires dx-runner to be functional

### Mitigations
- Ralph continues to work for existing workflows (no breaking change)
- Clear migration guide in docs/DX-LOOP-V1-RUNBOOK.md
- dx-runner is required for DX V8 anyway (not new dependency)

## Related

- Epic: bd-5w5o - dx-loop v1 unified unattended orchestration
- Subtask: bd-5w5o.14 - Extract Ralph baton and dependency engine
- Subtask: bd-5w5o.15 - Replace Ralph control plane with dx-runner
- ADR: docs/adr/ADR-DX-V8-UNIFIED-DISPATCH.md
- Ralph: scripts/ralph/beads-parallel.sh
- dx-runner: scripts/dx-runner
