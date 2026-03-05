# Fleet Sync Weekly Metrics Report

## Scope
Weekly operational signal summary for bd-d8f4.5, using captured artifacts only.

## Window
- Week of capture: `2026-03-05` (single available audit snapshot window in this run).

## Inputs
- `/tmp/fleet-platform-closeout-2026-03-05/daily-audit-latest.json`
- `/tmp/fleet-platform-closeout-2026-03-05/weekly-audit-latest.json`
- `/tmp/fleet-platform-closeout-2026-03-05/concurrency/*-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/check-summary.json`

## Observed Trends
- Daily samples available: **1**
- Weekly samples available: **1**
- Deterministic status distribution:
  - Daily: `red`
  - Weekly: `yellow`

## Gate Metrics
- PR rejection trend:
  - Method: count PRs closed as rejected in rolling window.
  - Current value: **not computable from current artifact set** (requires PR API export source not included).
- Repeated bug recurrence across VMs:
  - Method: count recurring host fail classes from host check summaries.
  - Current value: **2 recurring host groups** (`op_auth_readiness`, `alerts_transport_readiness`).
- Founder weekly intervention minutes:
  - Method: operator command windows from artifacts.
  - Current value: **>30 min** during rollout cleanup and proof runs.
- Drift incidents per week:
  - Current value: **4 active hosts red**.

## SLO Check (Decision Gate)
- SLO goal for program gate: <=30 min/week founder spend and no unresolved drift >24h.
- Current gate verdict: **NO-GO (unresolved rollouts/transports remain)**.

## Weekly Actions
1. Keep deterministic red/yellow review on Slack when transport is available.
2. Stabilize epyc6/epyc12 and auth/transport controls, then rerun 14-day runbook.
3. Populate recurring history files in `~/.dx-state/fleet/audit/*/history`.

## Evidence
- `/tmp/fleet-platform-closeout-2026-03-05/check-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/daily-audit-latest.json`
- `/tmp/fleet-platform-closeout-2026-03-05/weekly-audit-latest.json`
