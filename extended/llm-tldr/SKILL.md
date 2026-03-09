---
name: llm-tldr
description: MCP-native static analysis context slicing for precise, low-token task context extraction.
tags:
  - mcp
  - static-analysis
  - context
  - fleet-sync
  - local-first
---

# llm-tldr (Fleet Sync V2.2)

MCP-native static analysis for surgical context extraction and reduced token overhead.

## Tool Class

**`integration_mode: mcp`**

llm-tldr is rendered to IDE MCP configs and provides MCP server functionality.

## Installation

```bash
# Install via uv
uv tool install "llm-tldr==1.5.2"
```

## Health Commands

```bash
# Version check (MCP binary)
tldr-mcp --version

# Fallback version check
llm-tldr --version
```

## MCP Configuration

Rendered to IDE configs via Fleet Sync:

```json
{
  "mcpServers": {
    "llm-tldr": {
      "type": "stdio",
      "command": "tldr-mcp",
      "args": []
    }
  }
}
```

## Usage Patterns

### Via MCP Client
```bash
# Use via MCP-capable IDE
# The tool provides context slicing capabilities
```

### Key Functions
- `context`: Get token-efficient context starting from entry point
- `structure`: Get code structure (codemaps)
- `calls`: Build cross-file call graph
- `cfg`: Get control flow graph for a function
- `dfg`: Get data flow graph for a function
- `dead`: Find unreachable code
- `semantic`: Semantic code search using embeddings

## Contract

1. **Local-first**: Run on local machine via stdio
2. **Token efficient**: 95% token savings vs reading raw files
3. **Fallback path**: Keep fallback to normal repo-local context gathering
4. **Per-project indexes**: No central index requirement

## Runtime Requirements

- Python 3.12+
- tree-sitter dependencies
- FAISS dependencies (for semantic search)

## Fleet Sync Integration

```bash
# Check health via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="llm-tldr")'

# Install via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json
```

## IDE Targets

Rendered to these IDE configs:
- `codex-cli`: `~/.codex/config.toml`
- `claude-code`: `~/.claude.json`
- `opencode`: `~/.opencode/config.json`
- `gemini-cli`: `~/.gemini/antigravity/mcp_config.json`

## Upstream

- **Repo**: https://github.com/simonw/llm-tldr
- **Docs**: https://github.com/simonw/llm-tldr#readme

## Validation

### Layer 1 (Host Runtime)
```bash
tldr-mcp --version || llm-tldr --version
```

### Layer 2 (Config Convergence)
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json
```

### Layer 4 (Client Visibility)
```bash
codex mcp list    # Should show llm-tldr
claude mcp list   # Should show llm-tldr
gemini mcp list   # Should show llm-tldr
opencode mcp list # Should show llm-tldr
```

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `cass-memory`: CLI-native memory
- `context-plus`: MCP structural context
