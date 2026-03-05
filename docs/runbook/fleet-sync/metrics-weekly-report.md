# Fleet Sync Weekly Metrics Report

## Scope
Weekly summary for bd-d8f4.5, using available audit history in `~/.dx-state/fleet`.

## Window
- Week of capture: `2026-03-05` (single available snapshot in current history)

## Inputs
- `~/.dx-state/fleet/audit/daily/history/*.json`
- `~/.dx-state/fleet/audit/weekly/history/*.json`
- `/tmp/fleet-deploy-session/session-2026-03-05.md`

## Observed Trends
- Daily samples available: **1**
- Weekly samples available: **1**
- Deterministic status distribution (based on available data):
  - Daily: red (single snapshot)
  - Weekly: yellow (single snapshot)

## Gate Metrics (Method + Current Value)
- PR rejection trend:
  - Method: compare closed-unmerged vs merged PRs in rolling weekly window.
  - Current value: **not computable in this runbook pass** (historical sample not yet harvested into this doc).
- Repeated bug recurrence across VMs:
  - Method: count repeated `reason_codes`/check IDs across host snapshots for same week.
  - Current value: **2 recurring host drifts** (`tool_mcp_health` on `epyc6`, `epyc12`).
- Founder weekly intervention minutes:
  - Method: sum operator command windows from deploy/repair/audit session logs.
  - Current value: **>30 min** in this pass (manual SSH trust + config remediation required).
- Drift incidents per week:
  - Method: count red host rows in daily audit history.
  - Current value: **2 active host drifts** in latest daily run.

## Founder-time Indicator
- No repeat windows exist yet for mean-time-to-detection analysis beyond single-day signal.
- Baseline remains operationally noisy due remote snapshot read failures and environment drift.

## Open Risks
- PR-closure risk from unresolved rollout gate (`bd-d8f4.2` still red).
- Operational risk from Slack live transport unavailability in cron wrapper.

## Weekly Actions Proposed
1. Keep daily red/yellow review deterministic on Slack.
2. Escalate any sustained `yellow` for 2+ consecutive weeks or repeated red drift for follow-up.
3. Rebuild host rollout on canonical machines to collect complete daily/weekly history.

## Evidence
- `/tmp/fleet-land-plane-2026-03-05/check-greenrun-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/cron-exit-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/hosts/*-check-greenrun.json`
- `/Users/fengning/.dx-state/fleet/audit/weekly/latest.json`
- `/Users/fengning/.dx-state/fleet/audit/daily/latest.json`
