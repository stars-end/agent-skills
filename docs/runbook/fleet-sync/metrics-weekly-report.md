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

## Founder-time Indicator
- No repeat windows exist yet for mean-time-to-detection analysis beyond single-day signal.
- Baseline remains operationally noisy due remote snapshot read failures and environment drift.

## Open Risks
- PR-closure risk from lack of historical coverage (fewer than 14 days).
- Rollback risk from incomplete remote rollout.

## Weekly Actions Proposed
1. Keep daily red/yellow review deterministic on Slack.
2. Escalate any sustained `yellow` for 2+ consecutive weeks or repeated red drift for follow-up.
3. Rebuild host rollout on canonical machines to collect complete daily/weekly history.

## Evidence
- `/tmp/fleet-os-completion/audit-weekly-fleet.json`
- `/Users/fengning/.dx-state/fleet/audit/weekly/history/2026-10.json`
- `/Users/fengning/.dx-state/fleet/audit/daily/history/2026-03-05.json`
