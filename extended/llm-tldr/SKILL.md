---
name: llm-tldr
description: |
  MCP-native semantic discovery and static analysis for precise, low-token task context extraction.
  Canonical default for both semantic code search and exact structural analysis (V8.6).
tags:
  - mcp
  - static-analysis
  - semantic
  - context
  - fleet-sync
  - local-first
  - canonical-default
---

# llm-tldr (Fleet Sync V2.3)

MCP-native semantic discovery and static analysis for surgical context extraction and reduced token overhead.

## Tool Class

**`integration_mode: mcp`**

llm-tldr is rendered to IDE MCP configs and provides MCP server functionality.

## Routing Status

**Canonical default** for semantic discovery and exact static analysis (V8.6 routing contract).

## Installation

```bash
uv tool install "llm-tldr==1.5.2"
```

## Health Commands

```bash
tldr-mcp --version || llm-tldr --version
```

## State Containment (af-aqb.1)

All llm-tldr runtime state (`.tldr/` and `.tldrignore`) is redirected outside
the project tree via symlinks. This prevents artifact leakage into repos,
worktrees, and nested subdirectories.

### How It Works

- **MCP server**: Fleet Sync renders `tldr-mcp-contained.sh` instead of `tldr-mcp`
  directly. The contained wrapper patches the daemon at startup to create symlinks
  before any state is written.
- **CLI invocations**: Use `tldr-contained.sh` to pre-create symlinks before
  `llm-tldr` writes state.
- **State location**: `$TLDR_STATE_HOME/<project-hash>/` (default: `~/.cache/tldr-state/`)
- **Project hash**: MD5 of the resolved project path. Same repo = same state, even
  across worktrees with different absolute paths.

### What Gets Symlinked

| Artifact | In-Repo | External State |
|----------|---------|----------------|
| `.tldr/` | Symlink | `$TLDR_STATE_HOME/<hash>/.tldr/` |
| `.tldrignore` | Symlink | `$TLDR_STATE_HOME/<hash>/.tldrignore` |

### Fallback: Existing `.tldr` Directory

If a real `.tldr` directory already exists (from pre-containment usage), the
wrapper migrates it to the external state location and replaces it with a symlink.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TLDR_STATE_HOME` | `~/.cache/tldr-state/` | External state root |
| `TLDR_AUTO_DOWNLOAD` | unset | Skip model download prompts |

## MCP Configuration

Rendered to IDE configs via Fleet Sync (contained):

```json
{
  "mcpServers": {
    "llm-tldr": {
      "type": "stdio",
      "command": "bash",
      "args": ["-lc", "exec ~/agent-skills/scripts/tldr-mcp-contained.sh"]
    }
  }
}
```

## Operational Guidance

### Warm / Index Lifecycle

llm-tldr's `semantic` tool requires a one-time `tldr warm` to build the FAISS
index. Use the contained wrapper for warm operations:

```bash
~/agent-skills/scripts/tldr-contained.sh warm ~/agent-skills
~/agent-skills/scripts/tldr-contained.sh warm /tmp/agents/<beads-id>/<repo>
```

The daemon auto-reindexes after 20 file changes, but the initial warm is
required for semantic search to function. The contained wrapper ensures no
`.tldr/` or `.tldrignore` files are created inside the project tree, even when
running `warm` from nested subdirectories.

### Worktree-Safe Project Usage

llm-tldr accepts a `project` parameter on every MCP tool call:

```bash
semantic(project="/tmp/agents/bd-xxx/agent-skills", query="...")
context(project="/tmp/agents/bd-xxx/agent-skills", entry="main", depth=2)
```

The contained MCP server ensures the daemon's state is always redirected to
`$TLDR_STATE_HOME`, regardless of which project path is passed.

### Per-Call Project Parameter

Every MCP tool accepts `project` (default `"."`):
- In Claude Code worktrees, CWD is the worktree path and `project="."` works.
- For multi-repo work, pass the explicit project path in each tool call.
- The fleet MCP config launches the contained wrapper with no `--project` flag,
  letting each call specify the target.

## Required Trigger Contract

Use `llm-tldr` first for ALL of the following:

**Semantic discovery (V8.6):**
- locating the part of the repo responsible for a concept or feature
- mapping related files/modules before editing
- answering "where does X live?" or "what code is related to X?"
- natural language code search by meaning

**Exact static analysis:**
- call graph or reverse-call impact
- CFG/DFG/program slice
- dead code or architecture layer analysis
- "trace the exact code path that leads here"

**Context and test targeting (V8.6):**
- "understand this function and its dependencies" -> `context` tool (95% token savings)
- "what tests need to run" -> `change_impact` tool

Do not skip directly to repeated `read_file` traversal for these questions unless
a documented fallback condition applies.

### Key Functions

| Function | Purpose | Requires Warm? |
|----------|---------|----------------|
| `semantic` | Semantic code search by meaning (FAISS + bge-large) | Yes |
| `context` | Token-efficient context from entry point (95% savings) | No |
| `structure` | Code structure / codemaps | No |
| `calls` | Cross-file call graph | No |
| `cfg` | Control flow graph | No |
| `dfg` | Data flow graph | No |
| `slice` | Program slice (backward/forward) | No |
| `dead` | Find unreachable code | No |
| `arch` | Architectural layer detection | No |
| `change_impact` | Test targeting for changed files | No |
| `diagnostics` | Type check + lint | No |
| `impact` | Reverse-call impact analysis | No |
| `search` | Regex search across codebase | No |

### Capabilities Previously Under-Routed

The investigation cycle (bd-rb0c.3) identified that at least 6 of 16 MCP tools were effectively unused. V8.6 closes this gap:

- `semantic`: Now the canonical semantic lane.
- `context`: Was never routed. Biggest missed opportunity (95% token savings).
- `change_impact`: Was never routed. Now surfaced for test targeting.
- `dead`: Was never routed. Now surfaced for refactoring.
- `arch`: Was never routed. Now surfaced for architectural analysis.
- `diagnostics`: Was never routed. Now surfaced for type/lint checks.

## Status

- Fleet contract: MCP-rendered tool (contained via `tldr-mcp-contained.sh`)
- Canonical install: `uv tool install "llm-tldr==1.5.2"`
- Canonical health checks:
  - `tldr-mcp --version || llm-tldr --version`
  - client MCP visibility checks such as `claude mcp list`, `codex mcp list`, `gemini mcp list`, `opencode mcp list`

## Upstream Docs

- **Repo**: https://github.com/parcadei/llm-tldr
- **Docs**: https://github.com/parcadei/llm-tldr#readme
- **PyPI**: `https://pypi.org/project/llm-tldr/`

