# Fleet Audit JSON Schema

Applies to both `dx-audit --daily` and `dx-audit --weekly`.

## Top-Level

```json
{
  "mode": "daily|weekly",
  "generated_at": "2026-03-04T23:36:00Z",
  "generated_at_epoch": 1772660000,
  "fleet_status": "green|yellow|red|unknown",
  "summary": {
    "pass": 0,
    "yellow": 0,
    "red": 0,
    "unknown": 0,
    "hosts_checked": 1,
    "hosts_failed": 0
  },
  "hosts": [
    {
      "host": "local|<hostname>",
      "overall": "green|yellow|red|unknown",
      "checks": [
        {
          "id": "fleet.v2.2.<check_id>",
          "host": "local|<hostname>",
          "status": "pass|warn|fail|unknown",
          "severity": "low|medium|high|critical",
          "details": "string",
          "next_action": "string(optional)"
        }
      ]
    }
  ],
  "checks": [
    {
      "id": "fleet.v2.2.<check_id>",
      "host": "local|<hostname>",
      "status": "pass|warn|fail|unknown",
      "severity": "low|medium|high|critical",
      "details": "string",
      "next_action": "string(optional)"
    }
  ],
  "repair_hints": [
    {
      "host": "local|<hostname>",
      "check_id": "fleet.v2.2.<check_id>",
      "command": "dx-fleet repair --json"
    }
  ],
  "reason_codes": [
    "stable-sorted-machine-readable-ids"
  ],
  "state_paths": {
    "audit_root": "~/.dx-state/fleet",
    "tool_health_json": "~/.dx-state/fleet/tool-health.json",
    "tool_health_lines": "~/.dx-state/fleet/tool-health.lines",
    "audit_latest": "~/.dx-state/fleet/audit/<daily|weekly>/latest.json",
    "audit_history": "~/.dx-state/fleet/audit/<daily|weekly>/history",
    "legacy_state_roots": ["~/.dx-state/fleet-sync", "~/.dx-state/fleet_sync"]
  },
  "slack_message": "deterministic status text"
}
```

## Check ID Stability

- IDs are versioned using `fleet.v2.2.<id>` prefix.
- Unknown check IDs from manifests remain surfaced as:
  - `fleet.v2.2.<manifest_id>`

## Failure Exit Codes

- `0` success / non-red status
- `2` red status (`fleet_status == "red"`)
