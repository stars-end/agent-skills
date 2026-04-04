# dx-loop Startup Hydration Timeout

- CLASS: `dx_loop_control_plane`
- NOT_A_PRODUCT_BUG: `true`
- Beads: `bd-tbw1l.1`
- Authoritative source commit: `16d16e190bc8d2b954ddbd2d4ab5c2fc75bb7c7e`
- Scope: documentation and QA only

## Summary

`dx-loop` can fail its very first dispatch cycle for an open epic when Beads child hydration is slower than the hard-coded startup timeout budget.

In the reproduced `bd-tbw1l` startup wave, `dx-loop start --epic bd-tbw1l --repo agent-skills` resumed:

- `wave-2026-04-04-23-01-07Z`

The wave then exited immediately on iteration 1 with zero dispatches because most child tasks were marked blocked under:

- `task_metadata_unavailable: timeout`

This is a control-plane startup bug, not product behavior. The loop never reached a truthful “ready to dispatch” frontier because the startup hydration budget was shorter than real `bd show <task>` latency on this host.

## Severity / Impact

- Severity: major
- Impact:
  - first-pass orchestration can falsely classify a startable epic as blocked
  - `dx-loop start` exits without resident supervision and without real task execution
  - follow-up `dx-loop status` and `dx-loop explain` can time out under the same latency conditions
  - operator confidence in `dx-loop` startup truth is reduced exactly when maximal dogfooding needs it most

## Exact Reproduction Steps

Run from canonical `~/bd`:

```bash
dx-loop start --epic bd-tbw1l --repo agent-skills
dx-loop status --epic bd-tbw1l --json
dx-loop explain --epic bd-tbw1l
```

Measured child latency probes:

```bash
/usr/bin/time -p bd show bd-zeplg --json >/dev/null
/usr/bin/time -p bd show bd-p84ci --json >/dev/null
/usr/bin/time -p bd show bd-rk6xs --json >/dev/null
/usr/bin/time -p bd show bd-59esp --json >/dev/null
/usr/bin/time -p bd show bd-rae7t --json >/dev/null
/usr/bin/time -p bd show bd-2qzfu --json >/dev/null
```

Hydration simulation using the source commit under test:

```bash
python3 - <<'PY'
import sys
sys.path.insert(0, '/tmp/bd-tbw1l-context/source/scripts/lib')
from dx_loop.beads_integration import BeadsWaveManager
m = BeadsWaveManager(default_repo='agent-skills')
m.load_epic_tasks('bd-tbw1l')
r = m.describe_wave_readiness(timeout_seconds=3)
print('3s ready', r.ready)
print('3s waiting', len(r.waiting_on_dependencies))
print('3s loaded', sum(1 for t in m.tasks.values() if t.details_loaded), 'of', len(m.tasks))
PY
```

```bash
python3 - <<'PY'
import sys
sys.path.insert(0, '/tmp/bd-tbw1l-context/source/scripts/lib')
from dx_loop.beads_integration import BeadsWaveManager
m = BeadsWaveManager(default_repo='agent-skills')
m.load_epic_tasks('bd-tbw1l')
r = m.describe_wave_readiness(timeout_seconds=7)
print('7s ready', r.ready)
print('7s waiting', len(r.waiting_on_dependencies))
print('7s loaded', sum(1 for t in m.tasks.values() if t.details_loaded), 'of', len(m.tasks))
PY
```

## Observed Behavior

### Startup

`dx-loop start --epic bd-tbw1l --repo agent-skills` resumed the persisted wave and produced:

- `Wave ID: wave-2026-04-04-23-01-07Z`
- `No ready tasks: waiting on dependencies for 10 task(s)`
- `Initial frontier has zero dispatchable tasks; exiting without resident loop`

### Persisted Wave State

Persisted state at `/tmp/dx-loop/waves/wave-2026-04-04-23-01-07Z/loop_state.json` showed:

- `wave_status.state = waiting_on_dependency`
- `wave_status.blocker_code = waiting_on_dependency`
- `scheduler_state.dispatch_count = 0`
- `scheduler_state.active_beads_ids = []`
- most tasks blocked with:
  - `task_metadata_unavailable`
  - `dependency_statuses.task_metadata_unavailable = timeout`

Nine child tasks had:

- `details_loaded = false`
- `detail_load_error = "timeout"`

### Status / Explain

Both bounded probes timed out:

- `timeout 30 dx-loop status --epic bd-tbw1l --json` -> exit `124`
- `timeout 30 dx-loop explain --epic bd-tbw1l` -> exit `124`

## Expected Behavior

- startup should not classify the epic as dependency-blocked solely because hydration timed out below normal `bd show` latency
- if hydration is incomplete, the loop should surface a truthful startup-hydration/control-plane blocker rather than a dependency graph blocker
- operator surfaces should remain responsive and actionable even when startup hydration is slow

## Root Cause Analysis

### Primary Cause

The startup hydration timeout policy is mismatched to real Beads latency on this host.

