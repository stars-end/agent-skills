# Fleet Sync GA Handoff

## Readiness Decision
- Bash 3.2 daily/weekly audit compatibility: **GO**
- `dx-fleet-daily-check.sh` contract correctness: **GO**
- Full bd-d8f4 program completion: **NO-GO** until rollout/metrics blockers are cleared.

## Operating Model
- Fleet command surface: single family `dx-fleet check|repair|audit`.
- State writes: `~/.dx-state/fleet/` (single canonical root).
- Legacy fallback reads: `~/.dx-state/fleet-sync`, `~/.dx-state/fleet_sync`.
- Daily mode: runtime checks.
- Weekly mode: governance/compliance checks.

## Daily Founder Flow
1. `./scripts/dx-audit-cron.sh --daily --dry-run`
2. `./scripts/dx-audit-cron.sh --daily`
3. If `fleet_status=red`: `./scripts/dx-fleet.sh repair --json`, then rerun check/audit.

## Weekly Founder Flow
1. `./scripts/dx-audit-cron.sh --weekly --dry-run`
2. `./scripts/dx-audit-cron.sh --weekly`
3. If `fleet_status=yellow/red`: same repair loop.

## Break-Glass
- If cron exits non-zero with transport unavailable, capture output and rerun when `DX_SLACK_WEBHOOK` or Slack token is restored.
- If host snapshots are stale/missing, rerun install/check on that host and compare with `/tmp/fleet-platform-closeout-2026-03-05/hosts/*`.

## Current Blockers To Clear Gate
1. Restore deterministic live Slack transport in cron:
   - current Slack API response is `not_in_channel` for `C0AEC54RZ6V`.
   - token is valid but bot is not in the configured channel and token lacks `channels:join`.
   - clear path: invite bot to `#dx-alerts`/configured channel or provide `DX_SLACK_WEBHOOK`/`DX_ALERTS_WEBHOOK`.
2. Complete metrics gate data for PR rejection trend in weekly report.

## Cleared Since Last Pass
- Cross-host rollout convergence is now green for all 4 hosts.
- op_auth_readiness is green fleet-wide (including epyc6 host token source remediation).

## Evidence Paths
- `/tmp/fleet-platform-closeout-2026-03-05/`
