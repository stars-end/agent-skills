# Fleet Sync Runbook (v2.3)

## Purpose

Operate Fleet Sync with low founder load:

- one command family
- daily runtime checks
- weekly governance checks
- deterministic Slack messages to `#fleet-events`

## Canonical Commands

### Fleet-Wide Converge (V2.2)

One-command converge across all canonical VMs:

```bash
# Fleet-wide drift check
~/agent-skills/scripts/dx-fleet.sh converge --check --json

# Fleet-wide apply
~/agent-skills/scripts/dx-fleet.sh converge --apply --json

# Fleet-wide repair
~/agent-skills/scripts/dx-fleet.sh converge --repair --json
```

Returns non-zero if any host is red.

### Host-level convergence

```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-mcp-tools-sync.sh --repair --json --state-dir ~/.dx-state/fleet
```

### Fleet health checks

```bash
~/agent-skills/scripts/dx-fleet.sh check --mode daily --json
~/agent-skills/scripts/dx-fleet.sh check --mode weekly --json
```

### Fleet audit

```bash
~/agent-skills/scripts/dx-fleet.sh audit --daily --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-fleet.sh audit --weekly --json --state-dir ~/.dx-state/fleet
```

### Repair

```bash
~/agent-skills/scripts/dx-fleet.sh repair --json --state-dir ~/.dx-state/fleet
```

## Fail-Closed Semantics (V2.2)

### MCP Overall Truth Model

The `overall` status is computed from BOTH tool rows AND file rows:

- If `tools_fail > 0` → `overall = "red"` (no exceptions)
- If `files_fail > 0` → `overall = "red"`
- If `warn > 0` → `overall = "yellow"`
- Otherwise → `overall = "green"`

### Runtime Error Fail-Closed

On runtime errors, `dx-mcp-tools-sync.sh`:

1. Removes stale cached JSON fallback
2. Emits synthetic red JSON with `reason_code=mcp_tools_sync_runtime_error`
3. Exits non-zero

This ensures **no false-green** under runtime failures.

### Strict Freshness Enforcement

Snapshots older than threshold (default: 6 hours) are rejected:

- `local_snapshot_stale`: Local snapshot too old
- `remote_snapshot_stale`: Remote snapshot too old
- `remote_snapshot_missing`: Cannot fetch remote snapshot

### Operator One-Command Converge + Repair Loop

```bash
# 1. Check fleet-wide health
~/agent-skills/scripts/dx-fleet.sh converge --check --json

# 2. If red, apply repairs
~/agent-skills/scripts/dx-fleet.sh converge --repair --json

# 3. Verify full recovery
~/agent-skills/scripts/dx-fleet.sh converge --check --json | jq '.overall == "green"'
```

For single-host issues:
```bash
# Diagnose
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.status=="fail")'

# Repair
~/agent-skills/scripts/dx-mcp-tools-sync.sh --repair --json

# Verify
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.overall == "green"'
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

## Platform Status Contract

Fleet Sync operates in one of two states:

### Full Fleet Sync GO
All enabled MCP tools are healthy. Expect green daily/weekly audits across all hosts.

### Ops-Platform Only GO
Ops infrastructure is healthy, but the MCP tool-value lane is partial.
- This is acceptable when tools are explicitly disabled in `configs/mcp-tools.yaml`
- `tool_mcp_health` will show green because only enabled tools are health-checked
- Core ops remain operational: Beads, GitHub, Railway, 1Password, Slack alerts

**Current Status: GO: ops-platform only (partial MCP tool-value lane)**

Enabled tools (2/4):
- `llm-tldr` (1.5.2): context slicing, working
- `contextplus` (1.0.7): semantic intelligence, working

Disabled tools (2/4, see `configs/mcp-tools.yaml` for rationale):
- `cass-memory`: no npm package published, requires building from source
- `serena`: PyPI package provides no executable entrypoint

**Fleet Status (2026-03-08):**
- All 4 hosts: green
- Daily audit: 20/20 checks pass
- Weekly audit: 36/36 checks pass
- MCP tools: 2/2 enabled tools healthy
- IDE surfaces: 20/20 configs aligned

**Operator expectations:**
- Daily/weekly audits should pass (green) if ops checks pass
- If `tool_mcp_health` fails, check if tool is enabled in manifest - disabled tools are not health-checked
- To add a new tool: add to `configs/mcp-tools.yaml` with `enabled: true`, run `dx-mcp-tools-sync.sh --apply`
- To disable a broken tool: set `enabled: false` with `disabled_reason`, the tool will be excluded from health checks

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
