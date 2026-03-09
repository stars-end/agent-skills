# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Expected Client Surface |
|------|-------|-------------------|------------------|-------------------------|
| `cass-memory` | `cli` | `npm install -g Dicklesworthstone/cass_memory_system` | `cm --version`, `cm quickstart --json` | Host runtime only; not rendered to IDE configs |
| `llm-tldr` | `mcp` | `uv tool install "llm-tldr==1.5.2"` | `tldr-mcp --version \|\| llm-tldr --version` | `codex`, `claude`, `gemini`, `opencode` where configured |
| `context-plus` | `mcp` | `npx -y contextplus` | `npx -y contextplus --help \| head -1` | `codex`, `claude`, `gemini`, `opencode` where configured |
| `serena` | `mcp` | `uv tool install git+https://github.com/oraios/serena.git` | `serena --help \| head -1` | `codex`, `claude`, `gemini`, `opencode` where configured |

## Canonical Rules

- `cli` tools must not create IDE drift failures.
- `mcp` tools must pass both:
  - manifest/render/file-level checks
  - real client CLI visibility checks
- Google surfaces:
  - `antigravity`
  - `gemini-cli`
  share one MCP config root.

## Current Status (V2.2)

All four tools are enabled and operational:
- `cass-memory`: CLI-native episodic memory
- `llm-tldr`: MCP static analysis context slicing
- `context-plus`: MCP structural context analysis
- `serena`: MCP AI assistant memory

## Known Caveats

- `cass-memory` is CLI-native and should NOT appear in IDE MCP configs. If manually added, it will show as "Failed to connect" in `claude mcp list`.
- `serena` PyPI has package collision with an unrelated AMQP client - must install from GitHub.
- `context-plus` package name is `contextplus` (not `@forloopcodes/contextplus`).
