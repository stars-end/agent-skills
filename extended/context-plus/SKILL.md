---
name: context-plus
description: |
  MCP-native structural context analysis (experimental/optional as of V8.6).
  Available for opt-in use only; not part of the canonical routing contract.
tags:
  - mcp
  - context
  - structure
  - fleet-sync
  - local-first
  - experimental
  - optional
---

# Context+ (Fleet Sync V2.3 — Experimental)

MCP-native structural context analysis. Available for opt-in use only.

## Tool Class

**`integration_mode: mcp`** (retained for backward compatibility)

Context+ is rendered to IDE MCP configs but is no longer the canonical default for any routing lane.

## Routing Status

**Experimental / optional** as of V8.6 routing contract.

Context+ has been demoted from the canonical routing contract because of structural limitations:
- **Worktree blindness**: `ROOT_DIR` is set once at server startup. Agents working in worktrees get stale results from the untouched canonical clone.
- **Single-root binding**: Each MCP instance is bound to exactly one repo. No dynamic root selection.
- **Cross-repo overhead**: Requires O(n) per-repo MCP entries for n repos, each with per-IDE overrides.
- **Unused capabilities**: Spectral clustering, memory graph, and feature hub navigation have near-zero observed agent usage.

llm-tldr is now the canonical default for both semantic discovery and exact static analysis.

## Current Fleet Status

- Fleet contract: MCP-rendered tool (retained for backward compatibility)
- Current state: ENABLED (opt-in)
- Install: `~/agent-skills/scripts/install-contextplus-patched.sh`

## Installation

```bash
~/agent-skills/scripts/install-contextplus-patched.sh
```

## Health Commands

```bash
test -f ~/.local/share/contextplus-patched/build/index.js && echo "OK"
```

## MCP Configuration

Rendered to IDE configs via Fleet Sync (per-repo scoped entries):

```json
{
  "mcpServers": {
    "context-plus-agent-skills": {
      "type": "stdio",
      "command": "node",
      "args": ["~/.local/share/contextplus-patched/build/index.js", "~/agent-skills"]
    }
  }
}
```

## Required Trigger Contract

**V8.6 routing contract does NOT route any task class to context-plus by default.**

Use context-plus only when:
- explicitly requested by the operator for a specific capability (spectral clustering, memory graph)
- llm-tldr is unavailable and the task requires embedding-based semantic search
- a documented opt-in scenario applies

Do NOT use context-plus as the first tool for:
- semantic repo discovery (use llm-tldr)
- exact static analysis (use llm-tldr)
- symbol-aware edits (use serena)

If context-plus is used on a qualifying task instead of the canonical tool, the response must include `Tool routing exception: context-plus opt-in for <reason>`.

## Key Functions (retained for reference)

- **Semantic Code Search**: Find code by meaning via embeddings
- **Spectral Clustering**: Group semantically related files
- **Memory Graph**: Cross-session concept recall with decay-scored edges
- **Feature Hub**: Obsidian-style wikilink navigation

## Unique Capabilities vs llm-tldr

| Capability | context-plus | llm-tldr | Notes |
|-----------|-------------|----------|-------|
| Semantic search (by meaning) | Via embeddings | Via FAISS + bge-large | Both work |
| Spectral clustering | Yes | No | Near-zero usage |
| Memory graph with decay | Yes (6 tools) | No | Overlaps with serena memory |
| Feature hub / wikilinks | Yes | No | Near-zero usage |
| Worktree support | Broken (single root) | Works (project per call) | Structural gap |
| CFG/DFG/slice | No | Yes | llm-tldr unique |
| Dead code detection | No | Yes | llm-tldr unique |
| Context from entry point | No | Yes (95% savings) | llm-tldr unique |

## Status

- Default stack status: NOT CANONICAL (experimental/optional)
- Fleet status: enabled for backward compatibility
- Use only when explicitly opted in
- Do not require this tool in standard repo workflows

## Upstream

- **Repo**: https://github.com/ForLoopCodes/contextplus
- **Docs**: https://github.com/ForLoopCodes/contextplus#readme

## Contract

1. **Local-first**: Execute locally via stdio MCP
2. **No central gateway**: Never a mandatory central gateway dependency
3. **Repository-local**: Prefer repository-local indexes and embeddings
4. **Opt-in only**: Not the canonical routing default (V8.6)
5. **Fail open**: Fail open to llm-tldr or normal local navigation if unavailable

## Runtime Requirements

- Node.js 20+ (or Bun)
- OpenRouter API key (for embeddings)

## Fleet Sync Integration

```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="context-plus")'
```

## IDE Targets

Rendered to these IDE configs (per-repo scoped entries):
- `codex-cli`: `~/.codex/config.toml`
- `claude-code`: `~/.claude.json`
- `antigravity`: `~/.gemini/antigravity/mcp_config.json`
- `opencode`: `~/.config/opencode/opencode.jsonc`
- `gemini-cli`: `~/.gemini/settings.json`

## Validation

### Layer 1 (Host Runtime)
```bash
test -f ~/.local/share/contextplus-patched/build/index.js && echo "OK"
```

### Layer 2 (Config Convergence)
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json
```

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `llm-tldr`: Canonical default for semantic + structural analysis (V8.6)
- `serena`: Symbol-aware edits and persistent memory
- `cass-memory`: Pilot-only CLI memory
