# Fleet Sync Validation Matrix

Quick reference for Layer 1-4 validation checks.

## Layer 1: Host Runtime Health

Check if tools are installed and executable.

| Tool | Command | Expected |
|------|---------|----------|
| `cass-memory` | `cm --version` | Version string (e.g., `0.2.3`) |
| `llm-tldr` | `tldr-mcp --version \|\| llm-tldr --version` | Version string (e.g., `1.5.2`) |
| `context-plus` | `npx -y contextplus --help \| head -1` | Help output |
| `serena` | `serena --help \| head -1` | Help output |

## Layer 2: Config Convergence

Run Fleet Sync convergence check:

```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet
```

Expected: `"overall": "green"`, `"tools_fail": 0`, `"files_fail": 0`

## Layer 3: Fleet Gates

Daily and weekly fleet checks:

```bash
# Daily runtime check
~/agent-skills/scripts/dx-fleet.sh check --mode daily --json --state-dir ~/.dx-state/fleet

# Weekly governance check
~/agent-skills/scripts/dx-fleet.sh check --mode weekly --json --state-dir ~/.dx-state/fleet
```

Expected: `"fleet_status": "green"`

## Layer 4: Client Visibility

Verify MCP tools are visible to IDE clients:

### Claude Code

```bash
claude mcp list
```

Expected: All MCP tools show "Connected":
- `llm-tldr: tldr-mcp - Connected`
- `context-plus: npx -y contextplus - Connected`
- `serena: serena start-mcp-server - Connected`

Note: `cass-memory` is CLI-native and should NOT appear here (or will show "Failed to connect" if manually added).

### Codex CLI

```bash
codex mcp list
```

Expected: MCP tools listed with correct commands and args.

### OpenCode

```bash
opencode mcp list
```

Expected: MCP tools listed.

### Gemini CLI

```bash
gemini mcp list
```

Expected: MCP tools listed (shares config with `antigravity`).

## Quick Repair

If checks fail, run repair:

```bash
# Single host repair
~/agent-skills/scripts/dx-mcp-tools-sync.sh --repair --json --state-dir ~/.dx-state/fleet

# Fleet-wide converge
~/agent-skills/scripts/dx-fleet.sh converge --repair --json
```

## Status Semantics

| Status | Meaning | Action |
|--------|---------|--------|
| `green` | All checks pass | None |
| `yellow` | Warnings only | Review, optional repair |
| `red` | Failures detected | Run repair immediately |
