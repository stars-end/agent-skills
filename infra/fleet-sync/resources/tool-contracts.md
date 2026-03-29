# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Expected Client Surface |
|------|-------|-------------------|------------------|-------------------------|
| `cass-memory` | `cli` | `npm install -g Dicklesworthstone/cass_memory_system` | `cm --version`, `cm quickstart --json` | Host runtime only; not rendered to IDE configs |
| `llm-tldr` | `mcp` | `uv tool install "llm-tldr==1.5.2"` | `tldr-mcp --version \|\| llm-tldr --version` | `codex`, `claude`, `gemini`, `opencode` where configured |
| `context-plus` | `mcp` | `scripts/install-contextplus-patched.sh` | `test -f ~/.local/share/contextplus-patched/build/index.js` | `codex`, `claude`, `gemini`, `antigravity`, `opencode` where configured |
| `serena` | `mcp` | `uv tool install git+https://github.com/oraios/serena.git` | `serena --help \| head -1` | `codex`, `claude`, `gemini`, `opencode` where configured |

## Canonical Rules

- `cli` tools must not create IDE drift failures.
- `mcp` tools must pass both:
  - manifest/render/file-level checks
  - real client CLI visibility checks
- Google surfaces:
  - `antigravity`
  - `gemini-cli`
  require separate config files with converged `context-plus` launcher entries.

## Current Status (V2.2)

All four tools are enabled and pass Layer 1-3 checks:
- `cass-memory`: CLI-native episodic memory
- `llm-tldr`: MCP static analysis context slicing
- `context-plus`: MCP structural context analysis
- `serena`: MCP AI assistant memory

**Layer 4 Client Visibility (observed 2026-03-10):**
- Claude Code: All MCP tools connected ✓
- Gemini CLI: All MCP tools connected ✓ (via `~/.gemini/settings.json`)
- Codex CLI: All MCP tools listed and enabled ✓ (via `~/.codex/config.toml` `mcp_servers`)
- OpenCode: All MCP tools connected ✓ (via `~/.config/opencode/opencode.jsonc` `mcp`)

Layer 4 visibility is necessary but not sufficient.

## Layer 5: Agent Adoption

A tool is not considered healthy in practice unless agents are instructed to use it for the right task class.

Required Layer 5 checks:
- generated AGENTS baseline contains the MCP Tool-First Routing Contract
- relevant skill docs contain Required Trigger Contract sections
- repo-level addenda contain at least repo-specific examples where needed
- handoffs/prompts can report tool use or a routing exception

Current state: Layer 4 GO does not imply Layer 5 GO.

## Known Caveats

- `cass-memory` is CLI-native and should NOT appear in IDE MCP configs. If manually added, it will show as "Failed to connect" in `claude mcp list`.
- `serena` PyPI has package collision with an unrelated AMQP client - must install from GitHub.
- `context-plus` uses a patched local build at `~/.local/share/contextplus-patched/build/index.js`.
- `context-plus` uses a split contract. In Codex, render a single visible
  workspace-local alias named `context-plus` to reduce MCP-list ambiguity.
  In other IDEs, deploy repo-scoped `context-plus-*` MCP entries (one per
  canonical repo), each launched with an explicit path argument per the
  upstream README contract: `contextplus [path]` starts the MCP server for
  the specified path.
- `gemini-cli` + `antigravity` use wrapped launcher form with the repo path
  inside the exec string.
- `CONTEXTPLUS_ROOT` env var is an escape-hatch; the primary fleet contract
  is explicit path args per entry. V1 caches are auto-migrated to V2 on first load.
