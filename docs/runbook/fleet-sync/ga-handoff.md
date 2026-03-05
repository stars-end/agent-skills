# Fleet Sync GA Handoff

## Operating Model
- Fleet command surface: single family `dx-fleet check|repair|audit`.
- State write path: `~/.dx-state/fleet/` only.
- Fallback reads: `~/.dx-state/fleet-sync`, `~/.dx-state/fleet_sync`.
- Daily mode: runtime checks + deterministic red/yellow/fail behavior.
- Weekly mode: governance/compliance checks.
- Primary dispatch target: one-click Slack alert in `#dx-alerts` via `scripts/dx-audit-cron.sh`.

## Daily Founder Flow
1. `./scripts/dx-audit-cron.sh --daily --dry-run` (verify deterministic message shape pre-change).
2. `./scripts/dx-audit-cron.sh --daily` scheduled by cron.
3. If `fleet_status=green`: no action.
4. If `fleet_status=yellow`: run `./scripts/dx-fleet.sh repair --json`.
5. If `fleet_status=red`: run `./scripts/dx-fleet.sh repair --json`, then rerun `./scripts/dx-fleet.sh audit --daily --json`.

## Weekly Founder Flow
1. `./scripts/dx-audit-cron.sh --weekly --dry-run`.
2. `./scripts/dx-audit-cron.sh --weekly`.
3. Red/yellow follow-up handled by same repair + rerun loop with weekly-only targets.

## Break-Glass
- If cron wrapper exits non-zero with transport unavailable, rerun check/report manually after `DX_SLACK_*` context is repaired.
- If `~/.dx-state/fleet` becomes unavailable, run:
  - `mkdir -p ~/.dx-state/fleet/{audit/{daily,weekly}/{history},repair}` before rerunning `dx-fleet.sh` commands.
- If remote host snapshots are stale/missing, run host-level SSH repair and validate `~/.dx-state/fleet/tool-health.json` generation on each host.

## Known Risks
- Current deployment state has incomplete rollout of `dx-fleet-install.sh` on some canonical hosts.
- `macmini` SSH auth profile blocks remote install/check probes from this environment.
- 14-day history/Soak evidence is not yet fully populated.

## Required Owner Actions on Red
- Preserve `~/.dx-state/fleet/audit/daily/latest.json` and `~/.dx-state/fleet/tool-health.json` for forensics.
- Execute repair command from local operator console and attach new logs/artifacts to follow-up.
- Escalate if red persists >2 check cycles.

## Evidence Paths
- `/tmp/fleet-deploy-session/session-2026-03-05.md`
- `/tmp/fleet-os-completion/audit-daily-fleet.json`
- `/tmp/fleet-os-completion/audit-weekly-fleet.json`
- `/tmp/fleet-os-completion/concurrency-stress-summary.txt`
- `/tmp/fleet-os-completion/repair-pass.json`
- `/tmp/fleet-os-completion/repair-fail.json`
- `/tmp/fleet-os-completion/crons-daily-dryrun-os.txt`
- `/tmp/fleet-os-completion/crons-weekly-dryrun-os.txt`
