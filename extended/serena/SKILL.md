---
name: serena
description: AI assistant memory MCP server. DISABLED pending end-to-end validation.
tags:
  - mcp
  - memory
  - fleet-sync
  - disabled
---

# Serena (Fleet Sync V2.2)

AI assistant memory MCP server for persistent context across sessions.

## Current Status

**DISABLED** - Pending end-to-end validation.

## Tool Class

**`integration_mode: mcp`**

Serena is intended as an MCP server but is currently disabled until proven working end-to-end.

## Blocker

The PyPI package `serena` is an unrelated AMQP client. The correct package must be installed from GitHub:

```bash
# Correct installation (from GitHub)
uv tool install git+https://github.com/oraios/serena.git

# WRONG - Do not use PyPI
uv tool install serena  # This installs the wrong package!
```

## Health Commands

```bash
# Version/help check
serena start-mcp-server --help
```

## MCP Configuration (When Enabled)

Would be rendered to IDE configs:

```json
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "serena",
      "args": ["start-mcp-server"]
    }
  }
}
```

## State Storage

- Uses `.serena/memories/` for state

## Validation Requirements

Before enabling, verify:

1. **Layer 1 - Host Runtime**:
   ```bash
   serena start-mcp-server --help
   ```

2. **Layer 4 - Client Visibility**:
   ```bash
   codex mcp list    # Must show serena
   claude mcp list   # Must show serena
   opencode mcp list # Must show serena
   ```

3. **Functional Test**:
   - Tool must respond to MCP protocol messages
   - Memory operations must work end-to-end

## How to Enable

1. Install from GitHub on all canonical hosts
2. Verify Layer 1 health commands pass
3. Verify Layer 4 client visibility
4. Update `configs/mcp-tools.yaml`: set `enabled: true`
5. Run `dx-mcp-tools-sync.sh --apply --json`
6. Run `dx-fleet.sh converge --check --json`

## Upstream

- **Repo**: https://github.com/oraios/serena
- **Docs**: https://github.com/oraios/serena#readme

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `cass-memory`: CLI-native memory (enabled)
