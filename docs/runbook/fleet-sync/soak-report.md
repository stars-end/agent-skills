# Fleet Sync 14-Day Soak Report (SLO Gate)

## Readiness Decision
- Full bd-d8f4 program completion: **NO-GO**
- Reason: required 14-day soak window is incomplete and unresolved drift remains open.

## Scope
bd-d8f4.6 decision artifact for post-rollout reliability gating.

## Date
- Generated: `2026-03-05`

## Data Availability
- Current audit history contains:
  - Daily: 1 sample
  - Weekly: 1 sample
- **14-day aggregate not yet available in this worktree session**.

## Computed Baseline (Current Window)
- Daily latest: red.
- Weekly latest: yellow.
- Known unresolved drift:
  - Remote host snapshot reachability for `epyc6`, `epyc12`, `homedesktop-wsl` unresolved.
- Repair coverage:
  - Repair command contract validated with fixture pass/fail and structured JSON outputs.

## SLO Check
- Target SLO: <=30 min founder time / week and no unresolved drift >24h.
- Current verdict: **NO-GO** (insufficient coverage + unresolved drift windows).

## MTTR/Red-Yellow
- Not computed for 14-day distribution due insufficient sample depth.
- Existing red state remains dominated by connectivity and transport readiness and should be cleared before hard gate pass.

## Mitigations before SLO re-test
1. Rehydrate canonical hosts so `~/.dx-state/fleet` snapshots are reachable for all targets.
2. Run 14 consecutive daily sessions with persisted artifacts.
3. Recalculate MTTR and unresolved windows from real history.

## Evidence
- `/Users/fengning/.dx-state/fleet/audit/daily/history/*.json`
- `/Users/fengning/.dx-state/fleet/audit/weekly/history/*.json`
- `/tmp/fleet-os-completion/concurrency-stress-summary.txt`
