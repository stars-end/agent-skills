# dx-loop Golden CSV Fixture Requalification Rerun

**Date**: 2026-04-08  
**CLASS**: dx_loop_control_plane  
**NOT_A_PRODUCT_BUG**: true

## Fixture IDs

| Role | ID |
|------|-----|
| Epic | bd-6u95f |
| .1 Append line 1 | bd-6u95f.1 |
| .2 Append line 2 | bd-6u95f.2 |
| .3 Append line 3 | bd-6u95f.3 |
| .4 Append line 4 | bd-6u95f.4 |
| .5 Append line 5 | bd-6u95f.5 |
| Wave ID | wave-2026-04-08-16-36-50Z |
| Run ID (initial, artifact fail) | golden-csv-20260408T163637Z |
| Run ID (final, artifact pass) | golden-csv-20260408T164543Z |
| Final run dir | /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z |

## Commands Run

1. `python3 fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py --dry-run`
2. `python3 fixtures/dx_loop/golden_csv/scripts/instantiate_epic.py`
3. `python3 fixtures/dx_loop/golden_csv/scripts/create_run.py`
4. `dx-loop status --beads-id bd-6u95f.1`
5. `dx-loop explain --beads-id bd-6u95f.1`
6. `dx-loop start --epic bd-6u95f --repo agent-skills`
7. `dx-loop status --epic bd-6u95f --json`
8. `dx-loop explain --epic bd-6u95f`
9. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z --task-index 1`
10. `bd close bd-6u95f.1 --reason 'fixture append line 1 complete'`
11. `dx-loop status --epic bd-6u95f --json`
12. `dx-loop explain --epic bd-6u95f`
13. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z --task-index 2`
14. `bd close bd-6u95f.2 --reason 'fixture append line 2 complete'`
15. `dx-loop status --epic bd-6u95f --json`
16. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z --task-index 3`
17. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z --task-index 4`
18. `bd close bd-6u95f.3 --reason 'fixture append line 3 complete'`
19. `bd close bd-6u95f.4 --reason 'fixture append line 4 complete'`
20. `dx-loop status --epic bd-6u95f --json`
21. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z --task-index 5`
22. `bd close bd-6u95f.5 --reason 'fixture append line 5 complete'`
23. `dx-loop status --epic bd-6u95f --json`
24. `dx-loop explain --epic bd-6u95f`
25. `python3 fixtures/dx_loop/golden_csv/scripts/validate_run.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T163637Z`
26. `python3 fixtures/dx_loop/golden_csv/scripts/create_run.py`
27. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z --task-index 1`
28. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z --task-index 2`
29. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z --task-index 3`
30. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z --task-index 4`
31. `python3 fixtures/dx_loop/golden_csv/scripts/append_line.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z --task-index 5`
32. `python3 fixtures/dx_loop/golden_csv/scripts/validate_run.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z`
33. `bd show bd-6u95f --json`

## Results by Phase

### A. First-Use Lookup — PASS

`dx-loop status --beads-id bd-6u95f.1` and `dx-loop explain --beads-id bd-6u95f.1` before wave creation both returned actionable first-use guidance:

- blocker class: `control_plane_missing_wave_state`
- suggested next command: `dx-loop start --epic bd-6u95f`
- no hang
- no raw missing-wave dead-end text

### B. Bootstrap — PASS

`dx-loop start --epic bd-6u95f --repo agent-skills` produced persisted wave `wave-2026-04-08-16-36-50Z`.

`dx-loop status --epic bd-6u95f --json` showed:

- `wave_status.state = in_progress_healthy`
- `default_repo = agent-skills`
- initial layer frontier includes only `bd-6u95f.1`

No zero-dispatch false success observed.

### C. Dependency Advancement — PASS

Observed frontier progression from status JSON:

- after closing `.1`: dispatchable = `bd-6u95f.2`
- after closing `.2`: dispatchable = `bd-6u95f.3`, `bd-6u95f.4`
- after closing `.3` and `.4`: dispatchable = `bd-6u95f.5`
- `.5` did not surface before both join dependencies were terminal

No stale frontier detected.

### D. Artifact Integrity — PASS (final run)

Initial run `golden-csv-20260408T163637Z` failed due operator-executed parallel append of `.3` and `.4`, producing:

```
line 1
line 2
line 4
line 3
line 5
```

Final run `golden-csv-20260408T164543Z` executed append steps serially and passed validation:

- `python3 .../validate_run.py --run-dir /tmp/dx-loop-fixtures/golden-csv/golden-csv-20260408T164543Z`
- output: `PASS`
- final `output.csv`:
  - `line 1`
  - `line 2`
  - `line 3`
  - `line 4`
  - `line 5`

### E. Terminal Retirement — PASS

After `.5` closed:

- `dx-loop status --epic bd-6u95f --json` -> `wave_status.state = completed`
- retirement reason: `Epic bd-6u95f is closed in Beads; stale wave cache retired`
- `dispatchable_tasks = []`
- `dx-loop explain --epic bd-6u95f` -> `No action required: epic is already closed and this wave is retired.`

### F. Operator UX / Docs — PASS with clarifications

No control-plane regression found, but UX/docs clarifications were identified (see dedicated sections below).

## Control-Plane Findings

None.

`dx-loop` remains requalified on this rerun.

## Agent UX Friction

1. `dx-loop status --beads-id` and `dx-loop explain --beads-id` return actionable guidance pre-wave, but exit code is non-zero. This is correct but easy to misread in automation as hard failure.
2. Runbook wave-3 wording allows `.3` and `.4` together; if an operator applies both append scripts concurrently, artifact ordering becomes nondeterministic and validation fails, which can look like fixture failure.
3. `bd close` repeatedly emits unrelated orphan detection and backup warnings during fixture flow; this adds noise to QA logs but did not block execution.

## Skills/Docs Clarifications

1. In `docs/runbooks/dx-loop-golden-csv-fixture.md`, clarify that for this fixture the append helper should be executed serially (`1,2,3,4,5`) if strict CSV order is required by validator, even though `.3` and `.4` are same wave.
2. In the same runbook, explicitly note expected non-zero exit codes for pre-wave `status/explain` and treat actionable guidance as PASS criteria.
3. Add a short troubleshooting note that `bd` warning noise (orphan detection/auto-backup) is non-blocking for fixture verdict unless command exits non-zero.

## Verdict

Golden fixture rerun outcome: **PASS**  
`dx-loop` requalification status on current master: **REQUALIFIED**
