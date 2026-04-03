# bd-7r9r QA Log — dx-loop blocked-truth persistence

Date: 2026-04-03
Issue: `bd-7r9r`
Class: `dx_loop_control_plane`

## Failure shape covered

- Active-epic registry and persisted `loop_state.json` exist.
- Iteration-1 dispatch attempts can block on missing upstream PR artifacts (example: `bd-iey6`).
- No `dx-runner` process starts.
- Loop could remain resident and later surfaces could rewrite blocked truth as healthy/completed.

## Bounded fixes implemented

- Added repo-truthful closed-dependency artifact recovery fallbacks for closed dependency metadata with missing repo.
- Made iteration-1 all-blocked/no-runner-started dispatch exit with actionable blocked state.
- Kept `status`/`explain` missing-wave diagnostics actionable for epic-token lookups.
- Reconciliation now preserves blocked scheduler truth when no active runs, and still reconciles closed tasks without requiring active baton states.

## Regression coverage

Added/updated targeted tests in `tests/dx_loop/test_v1_1_fixes.py`:

- `test_run_loop_exits_when_initial_dispatch_blocked_by_dependency_artifacts`
- `test_recover_closed_dependency_artifact_uses_default_repo_when_repo_missing`
- `test_status_reconcile_preserves_blocked_state_without_baton`
- `test_status_resolves_epic_when_passed_via_beads_id`
- `test_status_missing_wave_reports_epic_token_diagnostics`

## QA commands

```bash
pytest -q tests/dx_loop/test_v1_1_fixes.py tests/dx_loop/test_baton.py tests/dx_loop/test_state_machine.py
git diff --check
~/agent-skills/scripts/dx-verify-clean.sh "$(pwd)"
```
