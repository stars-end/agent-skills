# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Routing (V8.6) |
|------|-------|-------------------|------------------|-----------------|
| `cass-memory` | `cli` | `npm install -g Dicklesworthstone/cass_memory_system` | `cm --version`, `cm quickstart --json` | N/A (disabled) |
| `llm-tldr` | `mcp` | `uv tool install "llm-tldr==1.5.2"` | `tldr-mcp --version \|\| llm-tldr --version` | **Canonical default** (semantic + structural) |
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

## Current Status (V2.3)

| Tool | Layer 1-3 | Layer 4 | Layer 5 | Notes |
|------|-----------|---------|---------|-------|
| `cass-memory` | Disabled | N/A | N/A | Pilot-only |
| `llm-tldr` | Pass | Pass | Active (V8.6) | Canonical default for semantic + structural |
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
- `gemini-cli` + `antigravity` use wrapped launcher form with the repo path
  inside the exec string.
- `llm-tldr` contained semantic search auto-bootstraps a missing semantic index
  on first use for the target project path.
  `tldr warm <project>` only warms structural caches.
  Every MCP tool call accepts a `project` parameter for worktree-safe operation.
  **State containment (af-aqb.1):** llm-tldr runtime state (`.tldr/`, `.tldrignore`)
  is resolved outside the project tree by contained runtime patching in
  `tldr-mcp-contained.sh` (MCP) and `tldr-contained.sh` (CLI). State lives in
  `$TLDR_STATE_HOME/<project-hash>/` (default: `~/.cache/tldr-state/`). No
  `.tldr`/`.tldrignore` paths are created under repo/worktree trees. This is
  enforced by `scripts/dx-verify-clean.sh`, which fails on leaked artifacts in
  canonical repos.

## Removed Tools

- `context-plus` was fully removed in bd-rb0c.8 (2026-03-29). It was replaced by
  `llm-tldr` for semantic discovery and `serena` for symbol-aware edits. See
  `extended/context-plus/SKILL.md` for historical reference.
