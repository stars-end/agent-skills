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

## Current Fleet Status

- Fleet contract: MCP-rendered tool
- Current state: ✅ ENABLED
- Install: `npx -y contextplus` or `bunx contextplus`

## Installation

```bash
# Option 1: Run directly with npx (recommended)
npx -y contextplus

# Option 2: Install globally with bun
bunx contextplus
```

**NOTE**: The correct package name is `contextplus` (NOT `@forloopcodes/contextplus` which returns 404).

## Health Commands

```bash
# Version check
npx -y contextplus --version

# Help
npx -y contextplus --help
```

## MCP Configuration

Rendered to IDE configs via Fleet Sync:

```json
{
  "mcpServers": {
    "context-plus": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "contextplus"]
    }
  }
}
```

## Usage Patterns

### Via MCP Client
- Use via MCP-capable IDE (Claude Code, Cursor, VS Code, Windsurf, OpenCode)
- The tool provides structural analysis capabilities

### Key Functions
- **Semantic Code Search**: Find code by meaning, not just keywords
- **AST-based Analysis**: Tree-sitter powered structural understanding
- **Spectral Clustering**: Group semantically related files
- **RAG Integration**: Combine with Ollama for enhanced retrieval
- **Wikilink Hubs**: Obsidian-style feature navigation

## Status
- Fleet contract: MCP-rendered tool
- Expected package: `contextplus`
- Expected runtime: Node.js
- Canonical health checks:
  - `npx -y contextplus --version`
  - client MCP visibility checks such as `claude mcp list`, `codex mcp list`, `gemini mcp list`, `opencode mcp list`

## Upstream Docs
- GitHub: `https://github.com/ForLoopCodes/contextplus`
- npm package: `https://www.npmjs.com/package/contextplus`

## Contract

1. **Local-first**: Execute locally via stdio MCP
2. **No central gateway**: Never a mandatory central gateway dependency
3. **Repository-local**: Prefer repository-local indexes and embeddings
4. **Fail open**: Fail open to normal local navigation if unavailable

## Expected Output

- Ranked target files/modules
- Dependency or cluster hints for safer edits
- Semantic code clusters

## Runtime Requirements

- Node.js 20+ (or Bun)
- Ollama (optional, for embeddings)

## Optional Environment Variables

| Env Var | Purpose |
|---------|---------|
| `OLLAMA_EMBED_MODEL` | Ollama embedding model (default: nomic-embed-text) |
| `OLLAMA_CHAT_MODEL` | Ollama chat model (default: gemma2:27b) |
| `OLLAMA_API_KEY` | Ollama API key (for cloud) |

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
npx -y contextplus --version
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
npx -y contextplus
```

### Version Issues
The historical manifest version `0.0.7` may not be available. Use `latest` or run without version specifier.

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `llm-tldr`: MCP static analysis
- `cass-memory`: CLI-native memory
