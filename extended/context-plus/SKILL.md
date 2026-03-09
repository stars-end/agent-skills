---
name: context-plus
description: MCP-native structural context analysis for codebase mapping and dependency-aware targeting.
tags:
  - mcp
  - context
  - structure
  - fleet-sync
  - local-first
---

# Context+ (Fleet Sync V2.2)

MCP-native structural context analysis for higher-fidelity codebase mapping before edits.

## Tool Class

**`integration_mode: mcp`**

Context+ is rendered to IDE MCP configs and provides MCP server functionality.

## Installation

```bash
# Install via npm (correct package name)
npm install -g contextplus@1.0.7
```

**IMPORTANT**: The correct package name is `contextplus`, NOT `@forloopcodes/contextplus`.

## Health Commands

```bash
# Version check
contextplus --version
```

## MCP Configuration

Rendered to IDE configs via Fleet Sync:

```json
{
  "mcpServers": {
    "context-plus": {
      "type": "stdio",
      "command": "contextplus",
      "args": ["--transport", "stdio"]
    }
  }
}
```

## Usage Patterns

### Via MCP Client
```bash
# Use via MCP-capable IDE
# The tool provides structural analysis capabilities
```

### Key Functions
- Repository-local indexes and embeddings
- Ranked target files/modules
- Dependency or cluster hints for safer edits

## Contract

1. **Local-first**: Execute locally via stdio MCP
2. **No central gateway**: Never a mandatory central gateway dependency
3. **Repository-local**: Prefer repository-local indexes and embeddings
4. **Fail open**: Fail open to normal local navigation if unavailable

## Inputs

- Local worktree path
- Active branch/repo scope

## Expected Output

- Ranked target files/modules
- Dependency or cluster hints for safer edits

## Runtime Requirements

- Node.js 20+

## Optional Environment Variables

| Env Var | Purpose |
|---------|---------|
| `OLLAMA_EMBED_MODEL` | Ollama embedding model |
| `OLLAMA_CHAT_MODEL` | Ollama chat model |

## Fleet Sync Integration

```bash
# Check health via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="context-plus")'

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

- **Repo**: https://github.com/ForLoopCodes/contextplus
- **Docs**: https://github.com/ForLoopCodes/contextplus#readme

## Validation

### Layer 1 (Host Runtime)
```bash
contextplus --version
```

### Layer 2 (Config Convergence)
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json
```

### Layer 4 (Client Visibility)
```bash
codex mcp list    # Should show context-plus
claude mcp list   # Should show context-plus
opencode mcp list # Should show context-plus
```

## Troubleshooting

### Package Not Found (404)
If you see `@forloopcodes/contextplus not found`, use the correct package name:
```bash
npm install -g contextplus@1.0.7
```

### Version Mismatch
The manifest version `0.4.2` was a typo. Use version `1.0.7`.

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `llm-tldr`: MCP static analysis
- `cass-memory`: CLI-native memory
