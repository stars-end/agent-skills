---
name: serena
description: MCP-native AI assistant memory for persistent context across sessions.
tags:
  - mcp
  - memory
  - fleet-sync
  - ai-assistant
---

# Serena (Fleet Sync V2.2)

MCP-native AI assistant memory for persistent context across sessions.

## Tool Class

**`integration_mode: mcp`**

Serena is rendered to IDE MCP configs and provides MCP server functionality.

## Current Fleet Status

- Fleet contract: MCP-rendered tool
- Current state: ✅ ENABLED
- Install: `uv tool install git+https://github.com/oraios/serena.git`

## Installation

**IMPORTANT**: The PyPI package `serena` is an unrelated AMQP client. Must install from GitHub:

```bash
# Install from GitHub
uv tool install git+https://github.com/oraios/serena.git
```

This installs:
- `serena` - CLI tool
- `serena-mcp-server` - MCP server binary
- `index-project` - Project indexing tool

## Health Commands

```bash
# CLI help
serena --help

# MCP server help
serena start-mcp-server --help
```

## MCP Configuration

Rendered to IDE configs via Fleet Sync:

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

## Usage Patterns

### CLI Usage
```bash
# Manage projects
serena project list
serena project add /path/to/project

# Manage contexts
serena context list

# Start MCP server manually
serena start-mcp-server --project my-project
```

### Via MCP Client
- Use via MCP-capable IDE
- Provides persistent memory and context across sessions

## Key Commands

| Command | Description |
|---------|-------------|
| `serena project` | Manage projects |
| `serena context` | Manage contexts |
| `serena mode` | Manage modes |
| `serena start-mcp-server` | Start MCP server |
| `serena tools` | View available tools |

## State Storage

- Uses `.serena/` directory in project root
- Stores memories, contexts, and configuration

## Runtime Requirements

- Python 3.12+
- uv package manager

## Fleet Sync Integration

```bash
# Check health via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="serena")'

# Install via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json
```

## IDE Targets

Rendered to these IDE configs:
- `codex-cli`: `~/.codex/config.toml`
- `claude-code`: `~/.claude.json`
- `antigravity`: `~/.gemini/antigravity/mcp_config.json`
- `opencode`: `~/.opencode/config.json`

## Upstream

- **Repo**: https://github.com/oraios/serena
- **Docs**: https://github.com/oraios/serena#readme

## Validation

### Layer 1 (Host Runtime)
```bash
serena --help
```

### Layer 2 (Config Convergence)
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json
```

### Layer 4 (Client Visibility)
```bash
codex mcp list    # Should show serena
claude mcp list   # Should show serena
opencode mcp list # Should show serena
```

## Troubleshooting

### PyPI Package Collision
If `uv tool install serena` installs an AMQP client, uninstall and use GitHub:
```bash
uv tool uninstall serena
uv tool install git+https://github.com/oraios/serena.git
```

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `cass-memory`: CLI-native memory
- `llm-tldr`: MCP static analysis
