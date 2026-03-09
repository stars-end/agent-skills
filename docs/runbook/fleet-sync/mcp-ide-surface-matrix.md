# Fleet Sync MCP IDE Surface Matrix (bd-d8f4)

## Canonical Host x Client Surface Matrix

| Client Surface | macmini | epyc6 | homedesktop-wsl | epyc12 |
|----------------|---------|-------|-----------------|--------|
| `codex`        | [INFERRED] | [INFERRED] | [INFERRED] | [INFERRED] |
| `claude`       | [INFERRED] | [INFERRED] | [INFERRED] | [INFERRED] |
| `gemini-cli`   | [INFERRED] | [INFERRED] | [INFERRED] | [INFERRED] |
| `antigravity`  | [INFERRED] | [INFERRED] | [INFERRED] | [INFERRED] |
| `opencode`     | [INFERRED] | [INFERRED] | [INFERRED] | [INFERRED] |

*(Note: Verification requires explicit host-qualified command evidence for Layer 4 visibility. All surfaces are marked INFERRED until this evidence is collected.)*

## Layer 4 Client Visibility Commands

Agents must run these commands to verify Layer 4 visibility of installed MCP tools:

- **Codex:** `codex mcp list`
- **Claude Code:** `claude mcp list`
- **Gemini CLI:** `gemini mcp list`
- **OpenCode:** `opencode mcp list`

## Shared Config Surfaces

- **Google MCP Surface:** `antigravity` and `gemini-cli` share the identical configuration surface and path (`~/.gemini/antigravity/mcp_config.json`).
- While the configuration file is shared, Layer 4 visibility still requires per-client verification unless there is explicit proof that their respective MCP clients are literally the same binary/runtime. `gemini mcp list` proves parsing for the CLI, but `antigravity` may still need its own independent visibility check depending on its runtime implementation.

## System State Clarifications
Docs clearly distinguish between three layers of system health:
1. **Host Runtime Health:** Verified directly by running the tool's health command (e.g. `tldr-mcp --version` or `cm --version`) in the terminal. Proves the binary runs.
2. **File/Config Convergence:** Verified by inspecting the physical configuration file (e.g. `cat ~/.claude.json`) to confirm the expected configuration block exists on disk.
3. **Client-Visible MCP Availability:** Verified by running the respective Layer 4 client visibility command (e.g. `claude mcp list`). This proves the client successfully parsed the config, spawned the transport, and registered the tool.