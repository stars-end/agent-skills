# Fleet Sync Runbook

## Scope

This runbook defines deterministic fleet health operations for v2.2:

- Daily fleet runtime checks
- Weekly governance/compliance audits
- Deterministic Slack alerting to `#fleet-events` via Agent Coordination

## Commands

- Daily runtime check snapshot:

```bash
~/agent-skills/scripts/dx-fleet.sh check --json --state-dir ~/.dx-state/fleet
```

- Daily repair (lean):

```bash
~/agent-skills/scripts/dx-fleet.sh repair --json --state-dir ~/.dx-state/fleet
```

- Daily audit:

```bash
~/agent-skills/scripts/dx-fleet.sh audit --daily --json --state-dir ~/.dx-state/fleet
```

- Weekly audit:

```bash
~/agent-skills/scripts/dx-fleet.sh audit --weekly --json --state-dir ~/.dx-state/fleet
```

## Cron Wiring

Use `scripts/dx-audit-cron.sh`:

- Daily: `scripts/dx-audit-cron.sh --daily --state-dir ~/.dx-state/fleet`
- Weekly: `scripts/dx-audit-cron.sh --weekly --state-dir ~/.dx-state/fleet`

Each wrapper invocation emits one deterministic message and sends one `#fleet-events` post.

Dry-run:

```bash
~/agent-skills/scripts/dx-audit-cron.sh --daily --dry-run --state-dir ~/.dx-state/fleet
```

## Severity Mapping and Escalation

- `green`: no action required
- `yellow`: run `dx-fleet repair --json`
- `red`: dispatch repair immediately
- `unknown`: inspect stale-host history, then dispatch on policy

On red/fail from audit:

- Dispatch `dx-fleet repair --json`.

## Backward Compatibility / Migration

- New writes only to `~/.dx-state/fleet/`.
- Reads continue from legacy roots for now:
  - `~/.dx-state/fleet-sync/`
  - `~/.dx-state/fleet_sync/`

Rollback:

- If a script regression is suspected, set `DX_FLEET_STATE_ROOT` back to `~/.dx-state/fleet-sync` in automation temporarily.
- Temporarily disable weekly governance by running daily mode only (no code changes; do not delete state).

## Failure Modes

- Missing `jq`/`python3`: both weekly and daily audit commands use fallback parsing where possible.
- Invalid JSON from `dx-audit.sh`: cron wrapper exits non-zero and logs failure without sending.

## Evidence Artifact Paths

- Daily latest: `~/.dx-state/fleet/audit/daily/latest.json`
- Daily history: `~/.dx-state/fleet/audit/daily/history/YYYY-MM-DD.json`
- Weekly latest: `~/.dx-state/fleet/audit/weekly/latest.json`
- Weekly history: `~/.dx-state/fleet/audit/weekly/history/YYYY-WW.json`
