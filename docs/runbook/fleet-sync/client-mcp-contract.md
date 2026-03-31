# Fleet Sync: Client MCP Integration Contract (V1.0)

## Overview
This document defines the authoritative configuration and registration contract for Model Context Protocol (MCP) servers across all canonical client surfaces.

## Client Matrix

| Client | Config Path | Format | Registration Method | Verification Command | Status |
|--------|-------------|--------|---------------------|----------------------|--------|
| `claude-code` | `~/.claude.json` | JSON | File Patch | `claude mcp list` | `VERIFIED` |
| `gemini-cli` | `~/.gemini/settings.json` | JSON | File Patch | `gemini mcp list` | `VERIFIED` |
| `antigravity` | `~/.gemini/antigravity/mcp_config.json` | JSON | File Patch | (no native list command) | `INFERRED` |
| `codex-cli` | `~/.codex/config.toml` | TOML | File Patch | `codex mcp list` | `VERIFIED` |
| `opencode` | `~/.config/opencode/opencode.jsonc` | JSONC | File Patch | `opencode mcp list` | `VERIFIED` |

## Client-Specific Contracts

### Claude Code (`claude-code`)
- **Upstream Docs**: [Model Context Protocol in Claude Code](https://docs.anthropic.com/claude/docs/claude-code-mcp)
- **Source of Truth**: `~/.claude.json` (JSON)
- **Durable Registration**: Add entries to the `mcpServers` object in the JSON file.
- **Caveats**: Supports per-project overrides via `.claude.json` in project roots.

### Gemini CLI (`gemini-cli` / `antigravity`)
- **Upstream Docs**: [Gemini CLI MCP Documentation](https://geminicli.com/docs/core/mcp)
- **Source of Truth**:
  - `gemini-cli`: `~/.gemini/settings.json`
  - `antigravity`: `~/.gemini/antigravity/mcp_config.json`
- **Durable Registration**: Add/maintain `mcpServers` entries in both files.

### Codex CLI (`codex-cli`)
- **Upstream Docs**: [Codex CLI MCP Support](https://developers.openai.com/codex/mcp/)
- **Source of Truth**: `~/.codex/config.toml` (TOML)
- **Durable Registration**: Add entries under the `[mcp_servers]` table.
- **Verification**: `codex mcp list`

### OpenCode (`opencode`)
- **Upstream Docs**: [OpenCode MCP Guide](https://opencode.ai/docs/mcp-servers/)
- **Source of Truth**: `~/.config/opencode/opencode.jsonc` (JSONC)
- **Durable Registration**: Add entries to the `mcp` object.
- **Format**:
  ```json
  "mcp": {
    "server-name": {
      "type": "local",
      "command": ["command", "arg1", "arg2"]
    }
  }
  ```
- **Verification**: `opencode mcp list`

## Host Coverage Requirements
| Host | Role | Required Clients |
|------|------|------------------|
| `macmini` | macOS Dev | All 5 |
| `epyc6` | Linux Dev | 4 (Codex optional/unverified) |
| `epyc12` | Linux Dev | 4 (Codex optional/unverified) |
| `homedesktop-wsl` | Linux/WSL | 4 (Codex optional/unverified) |

## Tool Support Matrix
| Tool | claude-code | gemini-cli | codex-cli | opencode |
|------|-------------|------------|-----------|----------|
| `llm-tldr` | MCP (contained) | MCP (contained) | MCP (contained) | MCP (contained) |
| `serena` | MCP | MCP | MCP | MCP |
| `cass-memory` | CLI Only | CLI Only | CLI Only | CLI Only |

## Verification Protocol
1. **Host Health**: Ensure tool binary is in PATH.
2. **Config Health**: Ensure server entry exists in the correct config file with correct key and structure.
3. **Client Visibility**: Run `[client] mcp list` and ensure the tool is reported as "Connected" (or "✓").
