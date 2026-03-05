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
1. Fix remote script path consistency on `homedesktop-wsl` for `~/agent-skills/...` install/check helpers.
2. Restore deterministic live Slack transport in cron (`SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SLACK_MCP_XOXP_TOKEN`, `SLACK_MCP_XOXB_TOKEN`, `DX_SLACK_WEBHOOK`, or `DX_ALERTS_WEBHOOK`).
3. Produce one fresh cross-host green convergence run where all hosts pass required checks under stable auth/transport.

## Evidence Paths
- `/tmp/fleet-platform-closeout-2026-03-05/`
