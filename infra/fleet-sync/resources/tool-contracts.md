# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Routing (V8.6) |
|------|-------|-------------------|------------------|-----------------|
| `cass-memory` | `cli` | `npm install -g Dicklesworthstone/cass_memory_system` | `cm --version`, `cm quickstart --json` | N/A (disabled) |
| `llm-tldr` | `mcp` | `uv tool install "llm-tldr==1.5.2"` | `tldr-mcp --version \|\| llm-tldr --version` | **Canonical default** (semantic + structural) |
| `context-plus` | `mcp` | `scripts/install-contextplus-patched.sh` | `test -f ~/.local/share/contextplus-patched/build/index.js` | Experimental/optional |
| `serena` | `mcp` | `uv tool install git+https://github.com/oraios/serena.git` | `serena --help \| head -1` | Canonical default (edits + memory) |

## Canonical Rules

- `cli` tools must not create IDE drift failures.
- `mcp` tools must pass both:
  - manifest/render/file-level checks
  - real client CLI visibility checks
- Google surfaces:
  - `antigravity`
  - `gemini-cli`
  require separate config files with converged MCP launcher entries.

## Routing Contract (V8.6)

| Task Shape | Canonical First Tool | Reason |
|------------|---------------------|--------|
| Semantic discovery ("where does X live?") | `llm-tldr` | FAISS + bge-large semantic search |
| Exact structural analysis (CFG/DFG/slice/impact) | `llm-tldr` | Precise static analysis |
| Context from entry point | `llm-tldr` | 95% token savings |
| Test targeting for changed files | `llm-tldr` | change_impact tool |
| Symbol-aware edits / rename / refactor | `serena` | LSP-backed surgical editing |
| Persistent project memory / session continuity | `serena` | File-based memory |

`context-plus` is NOT the default for any task class. Use only for explicit opt-in scenarios (spectral clustering, memory graph).

## Current Status (V2.3)

| Tool | Layer 1-3 | Layer 4 | Layer 5 | Notes |
|------|-----------|---------|---------|-------|
| `cass-memory` | Disabled | N/A | N/A | Pilot-only |
| `llm-tldr` | Pass | Pass | Active (V8.6) | Canonical default for semantic + structural |
| `context-plus` | Pass | Pass | Experimental (V8.6) | Opt-in only; worktree blindness |
| `serena` | Pass | Pass | Active | Canonical default for edits + memory |

**Layer 4 Client Visibility (observed 2026-03-10):**
- Claude Code: All MCP tools connected
- Gemini CLI: All MCP tools connected (via `~/.gemini/settings.json`)
- Codex CLI: All MCP tools listed and enabled (via `~/.codex/config.toml` `mcp_servers`)
- OpenCode: All MCP tools connected (via `~/.config/opencode/opencode.jsonc` `mcp`)

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
- `context-plus` is deployed as repo-scoped MCP entries (one per canonical repo),
  each launched with an explicit path argument per the upstream README contract:
  `contextplus [path]` starts the MCP server for the specified path.
  The `context-plus` base entry (cli mode) is for install/health tracking only.
- `context-plus` is experimental/optional as of V8.6. Not the canonical routing default.
  Structural limitations: worktree blindness (single-root binding), O(n) config surface.
- `gemini-cli` + `antigravity` use wrapped launcher form with the repo path
  inside the exec string.
- `CONTEXTPLUS_ROOT` env var is an escape-hatch; the primary fleet contract
  is explicit path args per entry. V1 caches are auto-migrated to V2 on first load.
- `llm-tldr` semantic search requires `tldr warm <project>` before first use.
  Every MCP tool call accepts a `project` parameter for worktree-safe operation.