From the source commit:

- `BeadsWaveManager.load_epic_tasks()` hydrates:
  - first open child with a `10s` timeout
  - later open children with a `3s` timeout
- `describe_wave_readiness()` defaults to:
  - `timeout_seconds = 3`

In practice, representative `bd show <task>` calls measured around `5.9s` to `6.5s`, which is well above the `3s` budget.

That means startup does this:

1. load the first open child successfully under `10s`
2. time out on most later children under `3s`
3. carry those children into readiness as `task_metadata_unavailable: timeout`
4. conclude there are zero dispatchable tasks
5. exit the startup loop before any real work is dispatched

### Why This Is a `dx_loop_control_plane` Bug

- the product epic was open and had real work
- the control plane failed before dispatching anything
- `dx-loop` converted a startup hydration problem into a blocked frontier diagnosis
- no product code or prompt content caused the failure

This is therefore a startup orchestration bug in the control plane.

## Why Duplicate Beads Children Were Noise, Not the Primary Blocker

`bd-tbw1l` contains multiple semantically similar child issues. That is real epic hygiene noise, but it is not the main reason startup failed.

Evidence:

- with `timeout_seconds=3`, only `1/11` tasks hydrated and there were no ready tasks
- with `timeout_seconds=7`, all `11/11` tasks hydrated and ready tasks appeared immediately:
  - `bd-6hojm`
  - `bd-p84ci`
  - `bd-rae7t`
  - `bd-tbw1l.1`
  - `bd-zeplg`

This means the dominant blocker was not “duplicate children make the graph impossible”; it was “the graph was never hydrated truthfully under the active timeout budget.”

Nuance:

- the original dogfood report referred to `10` tasks
- this validation shows `11` open children because `bd-tbw1l.1` now exists as an additional child
- that difference changes the count, not the root cause

## Evidence Table

| Evidence | Result |
| --- | --- |
| `dx-loop start --epic bd-tbw1l --repo agent-skills` | resumed `wave-2026-04-04-23-01-07Z`, exited on iteration 1 with zero dispatches |
| persisted `wave_status.state` | `waiting_on_dependency` |
| persisted blocker detail | `task_metadata_unavailable: timeout` on most children |
| persisted dispatch count | `0` |
| `timeout 30 dx-loop status --epic bd-tbw1l --json` | timed out (`124`) |
| `timeout 30 dx-loop explain --epic bd-tbw1l` | timed out (`124`) |
| `/usr/bin/time -p bd show bd-zeplg --json` | `real 6.47s` |
| `/usr/bin/time -p bd show bd-p84ci --json` | `real 5.97s` |
| `/usr/bin/time -p bd show bd-rk6xs --json` | `real 5.88s` |
| `/usr/bin/time -p bd show bd-59esp --json` | `real 6.31s` |
| `/usr/bin/time -p bd show bd-rae7t --json` | `real 6.16s` |
| `/usr/bin/time -p bd show bd-2qzfu --json` | `real 6.20s` |
| simulation with `timeout_seconds=3` | `ready=[]`, `waiting=11`, `loaded=1 of 11` |
| simulation with `timeout_seconds=7` | `ready=['bd-6hojm','bd-p84ci','bd-rae7t','bd-tbw1l.1','bd-zeplg']`, `waiting=6`, `loaded=11 of 11` |

## Candidate Remediations

### 1. Raise or tier startup hydration time budgets

Use a larger startup/readiness timeout for first-pass epic hydration, not the same `3s` budget used for tighter inner-loop checks.

Why:

- current host latency already exceeds `3s` for normal `bd show` calls
- startup is the worst place to optimize for an unrealistically small timeout

### 2. Distinguish hydration failure from dependency blocking

When child metadata cannot be loaded, surface a startup-hydration blocker explicitly instead of folding it into `waiting_on_dependency`.

Why:

- `task_metadata_unavailable: timeout` is not the same operator action as a genuine unresolved dependency edge
- this would make `start`, `status`, and `explain` more truthful

### 3. Persist partial hydration diagnostics and remain observable

If startup exits early with zero dispatches, preserve a fast, actionable surface that reports:

- how many children loaded
- how many timed out
- which timeout budget was used
- the next suggested operator action

Why:

- current `status` / `explain` timing out compounds the original startup failure

## Open Questions / Follow-up Checks

1. Should startup use a dedicated hydration timeout budget separate from cadence-time reconciliation?
2. Should `describe_wave_readiness()` accept a startup mode that tolerates slower detail hydration?
3. Should timed-out children be retried before converting the whole frontier to `waiting_on_dependency`?
4. Why do `status` and `explain` still time out after the failed startup instead of quickly reporting the persisted blocked state?
5. Should duplicate/overlapping epic children be linted separately so operator noise is reduced even when hydration succeeds?

## Validation Notes

`llm-tldr` tool routing was attempted via CLI search from the worktree, but it returned no matches for known dx-loop symbols in this environment. Direct file inspection was used to complete the code-path validation.
