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
  - Daily: `green`
  - Weekly: `yellow`

## Gate Metrics
- PR rejection trend:
  - Method: count PRs closed as rejected in rolling window.
  - Current value: **not computable from current artifact set** (requires PR API export source not included).
- Repeated bug recurrence across VMs:
  - Method: count recurring host fail classes from host check summaries.
  - Current value: **0 active recurring host fail classes** in latest convergence run.
- Founder weekly intervention minutes:
  - Method: operator command windows from artifacts.
  - Current value: **>30 min** during rollout cleanup and proof runs.
- Drift incidents per week:
  - Current value: **0 active hosts red** in latest host check convergence.

## SLO Check (Decision Gate)
- SLO goal for program gate: <=30 min/week founder spend and no unresolved drift >24h.
- Current gate verdict: **NO-GO (transport + metrics completeness blockers remain)**.

## Weekly Actions
1. Keep deterministic red/yellow review on Slack when transport is available.
2. Fix Slack channel membership or webhook fallback for live cron delivery.
3. Populate recurring history files in `~/.dx-state/fleet/audit/*/history`.

## Evidence
- `/tmp/fleet-platform-closeout-2026-03-05/check-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/daily-audit-latest.json`
- `/tmp/fleet-platform-closeout-2026-03-05/weekly-audit-latest.json`
