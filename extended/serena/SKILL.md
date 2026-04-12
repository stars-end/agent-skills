---
name: serena
description: MCP-native symbol-aware editing for precise rename/refactor/insertion workflows; assistant memory is secondary.
tags:
  - mcp
  - memory
  - fleet-sync
  - ai-assistant
  - refactor
---

# Serena (Fleet Sync V2.2)

MCP-native symbol-aware editing for precise rename/refactor/insertion workflows.

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
      "command": "~/.local/bin/serena",
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
- Provides symbol-aware edit tools and optional project continuity

## Required Trigger Contract

Use `serena` first only when the task is an explicit symbol operation:
- rename/refactor of known symbols
- insert-before/after-symbol edits
- replace the body or signature of a known symbol safely
- structured symbol lookup or reference gathering before editing a known target

Default to patch/diff-first CLI editing for ordinary file edits, small textual
changes, and search-driven edits that do not require symbol-aware operations.

Project memory or session continuity is secondary. Do not reach for `serena`
just to preserve context unless continuity itself is the task.

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

GUI IDEs such as Antigravity may not inherit shell PATH. Fleet Sync renders the
MCP command as `~/.local/bin/serena`, which expands to an absolute executable
path in generated configs.

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
- `llm-tldr`: Canonical default for semantic + structural analysis (V8.6)
- `cass-memory`: Pilot-only CLI memory
