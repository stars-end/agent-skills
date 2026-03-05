# Fleet Sync Metrics Baseline

## Scope
Initial metric capture for bd-d8f4.5 at current run state.

## Capture Window
- Generated: `2026-03-05`
- Source artifacts:
  - `/tmp/fleet-platform-closeout-2026-03-05/daily-audit-latest.json`
  - `/tmp/fleet-platform-closeout-2026-03-05/weekly-audit-latest.json`
  - `/tmp/fleet-platform-closeout-2026-03-05/concurrency/*-summary.txt`
  - `/tmp/fleet-platform-closeout-2026-03-05/cron-exit-summary.txt`

## Baseline Values
- Daily: `fleet_status=red`, `hosts_checked=4`, `hosts_failed=4`, `checks={pass:12, yellow:0, red:8, unknown:0}`.
- Weekly: `fleet_status=yellow`, `hosts_checked=1`, `hosts_failed=0`, `checks={pass:8, yellow:2, red:0, unknown:0}`.
- Repair probe from state fixture:
  - Red fixture: `fail` (`overall_ok=false`, `fleet_status=red`)
  - Recovery fixture: still red on non-local hosts until host-level auth/transport signals are normalized.

## Drift and Reliability Signals
- Current recurring fail classes:
  - `op_auth_readiness` missing token across all hosts.
  - `alerts_transport_readiness` missing transport in this environment.
- MCP lane drift and host snapshot parity now mostly readable and no longer path-dependent.

## Baseline Risk Register
- High: transport readiness not available for cron live posting.
- High: full rollout gate blocked until all 4 hosts are green.
- Medium: PR rejection trend currently cannot be computed from artifact alone (see weekly report).

## Method
1. Run daily and weekly audits with `--json` and required top-level field verification.
2. Run repair fixture matrix for pass/fail contract.
3. Run 12-way concurrency stress for check/install/mcp/check/uninstall command families.
4. Capture cron dry-run/live behavior and exit behavior.

## Evidence Files
- `/tmp/fleet-platform-closeout-2026-03-05/check-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/check-summary.json`
- `/tmp/fleet-platform-closeout-2026-03-05/concurrency/mcp-check-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/concurrency/fleet-check-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/concurrency/fleet-install-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/concurrency/fleet-uninstall-summary.txt`
- `/tmp/fleet-platform-closeout-2026-03-05/cron-exit-summary.txt`
