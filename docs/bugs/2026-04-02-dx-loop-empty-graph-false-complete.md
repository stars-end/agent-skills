# dx-loop Empty-Graph False-Complete

- CLASS: `dx_loop_control_plane`
- NOT_A_PRODUCT_BUG: `true`
- Beads: `bd-htga`
- Product manifestation context: `affordabot` PR #360 (`aa10ba0860d95ffb460dd3a5722e5d557515b3f7`)
- dx-loop bug branch context: `agent-skills` PR #455 (`ef652849e2cf790e9ca6cb9e60ac0cc9a2e230aa`)

## Symptom

`dx-loop` could reconcile a fresh wave to a false success when the persisted task graph
was still empty and no work had actually been dispatched. In the original manifestation,
the loop reported success for `bd-owqm` even though there were no `dx-runner` jobs and no
real product execution had happened.

## Environment / Triggering Context

- Control-plane surface: `dx-loop`
- Host mode: persisted wave state under `/tmp/dx-loop/waves/<wave-id>/loop_state.json`
- Trigger shape:
  - fresh wave
  - `dispatch_count == 0`
  - no active jobs
  - no hydrated task graph in `beads_manager.tasks`
  - reconciliation executed from `status` / `explain`

## Exact Observed Behavior

- `dx-loop` marked the wave complete without any dispatched work
- there were no corresponding `dx-runner` jobs
- the empty graph was interpreted as “all tasks complete” instead of “bootstrap has not materialized”

Adjacent QA finding:

- a naive fix for the false-complete branch can introduce a second bug where an empty-graph
  wave stays `pending` forever even after the Beads epic is already terminal

## Expected Behavior

- a fresh zero-dispatch empty-graph wave must stay non-terminal
- the surface should say bootstrap is pending, not that the wave succeeded
- if the Beads epic is already terminal, the empty/stale cached wave should retire cleanly

## Root Cause

Surface reconciliation used the same “no pending tasks and no active jobs” completion logic
for both:

1. legitimate fully-complete waves, and
2. fresh waves whose task graph had not yet been hydrated

That collapsed “empty because not bootstrapped” into “empty because fully done”.

## Reproduction Notes

Minimal false-success shape:

1. create a wave with:
   - `epic_id` set
   - empty `beads_manager.tasks`
   - `dispatch_count == 0`
   - no active/completed tasks
2. run `_reconcile_wave_state_for_surfaces()`
3. old behavior could fall through to terminal success

Empty-graph retirement shape:

1. create the same empty cached wave
2. have `refresh_epic_truth()` return a terminal Beads status
3. wave should retire as a stale/empty cache, not remain pending forever

## Fix Summary

The reconciliation path now handles empty task-graph waves explicitly before normal readiness
resolution:

- if the wave has no hydrated tasks and the epic is already terminal:
  - retire the wave as completed-for-retirement
- if the wave has no hydrated tasks, zero dispatch, and no active/completed tasks:
  - keep the wave `pending` with a bootstrap-specific reason
- otherwise:
  - classify the wave as kickoff-env blocked rather than pretending it succeeded

## Regression Coverage

Focused tests in `tests/dx_loop/test_v1_1_fixes.py`:

- `test_status_reconcile_does_not_false_complete_minimal_wave`
- `test_status_reconcile_empty_graph_retire_when_epic_closed`

These cover both the original false-success bug and the adjacent retirement regression.

## Residual Risks

- This fix is intentionally narrow and only addresses empty-graph surface reconciliation
- Broader bootstrap failures can still surface as `kickoff_env_blocked`, which is correct
  but may still need future UX polish
- The underlying Beads hydration path remains a separate control-plane dependency

## QA Classification

- CLASS: `dx_loop_control_plane`
- NOT_A_PRODUCT_BUG: `true`
