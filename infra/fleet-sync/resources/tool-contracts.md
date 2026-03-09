# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Expected Client Surface |
|------|-------|-------------------|------------------|-------------------------|
| `cass-memory` | `cli` | `brew install dicklesworthstone/tap/cm` | `cm --version`, `cm quickstart --json`, `cm doctor --json` | Host runtime only; not required in MCP configs |
| `llm-tldr` | `mcp` | `uv tool install "llm-tldr==1.5.2"` | `tldr-mcp --version \|\| llm-tldr --version` | `codex`, `claude`, `gemini`, `opencode` where configured |
| `context-plus` | `mcp` | Validate real package `contextplus` on the current host | `contextplus --version` | `codex`, `claude`, `gemini`, `opencode` where configured |
| `serena` | `mcp` | Unresolved until a proven executable path exists | must prove executable entrypoint | same as above, only after proof |

## Canonical Rules

- `cli` tools must not create IDE drift failures.
- `mcp` tools must pass both:
  - manifest/render/file-level checks
  - real client CLI visibility checks
- Google surfaces:
  - `antigravity`
  - `gemini-cli`
  share one MCP config root.

## Current Known Risks

- `cass-memory` can be installed but still degraded/unhealthy at runtime.
- `context-plus` package naming has historically been wrong in the manifest.
- `serena` remains the highest-risk unresolved tool due to package collision and executable uncertainty.
