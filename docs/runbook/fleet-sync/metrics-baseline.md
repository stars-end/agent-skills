# Fleet Sync Metrics Baseline

## Scope
Initial metric capture for bd-d8f4.5 at current state.

## Capture Window
- Generated: `2026-03-05`
- Source artifacts:
  - `~/.dx-state/fleet/audit/daily/latest.json`
  - `~/.dx-state/fleet/audit/weekly/latest.json`
  - `/tmp/fleet-os-completion/repair-pass.json`
  - `/tmp/fleet-os-completion/repair-fail.json`
  - `/tmp/fleet-os-completion/concurrency-stress-summary.txt`

## Baseline Values
- Daily: `fleet_status=red`, `hosts_checked=4`, `hosts_failed=4`, `checks={pass:3, yellow:0, red:17, unknown:0}`.
- Weekly: `fleet_status=yellow`, `hosts_checked=1`, `hosts_failed=0`, `checks={pass:8, yellow:2, red:0, unknown:0}`.
- Repair contract:
  - Pass fixture: `dx-fleet-repair --json` -> exit `0`
  - Fail fixture: `dx-fleet-repair --json` -> exit `2`

## Drift and Reliability Signals
- Fleet checks currently fail primarily from:
  - Remote snapshot read failures for non-local hosts.
  - Missing OP token and Slack transport at local execution path.
- Repair outputs remain machine-parsable with explicit `reason_codes` and `state_paths`.

## Baseline Risk Register
- High: canonical host SSH accessibility and script rollout mismatch.
- Medium: insufficient 14-day history depth for trend interpretation.

## Method
1. Run daily and weekly audits with `--json`.
2. Verify required top-level fields and state artifact paths.
3. Run repair fixture matrix for pass/fail contract.
4. Run 12-way concurrency stress for `--json` commands.

## Evidence Files
- `/tmp/fleet-os-completion/audit-daily-fleet.json`
- `/tmp/fleet-os-completion/audit-weekly-fleet.json`
- `/tmp/fleet-os-completion/repair-pass.json`
- `/tmp/fleet-os-completion/repair-fail.json`
- `/tmp/fleet-os-completion/concurrency-stress-summary.txt`
