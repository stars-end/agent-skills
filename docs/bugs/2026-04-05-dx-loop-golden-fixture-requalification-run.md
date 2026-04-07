# dx-loop Golden CSV Fixture Requalification Run

**Date**: 2026-04-05
**CLASS**: dx_loop_control_plane
**NOT_A_PRODUCT_BUG**: true

## Fixture IDs

| Role | ID |
|------|-----|
| Epic | bd-l14dx |
| .1 Append line 1 | bd-l14dx.1 |
| .2 Append line 2 | bd-l14dx.2 |
| .3 Append line 3 | bd-l14dx.3 |
| .4 Append line 4 | bd-l14dx.4 |
| .5 Append line 5 | bd-l14dx.5 |
| Run ID | qa-run-001 |
| Run dir | /tmp/dx-loop-fixtures/golden-csv/qa-run-001 |

All issues closed post-run.

## Commands Run

1. `python3 fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py --dry-run`
2. Manual `bd create` calls to build the 5-task fork/join graph
3. `python3 fixtures/dx_loop/golden_csv/scripts/create_run.py --run-id qa-run-001`
4. `dx-loop status --beads-id bd-l14dx.1` (before wave)
5. `dx-loop explain --beads-id bd-l14dx.1` (before wave)
6. `dx-loop start --epic bd-l14dx` (without --repo)
7. `dx-loop status --epic bd-l14dx --json`
8. `dx-loop explain --epic bd-l14dx`
9. `dx-loop start --epic bd-l14dx --repo agent-skills` (second attempt)
10. `append_line.py --run-dir ... --task-index 1..5` (all 5 tasks)
11. `python3 fixtures/dx_loop/golden_csv/scripts/validate_run.py --run-dir ...`

## Results by Phase

### A. First-Use Lookup — PASS

`dx-loop status --beads-id bd-l14dx.1` before any wave:

```
Wave state not found for bd-l14dx.1
Blocker Class: control_plane_missing_wave_state
First-use guidance: start a wave for the parent epic, then retry this task lookup.
`dx-loop start --epic bd-l14dx`
```

Both `status` and `explain` returned actionable guidance with the exact next command.
No raw missing-wave dead-end. No hang.

### B. Bootstrap — PARTIAL PASS

**Without `--repo`:**

`dx-loop start --epic bd-l14dx` created a wave but immediately blocked on kickoff_env_blocked:
- Blocker: `dx_task_repo_unresolved` — Beads metadata did not resolve a unique target repo
- State: `kickoff_env_blocked`
- No dispatchable tasks

**With `--repo agent-skills`:**

`dx-loop start --epic bd-l14dx --repo agent-skills` created a wave and dispatched `.1`:
- State: `in_progress_healthy`
- Active: `bd-l14dx.1:implement`
- However: the runbook does not mention the `--repo` flag requirement
- The fixture spec does not address repo resolution

### C. Dependency Advancement — FAIL (dx-loop)

`dx-loop` loaded all 5 tasks into a single flat layer:
```
"layers": [["bd-l14dx.1", "bd-l14dx.2", "bd-l14dx.3", "bd-l14dx.4", "bd-l14dx.5"]]
```

Beads metadata correctly stores the dependency graph (verified via `bd show bd-l14dx.2 --json`):
- `.2` blocked by `.1`
- `.3` blocked by `.2`
- `.4` blocked by `.2`
- `.5` blocked by `.3` and `.4`

But `dx-loop` status JSON shows all tasks with `"dependencies": []`.
The dependency metadata is not being loaded by `dx-loop` — likely the timeout errors on tasks `.2` through `.5` prevented dependency resolution:
```
"detail_load_error": "timeout"
```

The frontier computation is therefore wrong: all tasks appear simultaneously dispatchable instead of respecting the fork/join graph.

### D. Artifact Integrity — PASS

Manual execution of all 5 append_line.py tasks produced:

```
line 1
line 2
line 3
line 4
line 5
```

Validation output:
```json
{
  "valid": true,
  "checks": {
    "line_count": {"pass": true},
    "exact_order": {"pass": true},
    "no_duplicates": {"pass": true},
    "exact_content": {"pass": true},
    "spec_assertion": {"pass": true}
  }
}
```

### E. Terminal Retirement — NOT TESTED

`dx-loop` was still running when we terminated the session. Manual close of all issues confirmed clean terminal state via `bd close`.

## dx-loop Requalification Verdict

**NOT REQUALIFIED**

Three dx-loop issues prevented full automated execution:

1. **Repo resolution required**: `dx-loop start` without `--repo` fails for fixture tasks that don't have repo metadata. The runbook does not document this requirement.

2. **Dependency graph not loaded**: `dx-loop` shows all tasks in one flat layer despite correct Beads dependency metadata. Detail loading timeouts on tasks `.2` through `.5` may prevent dependency resolution.

3. **instantiate_epic.py parsing bug**: The script parses `bd create` output incorrectly — it takes the last line of stdout as the issue id, but the actual format is `✓ Created issue: bd-xxx — title` on the first line with `Priority:` and `Status:` on subsequent lines.

## Residual Risks

- The fixture helper scripts work correctly in isolation (PASS)
- The fixture correctly creates the Beads dependency graph (PASS)
- `dx-loop` first-use diagnostics are actionable (PASS)
- `dx-loop` automated execution is not yet verified end-to-end on this fixture shape
- The `--repo` flag is an undocumented prerequisite for fixture tasks without repo metadata

## Root Cause Family

All three failures are independent:
1. Repo resolution is a `dx-loop` design constraint (no default repo fallback)
2. Dependency loading is a `dx-loop` reliability issue (timeout on bulk task resolution)
3. Output parsing is an `instantiate_epic.py` implementation bug
