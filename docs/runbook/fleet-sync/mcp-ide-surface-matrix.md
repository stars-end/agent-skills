# Fleet Sync MCP IDE Surface Matrix (bd-d8f4)

## Canonical Host x Client Surface Matrix

| Client Surface | macmini | epyc6 | homedesktop-wsl | epyc12 |
|----------------|---------|-------|-----------------|--------|
| `codex`        | [VERIFIED] | [VERIFIED] | [INFERRED] | [INFERRED] |
| `claude`       | [VERIFIED] | [VERIFIED] | [INFERRED] | [INFERRED] |
| `gemini-cli`   | [VERIFIED] | [VERIFIED] | [INFERRED] | [INFERRED] |
| `antigravity`  | [VERIFIED] | [VERIFIED] | [INFERRED] | [INFERRED] |
| `opencode`     | [VERIFIED] | [VERIFIED] | [INFERRED] | [INFERRED] |

## Layer 4 Client Visibility Commands

Agents must run these commands to verify Layer 4 visibility of installed MCP tools:

- **Codex:** `codex mcp list`
- **Claude Code:** `claude mcp list`
- **Gemini CLI:** `gemini mcp list`
- **OpenCode:** `opencode mcp list`

## Shared Config Surfaces

- **Google MCP Surface:** `antigravity` and `gemini-cli` share the identical configuration surface and path (`~/.gemini/antigravity/mcp_config.json`).
- Changes to this path affect both surfaces synchronously, meaning `gemini mcp list` serves as the visibility command for both tools.

## System State Clarifications
Docs clearly distinguish between three layers of system health:
1. **Host Runtime Health:** Verified directly by running the tool's health command (e.g. `tldr-mcp --version` or `cm --version`) in the terminal. Proves the binary runs.
2. **File/Config Convergence:** Verified by inspecting the physical configuration file (e.g. `cat ~/.claude.json`) to confirm the expected configuration block exists on disk.
3. **Client-Visible MCP Availability:** Verified by running the respective Layer 4 client visibility command (e.g. `claude mcp list`). This proves the client successfully parsed the config, spawned the transport, and registered the tool.