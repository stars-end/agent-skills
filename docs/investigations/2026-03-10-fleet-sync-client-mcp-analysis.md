# Investigation Analysis: Fleet Sync Client MCP Integration

- Date: 2026-03-10
- Beads ID: bd-d8f4
- Researcher: gemini-cli

## Objective
Establish an authoritative integration contract for MCP clients across the canonical fleet, resolving discrepancies between documented paths and actual runtime behavior.

## Research Findings

### 1. Claude Code (`claude-code`)
- **Verified Path**: `~/.claude.json`
- **Behavior**: Reads `mcpServers` globally and per-project.
- **Status**: `VERIFIED`

### 2. Gemini CLI / Antigravity
- **Verified Path**: `~/.gemini/settings.json`
- **Behavior**: The CLI ignores `~/.gemini/antigravity/mcp_config.json`. New servers must be added via `gemini mcp add --scope user` or direct patch to `settings.json`.
- **Relationship**: `antigravity` inherits these settings at runtime for its integrated agent.
- **Status**: `VERIFIED`

### 3. Codex CLI (`codex-cli`)
- **Verified Path**: `~/.codex/config.toml`
- **Behavior**: Uses the `[mcp_servers]` table format.
- **Status**: `VERIFIED`

### 4. OpenCode (`opencode`)
- **Config Path**: `~/.config/opencode/opencode.jsonc`
- **Durable Registration**: Uses the `mcp` key (not `mcpServers`).
- **Format**: Requires array-style command definition.
- **Status**: `VERIFIED`

## Conclusion
We have verified durable registration paths for all 4 primary clients. Full Layer 4 convergence is now achievable across the entire canonical fleet.
