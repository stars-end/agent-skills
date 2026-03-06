# Fleet Audit JSON Contract (v2.3)

Applies to both:

- `dx-fleet audit --daily --json`
- `dx-fleet audit --weekly --json`

## Top-level keys (stable)

```json
{
  "mode": "daily|weekly",
  "generated_at": "ISO8601 UTC",
  "generated_at_epoch": 0,
  "fleet_status": "green|yellow|red|unknown",
  "summary": {
    "pass": 0,
    "yellow": 0,
    "red": 0,
    "unknown": 0,
    "hosts_checked": 0,
    "hosts_failed": 0
  },
  "hosts": [],
  "checks": [],
  "repair_hints": [],
  "reason_codes": [],
  "state_paths": {},
  "slack_channel": "#fleet-events",
  "slack_message": "deterministic single-line summary"
}
```

## Hosts

Each host row:

```json
{
  "host": "macmini|homedesktop-wsl|epyc6|epyc12",
  "overall": "green|yellow|red",
  "checks": [
    {
      "id": "check_id",
      "status": "pass|warn|fail|unknown",
      "severity": "low|medium|high",
      "details": "text",
      "reason_code": "optional"
    }
  ]
}
```

## Checks

Flattened per-host checks (used by downstream parsers).

## Repair hints

Host-scoped commands:

```json
{
  "host": "epyc6",
  "check_id": "fleet.v2.2.host_red",
  "command": "ssh fengning@epyc6 '~/agent-skills/scripts/dx-fleet-repair.sh --json --state-dir ~/.dx-state/fleet'"
}
```

## Reason codes

Expected examples:

- `ok`
- `remote_snapshot_missing`
- `remote_snapshot_stale`
- `remote_snapshot_unparseable`
- `audit_payload_invalid`

## State paths

```json
{
  "audit_root": "~/.dx-state/fleet",
  "tool_health_json": "~/.dx-state/fleet/tool-health.json",
  "tool_health_lines": "~/.dx-state/fleet/tool-health.lines",
  "audit_latest": "~/.dx-state/fleet/audit/<daily|weekly>/latest.json",
  "audit_history": "~/.dx-state/fleet/audit/<daily|weekly>/history",
  "legacy_state_roots": [
    "~/.dx-state/fleet-sync",
    "~/.dx-state/fleet_sync"
  ]
}
```
