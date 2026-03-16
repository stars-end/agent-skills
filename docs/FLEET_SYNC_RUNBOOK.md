# Fleet Sync Runbook (v2.4)

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

Use `dx-fleet converge` for fleet-wide operations:

```bash
# Fleet-wide drift check
~/agent-skills/scripts/dx-fleet.sh converge --check --json

# Fleet-wide apply
~/agent-skills/scripts/dx-fleet.sh converge --apply --json

# Fleet-wide repair
~/agent-skills/scripts/dx-fleet.sh converge --repair --json
```

For per-host operations:

```bash
for vm in macmini homedesktop-wsl epyc6 epyc12; do
  ssh "$vm" "~/agent-skills/scripts/dx-fleet.sh check --mode daily --json --state-dir ~/.dx-state/fleet"
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

Fleet Sync operates with two tool classes:

### Tool Classes (V2.2)

| Class | Rendering | Layer 4 Check | Example |
|-------|-----------|---------------|---------|
| `mcp` | IDE config | `claude mcp list` | llm-tldr, context-plus, serena |
| `cli` | None | N/A | cass-memory |

### Current Tool Roster

| Tool | Mode | Status | Health Command |
|------|------|--------|----------------|
| `llm-tldr` | mcp | Enabled | `tldr-mcp --version` |
| `cass-memory` | cli | Enabled | `cm --version` |
| `context-plus` | mcp | Enabled | `npx -y contextplus --help` |
| `serena` | mcp | Enabled | `serena --help` |

**Current Status: FULL_GO**

All four tools are enabled and pass Layer 1-3 checks:
- CLI tools (`cass-memory`): Green when host runtime health passes
- MCP tools (`llm-tldr`, `context-plus`, `serena`): Green when:
  1. Host runtime health passes
  2. IDE configs are rendered
  3. Client visibility confirmed

**Known Limitations (from evidence/layer4.txt):**
- Claude Code: All MCP tools visible ✓
- Codex CLI: All MCP tools listed and enabled ✓ (via `mcp_servers`)
- OpenCode: All MCP tools connected ✓ (via `mcp` array)
- Gemini CLI: All MCP tools connected ✓ (via `~/.gemini/settings.json`)

Full GO achieved for all four primary clients showing MCP tool visibility (Codex verified on macmini, optional on Linux).

**Merge gate source of truth:** `docs/runbook/fleet-sync/merge-acceptance-matrix.md`
This matrix is mandatory before merge and defines required host/client pass cells.

**Operator expectations:**
- Daily/weekly audits should pass (green) if all enabled tools pass
- CLI tools only need Layer 1 (host runtime) - NOT Layer 4 (client visibility)
- MCP tools need both Layer 1 and Layer 4
- To add a new tool: add to `configs/mcp-tools.yaml` with `integration_mode: mcp|cli`
- To disable a broken tool: set `enabled: false` with `disabled_reason`

## Freshness / Remote Snapshot Rules

Remote host payloads fail deterministically when:

- snapshot missing (`remote_snapshot_missing`)
- snapshot stale beyond `audit.thresholds.tool_stale_hours` (`remote_snapshot_stale`)
- payload invalid (`remote_snapshot_unparseable`)

## Skills-Plane Health (Weekly)

Weekly fleet checks include two skills-related governance checks:

### Local Diagnosis (skills-doctor)

For diagnosing skills-plane issues on a single VM:

```bash
~/.agent/skills/health/skills-doctor/check.sh
~/.agent/skills/health/skills-doctor/check.sh --json
```

The skills-doctor verifies:
- Skills plane exists at `~/.agent/skills`
- Symlink points at canonical agent-skills (or is git checkout)
- `AGENTS.md` and baseline artifacts present
- Required skill directories for repo profile

### Fleet Governance (dx-fleet weekly)

Two weekly checks provide fleet-wide skills alignment:

**`skills_plane_alignment`**

Verifies the shared skills plane on each canonical host:
- Skills plane exists
- Symlink target is canonical (or git checkout)
- `AGENTS.md` present
- Baseline artifact (`dist/universal-baseline.md`) exists
- Core skill directories present

**`ide_bootstrap_alignment`**

Verifies IDE bootstrap rails point at skills plane:
- `~/.claude/CLAUDE.md` points at `~/.agent/skills/AGENTS.md`
- `~/.gemini/GEMINI.md` points at `~/.agent/skills/AGENTS.md`
- `~/.config/opencode/AGENTS.md` points at `~/.agent/skills/AGENTS.md`

### Why Weekly, Not Daily?

These checks are weekly because:
- Skills plane installation changes infrequently
- IDE bootstrap is typically a one-time setup
- Misalignment indicates systemic issues requiring manual intervention
- Daily checks would be noisy for what is fundamentally an install-time concern

### Repairing Skills-Plane Issues

If `skills_plane_alignment` fails:
```bash
# Re-link the skills plane
ln -sf ~/agent-skills ~/.agent/skills

# Or if not a checkout, clone it
git clone https://github.com/stars-end/agent-skills.git ~/.agent/skills
```

If `ide_bootstrap_alignment` fails:
```bash
# Claude Code
mkdir -p ~/.claude
ln -sf ~/.agent/skills/AGENTS.md ~/.claude/CLAUDE.md

# Gemini CLI
mkdir -p ~/.gemini
ln -sf ~/.agent/skills/AGENTS.md ~/.gemini/GEMINI.md
```

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

Rollback (remove Fleet Sync MCP configs from IDE files):

```bash
# Remove Fleet Sync managed blocks from IDE configs
# Manual edit required - remove sections between:
#   # BEGIN FLEET_SYNC_MCP_MANAGED
#   # END FLEET_SYNC_MCP_MANAGED
```
