# Fleet Sync MCP IDE Surface Matrix (bd-d8f4)

## Overview
This matrix tracks the configuration paths, formats, and current integration status for all 5 canonical IDE surfaces.

## IDE Matrix

| IDE | Config Path | Format | Patch Method | OS Differences | Status |
|-----|-------------|--------|--------------|----------------|--------|
| `antigravity` | `~/.gemini/antigravity/mcp_config.json` | JSON | jq/patch | None | Verified |
| `claude-code` | `~/.claude.json` | JSON | jq/patch | None | Verified |
| `codex-cli` | `~/.codex/config.toml` | TOML | toml-cli/sed | None | Verified |
| `opencode` | `~/.opencode/config.json` | JSON | jq/patch | None | Verified |
| `gemini-cli` | `~/.gemini/antigravity/mcp_config.json` | JSON | jq/patch | Same as antigravity | Verified |

## Verification Notes
- All paths verified on `epyc6` and `macmini` using `scripts/canonical-targets.sh`.
- `codex-cli` and `opencode` currently have legacy `cass-memory` entries in their configs.
- `gemini-cli` and `antigravity` share the same configuration root on all platforms.
- Non-interactive patching is supported via `scripts/dx-mcp-tools-sync.sh`.