# Fleet Sync: Client MCP Integration Contract (V1.0)

## Overview
This document defines the authoritative configuration and registration contract for Model Context Protocol (MCP) servers across all canonical client surfaces.

## Client Matrix

| Client | Config Path | Format | Registration Method | Verification Command | Status |
|--------|-------------|--------|---------------------|----------------------|--------|
| `claude-code` | `~/.claude.json` | JSON | File Patch | `claude mcp list` | `VERIFIED` |
| `gemini-cli` | `~/.gemini/settings.json` | JSON | File Patch | `gemini mcp list` | `VERIFIED` |
| `antigravity` | `~/.gemini/settings.json` | JSON | Same as gemini-cli | `antigravity chat --help` | `VERIFIED` |
| `codex-cli` | `~/.codex/config.toml` | TOML | File Patch | `codex mcp list` | `VERIFIED` |
| `opencode` | `~/.config/opencode/opencode.jsonc` | JSONC | File Patch | `opencode mcp list` | `BLOCKED` |

## Client-Specific Contracts

### Claude Code (`claude-code`)
- **Upstream Docs**: [Model Context Protocol in Claude Code](https://docs.anthropic.com/claude/docs/claude-code-mcp)
- **Source of Truth**: `~/.claude.json` (JSON)
- **Durable Registration**: Add entries to the `mcpServers` object in the JSON file.
- **Caveats**: Supports per-project overrides via `.claude.json` in project roots.

### Gemini CLI (`gemini-cli` / `antigravity`)
- **Upstream Docs**: [Gemini CLI MCP Documentation](https://geminicli.com/docs/core/mcp)
- **Source of Truth**: `~/.gemini/settings.json` (JSON)
- **Durable Registration**: Add entries to the `mcpServers` object in `~/.gemini/settings.json`.
- **Note**: `antigravity` (the desktop IDE) may show separate configuration for its internal Claude instance, but for Fleet Sync tool registration, the CLI settings file is the target.

### Codex CLI (`codex-cli`)
- **Upstream Docs**: [Codex CLI MCP Support](https://codex.ai/docs/mcp)
- **Source of Truth**: `~/.codex/config.toml` (TOML)
- **Durable Registration**: Add entries under the `[mcp_servers]` table.
- **Verification**: `codex mcp list`

### OpenCode (`opencode`)
- **Upstream Docs**: [OpenCode MCP Guide](https://opencode.ai/docs/mcp)
- **Source of Truth**: `~/.config/opencode/opencode.jsonc` (JSONC)
- **Blocker**: The current client (v1.2.20) does not recognize the `mcpServers` key in `opencode.jsonc`, and `opencode mcp add` fails to persist servers.
- **Status**: `BLOCKED`. Fleet Sync tools are rendered but invisible to the client.

## Host Coverage Requirements
| Host | Role | Required Clients |
|------|------|------------------|
| `macmini` | macOS Dev | All 5 |
| `epyc6` | Linux Dev | All 5 |
| `epyc12` | Linux Dev | All 5 |
| `homedesktop-wsl` | Linux/WSL | All 5 |

## Tool Support Matrix
| Tool | claude-code | gemini-cli | codex-cli | opencode |
|------|-------------|------------|-----------|----------|
| `llm-tldr` | ✅ | ✅ | ✅ | ❌ |
| `context-plus` | ✅ | ✅ | ✅ | ❌ |
| `serena` | ✅ | ✅ | ✅ | ❌ |
| `cass-memory` | CLI Only | CLI Only | CLI Only | CLI Only |

## Verification Protocol
1. **Host Health**: Ensure tool binary is in PATH.
2. **Config Health**: Ensure `mcpServers` entry exists in the correct config file.
3. **Client Visibility**: Run `[client] mcp list` and ensure the tool is reported as "Connected".
