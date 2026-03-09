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

Verify MCP tools are visible to IDE clients.

**Current Observed Reality (2026-03-09):**

| Client | Fleet Sync MCP Tools Visible | Status |
|--------|------------------------------|--------|
| Claude Code | ✓ All tools connected | Working |
| Codex CLI | ✗ Only shows playwright | Config not read |
| OpenCode | ✗ "No MCP servers configured" | Config not read |
| Gemini CLI | ✗ "No MCP servers configured" | Config not read |

### Claude Code

```bash
claude mcp list
```

**Observed:** All MCP tools show "Connected":
- `llm-tldr: tldr-mcp - Connected` ✓
- `context-plus: npx -y contextplus - Connected` ✓
- `serena: serena start-mcp-server - Connected` ✓

Note: `cass-memory` is CLI-native and should NOT appear here (or will show "Failed to connect" if manually added).

### Codex CLI

```bash
codex mcp list
```

**Observed:** Only shows `playwright` (not managed by Fleet Sync). Fleet Sync MCP tools not visible.

**Root Cause:** Config format mismatch. Fleet Sync writes `[mcpServers.*]` but Codex may expect `[mcp_servers.*]`.

### OpenCode

```bash
opencode mcp list
```

**Observed:** "No MCP servers configured" even though `~/.opencode/config.json` contains Fleet Sync entries.

**Root Cause:** Client not reading config file or using different path.

### Gemini CLI

```bash
gemini mcp list
```

**Observed:** "No MCP servers configured" even though `~/.gemini/antigravity/mcp_config.json` contains Fleet Sync entries.

**Root Cause:** Client not reading config file or using different path.

### Full GO Requirements

For full Fleet Sync GO, all four clients must show MCP tool visibility. Currently only Claude Code passes Layer 4.

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
