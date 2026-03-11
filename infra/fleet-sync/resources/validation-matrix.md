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
| Codex CLI | ✓ All tools listed and enabled | `VERIFIED` | `~/.codex/config.toml` |
| Antigravity | ✓ Inherits from Gemini | `INFERRED` | `~/.gemini/settings.json` |
| OpenCode | ✓ All tools connected | `VERIFIED` | `~/.config/opencode/opencode.jsonc` |

### Claude Code

```bash
claude mcp list
```

### Gemini CLI

```bash
gemini mcp list
```

### Codex CLI

```bash
codex mcp list
```

### OpenCode

```bash
opencode mcp list
```

### Full GO Requirements

For full Fleet Sync GO, required host/client cells must pass the pre-merge matrix in:

`docs/runbook/fleet-sync/merge-acceptance-matrix.md`

Current contract:
- `claude`, `gemini`, `opencode` are required on all 4 canonical hosts.
- `codex` is required on `macmini` and optional on Linux hosts.
- `antigravity` remains `INFERRED` via Gemini runtime/config.