## Contract

1. **Local-first**: Run on local machine via stdio
2. **Token efficient**: 95% token savings vs reading raw files
3. **Worktree-safe**: `project` parameter per call, no single-root lock-in
4. **Per-project daemons**: Daemon per resolved path, no central index requirement
5. **Warm-gated semantic**: `tldr warm` required before first `semantic` call
6. **State-contained**: No `.tldr/` or `.tldrignore` in repo/worktree trees
7. **Fallback path**: Keep fallback to normal repo-local context gathering

## Runtime Requirements

- Python 3.12+
- tree-sitter dependencies
- FAISS dependencies (for semantic search)

## Fleet Sync Integration

```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="llm-tldr")'
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json
```

## IDE Targets

Rendered to these IDE configs:
- `codex-cli`: `~/.codex/config.toml`
- `claude-code`: `~/.claude.json`
- `opencode`: `~/.config/opencode/opencode.jsonc`
- `gemini-cli`: `~/.gemini/settings.json`
- `antigravity`: `~/.gemini/antigravity/mcp_config.json`

## Validation

### Layer 1 (Host Runtime)
```bash
tldr-mcp --version || llm-tldr --version
```

### Layer 2 (Config Convergence)
```bash
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json
```

### Artifact Leak Proof
```bash
find . -name .tldr -o -name .tldrignore
~/agent-skills/scripts/tldr-contained.sh warm .
find . -name .tldr -o -name .tldrignore
```
Expected: only symlinks, no real files under the project tree.

### Nested Invocation Proof
```bash
cd <nested-dir>
~/agent-skills/scripts/tldr-contained.sh warm .
cd -
find . -name .tldr -o -name .tldrignore
```
Expected: only symlinks, no real files anywhere under the project tree.

### Operational Proof (V8.6)
```bash
~/agent-skills/scripts/tldr-contained.sh warm .
tldr semantic "routing contract" .
tldr structure . --lang python
tldr context <real-symbol> --project .
```

### Layer 4 (Client Visibility)
```bash
codex mcp list    # Should show llm-tldr
claude mcp list   # Should show llm-tldr
gemini mcp list   # Should show llm-tldr
opencode mcp list # Should show llm-tldr
```

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `serena`: Symbol-aware edits and persistent memory (canonical default)
- `cass-memory`: Pilot-only CLI memory
