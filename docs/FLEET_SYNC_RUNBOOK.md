# Fleet Sync Runbook (v2.3)

## Purpose

Operate Fleet Sync with low founder load:

- one command family
- daily runtime checks
- weekly governance checks
- deterministic Slack messages to `#fleet-events`

## Canonical Commands

### Host convergence

```bash
~/agent-skills/scripts/dx-fleet-install.sh --apply --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-fleet-check.sh --mode daily --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-fleet-check.sh --mode weekly --json --state-dir ~/.dx-state/fleet
```

### Fleet views

```bash
~/agent-skills/scripts/dx-fleet.sh audit --daily --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-fleet.sh audit --weekly --json --state-dir ~/.dx-state/fleet
```

### Repair

```bash
~/agent-skills/scripts/dx-fleet.sh repair --json --state-dir ~/.dx-state/fleet
```

## Cross-VM Rollout

```bash
for vm in macmini homedesktop-wsl epyc6 epyc12; do
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-install.sh --apply --json --state-dir ~/.dx-state/fleet"
done

for vm in macmini homedesktop-wsl epyc6 epyc12; do
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-check.sh --mode daily --json --state-dir ~/.dx-state/fleet"
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-check.sh --mode weekly --json --state-dir ~/.dx-state/fleet"
done
```

## Cron

Single canonical cron wrapper:

- Daily: `scripts/dx-audit-cron.sh --daily --state-dir ~/.dx-state/fleet`
- Weekly: `scripts/dx-audit-cron.sh --weekly --state-dir ~/.dx-state/fleet`

Dry-run checks:

```bash
~/agent-skills/scripts/dx-audit-cron.sh --daily --dry-run --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-audit-cron.sh --weekly --dry-run --state-dir ~/.dx-state/fleet
```

## Escalation Mapping

- `green`: no action
- `yellow`: run `dx-fleet repair --json`
- `red`: run repair on failing hosts and rerun checks
- `unknown`: treat as incident if repeated and investigate host reachability/state freshness

## Freshness / Remote Snapshot Rules

Remote host payloads fail deterministically when:

- snapshot missing (`remote_snapshot_missing`)
- snapshot stale beyond `audit.thresholds.tool_stale_hours` (`remote_snapshot_stale`)
- payload invalid (`remote_snapshot_unparseable`)

## Artifact Paths

- `~/.dx-state/fleet/tool-health.json`
- `~/.dx-state/fleet/tool-health.lines`
- `~/.dx-state/fleet/mcp-tools-sync.json`
- `~/.dx-state/fleet/audit/daily/latest.json`
- `~/.dx-state/fleet/audit/daily/history/YYYY-MM-DD.json`
- `~/.dx-state/fleet/audit/weekly/latest.json`
- `~/.dx-state/fleet/audit/weekly/history/YYYY-WW.json`

## Compatibility / Migration

Reads still tolerate:

- `~/.dx-state/fleet-sync/`
- `~/.dx-state/fleet_sync/`

Writes are canonicalized to `~/.dx-state/fleet/`.

## Disable / Rollback

Temporary disable:

- stop cron entries for `dx-audit-cron.sh`

Fail-open rollback:

```bash
~/agent-skills/scripts/dx-fleet-install.sh --uninstall --json --state-dir ~/.dx-state/fleet
```
