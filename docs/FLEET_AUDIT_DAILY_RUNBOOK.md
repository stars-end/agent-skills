# Fleet Audit Daily Runbook (Fleet Sync v2.3)

## Goal

Provide one deterministic daily fleet runtime health result across all canonical VMs.

## Command

```bash
~/agent-skills/scripts/dx-fleet.sh audit --daily --json --state-dir ~/.dx-state/fleet
```

## Daily required checks

- `beads_dolt`
- `tool_mcp_health`
- `required_service_health`
- `op_auth_readiness`
- `alerts_transport_readiness`

## Host scope

Cross-VM fanout across:

- `macmini`
- `homedesktop-wsl`
- `epyc6`
- `epyc12`

## Cron

```bash
~/agent-skills/scripts/dx-audit-cron.sh --daily --state-dir ~/.dx-state/fleet
```

Dry-run:

```bash
~/agent-skills/scripts/dx-audit-cron.sh --daily --dry-run --state-dir ~/.dx-state/fleet
```

## Severity semantics

- `green`: no action
- `yellow`: run `dx-fleet repair --json`
- `red`: repair failing hosts, rerun daily audit

## Remote freshness enforcement

Any host is failed when remote snapshot is stale or missing:

- `remote_snapshot_missing`
- `remote_snapshot_stale`
- `remote_snapshot_unparseable`

## Artifacts

- `~/.dx-state/fleet/audit/daily/latest.json`
- `~/.dx-state/fleet/audit/daily/history/YYYY-MM-DD.json`
