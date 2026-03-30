---
name: fleet-sync
description: Fleet Sync orchestrator for MCP tool convergence, health checks, and IDE config management across canonical VMs.
tags:
  - fleet
  - mcp
  - tools
  - convergence
  - health
  - dx
---

# Fleet Sync (V2.2)

Fleet Sync provides local-first MCP tool distribution and IDE rendering across canonical VMs.

## Canonical Surfaces

### VMs
- `macmini` - Primary macOS host
- `homedesktop-wsl` - WSL2 workstation
- `epyc6` - Primary Linux host
- `epyc12` - Secondary Linux host

### IDE Lanes
| IDE | Config Path | Format |
|-----|-------------|--------|
| `antigravity` | `~/.gemini/antigravity/mcp_config.json` | JSON |
| `claude-code` | `~/.claude.json` | JSON |
| `codex-cli` | `~/.codex/config.toml` | TOML |
| `opencode` | `~/.opencode/config.json` | JSON |
| `gemini-cli` | `~/.gemini/antigravity/mcp_config.json` | JSON |

## Tool Classes

### MCP Tools (`integration_mode: mcp`)
Rendered into IDE MCP configs with `mcp.*` block.

| Tool | Status | Binary | Health |
|------|--------|--------|--------|
| `llm-tldr` | Enabled | `tldr-mcp` | `tldr-mcp --version` |
| `serena` | Enabled | `serena` | `serena start-mcp-server --help` |

### CLI Tools (`integration_mode: cli`)
Standalone CLI tools, not rendered to IDE configs.

| Tool | Status | Binary | Health |
|------|--------|--------|--------|
| `cass-memory` | Enabled | `cm` | `cm --version` |

## Commands

### Host-Level Convergence
```bash
# Drift detection only
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json

# Install tools + render IDE configs
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json

# Force re-apply + verify
~/agent-skills/scripts/dx-mcp-tools-sync.sh --repair --json
```

### Fleet-Wide Operations
```bash
# Fleet-wide drift check
~/agent-skills/scripts/dx-fleet.sh converge --check --json

# Fleet-wide apply
~/agent-skills/scripts/dx-fleet.sh converge --apply --json

# Fleet-wide repair
~/agent-skills/scripts/dx-fleet.sh converge --repair --json
```

### Fleet Health Checks
```bash
# Daily runtime checks
~/agent-skills/scripts/dx-fleet.sh check --mode daily --json

# Weekly governance checks
~/agent-skills/scripts/dx-fleet.sh check --mode weekly --json
```

### Fleet Audit
```bash
# Daily audit
~/agent-skills/scripts/dx-fleet.sh audit --daily --json

# Weekly audit
~/agent-skills/scripts/dx-fleet.sh audit --weekly --json
```

## Validation Layers

### Layer 1: Host Runtime Health
Verify tool binaries work on each host:
```bash
# MCP tools
tldr-mcp --version || llm-tldr --version

# CLI tools
cm --version
cm quickstart --json
cm doctor --json
```

### Layer 2: Config Convergence
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet
```

### Layer 3: Fleet Gates
```bash
~/agent-skills/scripts/dx-fleet.sh check --mode daily --json --state-dir ~/.dx-state/fleet
~/agent-skills/scripts/dx-fleet.sh audit --weekly --json --state-dir ~/.dx-state/fleet
```

### Layer 4: Client Visibility
Verify MCP tools appear in IDE clients:
```bash
codex mcp list    # Should show llm-tldr
claude mcp list   # Should show llm-tldr
gemini mcp list   # Should show llm-tldr
opencode mcp list # Should show llm-tldr
```

Note: `cass-memory` is CLI-native and does NOT need to appear in MCP lists.

## Fail-Closed Semantics

The `overall` status is computed from BOTH tool rows AND file rows:
- If `tools_fail > 0` → `overall = "red"`
- If `files_fail > 0` → `overall = "red"`
- If `warn > 0` → `overall = "yellow"`
- Otherwise → `overall = "green"`

## Manifest Source

Single source of truth: `~/agent-skills/configs/mcp-tools.yaml`

Key fields per tool:
- `enabled`: true/false
- `integration_mode`: "mcp" or "cli"
- `install_cmd`: Installation command
- `health_cmd`: Health check command
- `target_ides`: IDE targets (MCP only)
- `mcp`: MCP server config block (MCP only)

## Related Skills

- `llm-tldr`: Static analysis context slicing
- `cass-memory`: CLI-native episodic memory
- `serena`: Symbol-aware edits and persistent memory

## Related Docs

- `~/agent-skills/docs/FLEET_SYNC_SPEC.md` - Architecture contract
- `~/agent-skills/docs/FLEET_SYNC_RUNBOOK.md` - Operational runbook
- `~/agent-skills/docs/IDE_SPECS.md` - IDE specifications
- `~/agent-skills/scripts/canonical-targets.sh` - VM/IDE registry

## Escalation

- `green`: No action
- `yellow`: Run `dx-fleet repair --json`
- `red`: Run repair on failing hosts and rerun checks
