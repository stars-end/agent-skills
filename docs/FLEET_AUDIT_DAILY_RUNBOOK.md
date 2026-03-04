# Fleet Daily Audit Runbook (V2.2)

## Purpose

Daily audit is deterministic runtime-only validation. It consumes Fleet Sync output artifacts and avoids broad platform checks.

## Command

```bash
~/agent-skills/scripts/dx-fleet.sh audit --daily --json --state-dir ~/.dx-state/fleet
```

## Exact Required Check IDs

- `beads_dolt`
- `tool_mcp_health`
- `required_service_health`
- `op_auth_readiness`
- `alerts_transport_readiness`

## Accepted Severities

- `green`/`pass`: stable.
- `yellow`/`warn`: remediation suggestion required (`repair_hints`).
- `red`/`fail`: immediate repair dispatch.
- `unknown`: deterministic retry after environment convergence.

## Failure Handling

1. On `yellow`: queue normal repair command and rerun audit.
2. On `red`: dispatch immediate repair:
   - `~/agent-skills/scripts/dx-fleet.sh repair --json --state-dir ~/.dx-state/fleet`
3. Preserve output artifact for forensics:
   - `~/.dx-state/fleet/audit/daily/latest.json`

## Expected JSON

Daily JSON must include:

- `mode: "daily"`
- `fleet_status`
- `summary` with counts and host stats
- `hosts`
- `checks`
- `repair_hints`
- `reason_codes`
- `state_paths`

## Slack Posting

`scripts/dx-audit-cron.sh --daily` is the deterministic daily posting path:

- one daily message in `#dx-alerts`
- exact mode in payload: `fleet_status` + check counts

If transport readiness is missing, audit command still writes state but wrapper exits non-zero without silent success.
