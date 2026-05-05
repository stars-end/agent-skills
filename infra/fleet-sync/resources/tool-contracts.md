# Fleet Sync Tool Contracts

This file is the compact operator reference for the intended Fleet Sync stack.

## Tool Classes

| Tool | Class | Canonical Install | Canonical Health | Routing (V8.6) |
|------|-------|-------------------|------------------|-----------------|
| `cass-memory` | `cli` | `npm install -g Dicklesworthstone/cass_memory_system` | `cm --version`, `cm quickstart --json` | N/A (disabled) |
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
| Symbol-aware edits / rename / refactor | `serena` | LSP-backed surgical editing |
| Persistent project memory / session continuity | `serena` | File-based memory |

## Current Status (V2.3)

| Tool | Layer 1-3 | Layer 4 | Layer 5 | Notes |
|------|-----------|---------|---------|-------|
| `cass-memory` | Disabled | N/A | N/A | Pilot-only |
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
- Fleet Sync expands `~` launcher paths to absolute host-local paths before
  writing client configs so direct stdio clients do not depend on shell
  expansion.
- Semantic search is an optional warmed hint lane, not a required MCP routing
  surface. Agents should call `scripts/semantic-search status` first and only
  query when status is `ready`.
- Query paths must not trigger indexing. If the semantic index is `missing`,
  `indexing`, or `stale`, use `rg` and direct reads.
- Legacy `.tldr` and `.tldrignore` paths must not be created under
  repo/worktree trees. This is enforced by `scripts/dx-verify-clean.sh`, which
  fails on leaked artifacts in canonical repos.

## Removed Tools

- `context-plus` was fully removed in bd-rb0c.8 (2026-03-29). It was replaced by
  `extended/context-plus/SKILL.md` for historical reference.
