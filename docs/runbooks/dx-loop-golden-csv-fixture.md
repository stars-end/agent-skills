# dx-loop Golden CSV Fixture — Operator Runbook

## Purpose

Deterministic end-to-end requalification harness for `dx-loop`. Uses a trivial CSV append workflow that exercises:

- first-use task lookup before a wave exists
- epic bootstrap and wave materialization
- dependency advancement through a chain
- one fork and one join
- terminal retirement

## Beads Graph Shape

```
.1 (no deps)
 └── .2 (depends on .1)
      ├── .3 (depends on .2)
      │    └── .5 (depends on .3 AND .4)
      └── .4 (depends on .2)
```

Each task appends one deterministic line to a CSV file.

## Prerequisites

- `bd` CLI available and connected to a Beads Dolt backend
- `dx-loop` available in PATH
- Python 3.9+

## Step-by-Step Execution

### 1. Create a Fresh Beads Epic

```bash
cd ~/agent-skills
python3 fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py
```

This prints the new epic id (e.g. `bd-abc123`). Use this as `<EPIC_ID>` below.

For a dry-run (no Beads writes):

```bash
python3 fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py --dry-run
```

### 2. Create a Fresh Local Run Directory

```bash
python3 fixtures/dx_loop/golden_csv/scripts/create_run.py
```

This prints a run-id (e.g. `golden-csv-20260405T153000Z`).

Optionally specify a custom run-id:

```bash
python3 fixtures/dx_loop/golden_csv/scripts/create_run.py --run-id my-test-001
```

The run directory is created at `/tmp/dx-loop-fixtures/golden-csv/<run-id>/`.

Set an environment variable for convenience:

```bash
RUN_DIR="/tmp/dx-loop-fixtures/golden-csv/<run-id>"
```

### 3. Pre-start Checks

Before any wave exists, verify that `dx-loop` provides actionable guidance:

```bash
dx-loop status --beads-id <EPIC_ID>.1
dx-loop explain --beads-id <EPIC_ID>.1
```

**Pass**: returns actionable first-use guidance (not raw error text, not hanging).

### 4. Bootstrap the Wave

```bash
dx-loop start --epic <EPIC_ID>
```

**Pass**:
- a persisted wave is materialized
- `dx-loop status --epic <EPIC_ID> --json` reports a live wave id
- the initial dispatch frontier contains only `.1`

### 5. Execute Tasks

For each task, the delegated agent or operator runs:

```bash
python3 fixtures/dx_loop/golden_csv/scripts/append_line.py \
  --run-dir "$RUN_DIR" --task-index <N>
```

Task execution order must respect dependencies:

| Wave | Tasks | Reason |
|------|-------|--------|
| 1 | .1 | No dependencies |
| 2 | .2 | Depends on .1 |
| 3 | .3, .4 | Both depend on .2 (fork) |
| 4 | .5 | Depends on .3 AND .4 (join) |

### 6. Mid-run Verification

After `.1` completes:
- only `.2` should become dispatchable

After `.2` completes:
- `.3` and `.4` should both become dispatchable

After `.3` and `.4` both complete:
- `.5` should become dispatchable

Check with:

```bash
dx-loop status --epic <EPIC_ID> --json
dx-loop explain --epic <EPIC_ID>
```

**Fail if**: stale frontier, dispatch before deps complete, or false blocking.

### 7. Validate the Run

```bash
python3 fixtures/dx_loop/golden_csv/scripts/validate_run.py --run-dir "$RUN_DIR"
```

**Pass conditions**:
- Exit code 0
- `validation.json` has `"valid": true`
- `output.csv` exactly matches `expected.csv`:
  ```
  line 1
  line 2
  line 3
  line 4
  line 5
  ```
- No duplicate, missing, or extra lines
- Order is correct

**Fail conditions**:
- Duplicate lines
- Missing lines
- Extra lines
- Wrong order
- Non-zero exit code

### 8. Terminal Retirement Check

```bash
dx-loop status --epic <EPIC_ID> --json
dx-loop explain --epic <EPIC_ID>
```

**Pass**:
- No stale dispatchable tasks
- Operator surfaces do not claim more work remains

**Fail**:
- Closed epic still appears actionable
- Stale frontier after completion

## Pass/Fail Contract Summary

| Phase | Pass | Fail |
|-------|------|------|
| Pre-start | Actionable first-use guidance | Raw error or hang |
| Bootstrap | Persisted wave, frontier = {.1} | No wave or invalid frontier |
| Mid-run | Correct dependency unlocking | Stale/false frontier |
| Artifact | Exact CSV match | Duplicates/missing/wrong order |
| Terminal | No stale dispatchable tasks | Ghost frontier |

## File Reference

| File | Purpose |
|------|---------|
| `fixtures/dx_loop/golden_csv/template/expected.csv` | Canonical expected output |
| `fixtures/dx_loop/golden_csv/template/run_spec.json` | Graph shape, line mapping, assertions |
| `fixtures/dx_loop/golden_csv/scripts/create_run.py` | Create fresh run directory |
| `fixtures/dx_loop/golden_csv/scripts/append_line.py` | Append one line to output.csv |
| `fixtures/dx_loop/golden_csv/scripts/validate_run.py` | Validate final output |
| `fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py` | Create fresh Beads epic |

## Local Run Layout

```
/tmp/dx-loop-fixtures/golden-csv/<run-id>/
├── output.csv          # Task append output
├── run.json            # Run metadata and append log
└── validation.json     # Validation verdict (after validate_run.py)
```

## Repeatability

- The template is stored in the repo (not a hard-coded live run)
- Each run creates a fresh Beads epic from the template
- Each run creates a fresh local directory under a unique run-id
- Old runs are ignored by default
- No manual cleanup required between runs
