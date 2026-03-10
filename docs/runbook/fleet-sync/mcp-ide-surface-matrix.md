# Fleet Sync MCP IDE Surface Matrix (bd-d8f4)

## Overview
This matrix tracks the configuration paths, formats, and current integration status for all 5 canonical IDE surfaces.

## IDE Matrix

| IDE | Config Path | Format | Patch Method | OS Differences | Status |
|-----|-------------|--------|--------------|----------------|--------|
| `antigravity` | `~/.gemini/settings.json` | JSON | jq/patch | Same as gemini-cli | `INFERRED` |
| `claude-code` | `~/.claude.json` | JSON | jq/patch | None | `VERIFIED` |
| `codex-cli` | `~/.codex/config.toml` | TOML | toml-cli/sed | None | `VERIFIED` |
| `opencode` | `~/.config/opencode/opencode.jsonc` | JSONC | File Patch | None | `VERIFIED` |
| `gemini-cli` | `~/.gemini/settings.json` | JSON | jq/patch | None | `VERIFIED` |

## Verification Status by Host

| Host | Verified IDEs | Notes |
|------|---------------|-------|
| `macmini` | All 5 | Full verification completed 2026-03-10 |
| `epyc6` | All 5 | Full verification completed 2026-03-10 |
| `epyc12` | All 5 | Full verification completed 2026-03-10 |
| `homedesktop-wsl` | All 5 | Full verification completed 2026-03-10 |

## Key Research Observations
- `opencode` requires the `mcp` key and an array-style command format.
- `gemini-cli` and `antigravity` share the same configuration root at `~/.gemini/settings.json`.
- `codex-cli` requires the underscored `mcp_servers` key in TOML.
