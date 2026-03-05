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
- Daily: `fleet_status=red`, `hosts_checked=4`, `hosts_failed=2`, `checks={pass:18, yellow:0, red:2, unknown:0}`.
- Weekly: `fleet_status=yellow`, `hosts_checked=1`, `hosts_failed=0`, `checks={pass:8, yellow:2, red:0, unknown:0}`.
- Repair contract:
  - Pass fixture: `dx-fleet-repair --json` -> exit `0`
  - Fail fixture: `dx-fleet-repair --json` -> exit `2`

## Drift and Reliability Signals
- Fleet checks currently fail primarily from:
  - `tool_mcp_health` drift on `epyc6` and `epyc12`.
  - Slack live send transport path unavailable from current coordinator environment.
- Repair outputs remain machine-parsable with explicit `reason_codes` and `state_paths`.

## Baseline Risk Register
- High: two-host MCP lane drift still prevents full-fleet green convergence.
- Medium: Slack transport in cron live mode not yet healthy (`transport unavailable`).
- Medium: insufficient 14-day history depth for trend interpretation.

## Method
1. Run daily and weekly audits with `--json`.
2. Verify required top-level fields and state artifact paths.
3. Run repair fixture matrix for pass/fail contract.
4. Run 12-way concurrency stress for `--json` commands.

## Evidence Files
- `/tmp/fleet-land-plane-2026-03-05/check-greenrun-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/repair-check-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/cron-exit-summary.txt`
- `/Users/fengning/.dx-state/fleet/audit/daily/latest.json`
- `/Users/fengning/.dx-state/fleet/audit/weekly/latest.json`
