# dx-loop Golden CSV Fixture Requalification

## Summary

Create a canonical low-risk `dx-loop` requalification fixture that exercises:

- first-use task lookup before any wave exists
- epic bootstrap and wave materialization
- dependency advancement through a chain
- one fork and one join
- terminal retirement after all work is complete

The business logic stays intentionally trivial: each task appends one deterministic line to a CSV file.

This fixture exists to answer one question cleanly:

> can `dx-loop` orchestrate a small chained Beads epic end-to-end without product-specific ambiguity?

## Scope

In scope:

- a saved Beads epic template shape for repeated requalification runs
- fixture files in `agent-skills`
- deterministic pass/fail checks
- repeatable run/reset mechanics with no manual cleanup
- a delegated implementation prompt contract

Out of scope:

- product code
- broad `dx-loop` redesign
- benchmarking agent quality

## Canonical Beads Epic Shape

Each requalification run should instantiate a fresh Beads epic from the same template.

Recommended epic title:

- `Golden dx-loop CSV requalification run`

Recommended child shape:

1. `.1` `Append line 1`
   - no dependencies
2. `.2` `Append line 2`
   - depends on `.1`
3. `.3` `Append line 3`
   - depends on `.2`
4. `.4` `Append line 4`
   - depends on `.2`
5. `.5` `Append line 5`
   - depends on `.3`
   - depends on `.4`

This gives the minimum useful graph:

- one linear prefix
- one fork
- one join

## Task Contract

Every task does exactly one append to the current run CSV.

Expected task behavior:

1. open the run-specific CSV file
2. append the exact line assigned to the task
3. do not reorder, rewrite, or deduplicate existing lines
4. exit cleanly after the append

Assigned lines:

- `.1` -> `line 1`
- `.2` -> `line 2`
- `.3` -> `line 3`
- `.4` -> `line 4`
- `.5` -> `line 5`

## Fixture Files

Recommended repo paths:

- `docs/runbooks/dx-loop-golden-csv-fixture.md`
  - operator runbook
- `fixtures/dx_loop/golden_csv/template/expected.csv`
  - canonical expected final output
- `fixtures/dx_loop/golden_csv/template/run_spec.json`
  - graph shape, line mapping, and assertions
- `fixtures/dx_loop/golden_csv/scripts/create_run.py`
  - creates a new run directory and unique run id
- `fixtures/dx_loop/golden_csv/scripts/append_line.py`
  - appends the requested line to the current run CSV
- `fixtures/dx_loop/golden_csv/scripts/validate_run.py`
  - validates final output and emits machine-readable verdict
- `fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py`
  - creates a fresh Beads epic + subtasks from the template

## Run Layout

Each run should use a unique run directory under a stable fixture root, for example:

- `/tmp/dx-loop-fixtures/golden-csv/<run-id>/`

Per-run contents:

- `output.csv`
- `run.json`
- `validation.json`

`run-id` should be generated automatically, for example:

- `golden-csv-20260405T153000Z`

## Exact Pass/Fail Contract

### Pre-start

Pass:

- `dx-loop status --beads-id <subtask>` returns actionable first-use guidance if no wave exists yet
- `dx-loop explain --beads-id <subtask>` returns actionable blocker diagnosis if no wave exists yet

Fail:

- raw missing-wave text with no next action
- hanging status/explain calls

### Bootstrap

Pass:

- `dx-loop start --epic <epic-id>` materializes a persisted wave
- `dx-loop status --epic <epic-id> --json` reports a live wave id
- the initial dispatch frontier is only `.1`

Fail:

- no usable wave created
- startup exits as success without dispatch
- frontier includes tasks whose dependencies are not satisfied

### Mid-run Dependency Advancement

Pass:

- after `.1` completes, only `.2` becomes dispatchable
- after `.2` completes, `.3` and `.4` become dispatchable
- `.5` does not become dispatchable until both `.3` and `.4` are terminal

Fail:

- stale frontier after a completed task
- downstream task dispatch before dependencies complete
- blocked state without truthful cause

### Artifact Integrity

Pass:

- final `output.csv` is exactly:
  - `line 1`
  - `line 2`
  - `line 3`
  - `line 4`
  - `line 5`
- each line appears exactly once
- no extra lines are present

Fail:

- duplicate lines
- missing lines
- incorrect order

### Terminal Retirement

Pass:

- epic reaches terminal/inert state after `.5`
- `dx-loop status --epic <epic-id> --json` shows no stale dispatch frontier
- `dx-loop explain --epic <epic-id>` does not claim more work remains

Fail:

- closed epic still appears actionable
- stale children remain dispatchable

## Repeatability Without Manual Cleanup

The fixture should be rerunnable without hand-editing files or reopening old Beads issues.

Required design:

1. the repo stores a template, not a single hard-coded live run
2. each execution creates a fresh run id and fresh output directory
3. each execution creates a fresh Beads epic from the template
4. validation reads only the current run directory
5. cleanup is automatic because old runs are ignored by default

Optional helper:

- `fixtures/dx_loop/golden_csv/scripts/prune_runs.py`
  - delete old local run directories beyond a retention limit

Recommended operator flow:

1. create a fresh Beads epic from template
2. create a fresh local run directory
3. run `dx-loop` against that epic
4. validate the current run directory
5. keep prior runs as archived evidence unless pruned automatically

## Minimal Operator Workflow

1. `instantiate_epic.py` creates a fresh epic and prints the new epic id
2. `create_run.py` creates the run directory and prints the run id
3. operator runs `dx-loop start --epic <epic-id>`
4. operator uses `dx-loop status` / `dx-loop explain` during execution
5. `validate_run.py` verifies final output and writes `validation.json`

## Acceptance For Implementation

1. Canonical fixture files exist in `agent-skills`
2. A new run can be created without editing source files
3. A fresh Beads epic can be instantiated from the saved template
4. Validation is deterministic and machine-readable
5. The runbook tells operators exactly how to execute and verify the fixture

## Recommended Future Use

Use this fixture as the standard `dx-loop` requalification gate:

- after control-plane bug fixes
- before reusing `dx-loop` on product-critical waves
- when comparing behavior across hosts or canonical VMs
