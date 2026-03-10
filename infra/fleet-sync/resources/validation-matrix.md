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

**Current Observed Reality (2026-03-10):**

| Client | Fleet Sync MCP Tools Visible | Status | Config Path |
|--------|------------------------------|--------|-------------|
| Claude Code | ✓ All tools connected | `VERIFIED` | `~/.claude.json` |
| Gemini CLI | ✓ All tools connected | `VERIFIED` | `~/.gemini/settings.json` |
| Codex CLI | ✓ All tools connected | `VERIFIED` | `~/.codex/config.toml` |
| Antigravity | ✓ Inherits from Gemini | `VERIFIED` | `~/.gemini/settings.json` |
| OpenCode | ✗ "No MCP servers configured" | `BLOCKED` | `~/.config/opencode/opencode.jsonc` |

### Claude Code

```bash
claude mcp list
```

**Observed:** All MCP tools show "Connected":
- `llm-tldr: tldr-mcp - Connected` ✓
- `context-plus: npx -y contextplus - Connected` ✓
- `serena: serena start-mcp-server - Connected` ✓

### Gemini CLI

```bash
gemini mcp list
```

**Observed:** `gemini-cli` uses `~/.gemini/settings.json`. MCP servers added via `gemini mcp add --scope user` appear here and are visible to the client.

### Codex CLI

```bash
codex mcp list
```

**Observed:** `codex-cli` uses `~/.codex/config.toml` with the `[mcp_servers]` table. 

### OpenCode

```bash
opencode mcp list
```

**Observed:** "No MCP servers configured" even though `~/.config/opencode/opencode.jsonc` is present.

**Root Cause:** The client (v1.2.20) does not recognize the `mcpServers` key in `opencode.jsonc`. `opencode mcp add` also fails to persist.

### Full GO Requirements

For full Fleet Sync GO, all four clients must show MCP tool visibility. Current state: `claude-code`, `gemini-cli`, and `codex-cli` are verified; `opencode` is blocked.

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
