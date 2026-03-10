# Fleet Sync MCP IDE Surface Matrix (bd-d8f4)

## Overview
This matrix tracks the configuration paths, formats, and current integration status for all 5 canonical IDE surfaces.

## IDE Matrix

| IDE | Config Path | Format | Patch Method | OS Differences | Status |
|-----|-------------|--------|--------------|----------------|--------|
| `antigravity` | `~/.gemini/settings.json` | JSON | jq/patch | Same as gemini-cli | `VERIFIED` |
| `claude-code` | `~/.claude.json` | JSON | jq/patch | None | `VERIFIED` |
| `codex-cli` | `~/.codex/config.toml` | TOML | toml-cli/sed | None | `VERIFIED` |
| `opencode` | `~/.config/opencode/opencode.jsonc` | JSONC | File Patch | None | `BLOCKED` |
| `gemini-cli` | `~/.gemini/settings.json` | JSON | jq/patch | None | `VERIFIED` |

## Verification Status by Host

| Host | Verified IDEs | Notes |
|------|---------------|-------|
| `epyc6` | All 5 | Primary Linux validation host |
| `macmini` | All 5 | Primary macOS validation host |
| `homedesktop-wsl` | Not yet verified | Inferred from shared config paths |
| `epyc12` | Not yet verified | Inferred from shared config paths |

**Overall Status:** Partially verified (2 of 4 hosts)

## Verification Notes
- All paths verified on `epyc6` and `macmini` using `scripts/canonical-targets.sh`.
- `codex-cli` and `opencode` currently have legacy `cass-memory` entries in their configs.
- `gemini-cli` and `antigravity` share the same configuration root on all platforms.
- Non-interactive patching is supported via `scripts/dx-mcp-tools-sync.sh`.