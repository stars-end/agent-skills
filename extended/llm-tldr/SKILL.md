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
the project tree via runtime path translation. This prevents artifact leakage into repos,
worktrees, and nested subdirectories.

### How It Works

- **MCP server**: Fleet Sync renders `tldr-mcp-contained-launch.py` instead of `tldr-mcp`
  directly. The contained wrapper patches llm-tldr path joins at process startup
  and patches MCP daemon startup so contained behavior is inherited by daemon forks.
- **CLI invocations**: `tldr-contained.sh` launches a contained Python entrypoint
  that patches llm-tldr before invoking `tldr.cli.main`.
- **State location**: `$TLDR_STATE_HOME/<project-hash>/` (default: `~/.cache/tldr-state/`)
- **Project hash**: MD5 of the resolved project path used by the command.

### Runtime State Mapping

| Artifact | In-Repo | External State |
|----------|---------|----------------|
| `.tldr/` | Absent | `$TLDR_STATE_HOME/<hash>/.tldr/` |
| `.tldrignore` | Absent | `$TLDR_STATE_HOME/<hash>/.tldrignore` |

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
      "command": "/home/<user>/agent-skills/scripts/tldr-mcp-contained-launch.py",
      "args": []
    }
  }
}
```

Fleet Sync expands the launcher path to an absolute host-local path before
writing client configs so direct stdio clients do not depend on shell `~`
expansion.

## Operational Guidance

### Warm / Index Lifecycle

`tldr warm` pre-builds structural call graph caches.
Contained semantic search auto-bootstraps a FAISS index on first use when missing.

Use the contained wrapper for both:

```bash
~/agent-skills/scripts/tldr-contained.sh warm ~/agent-skills
~/agent-skills/scripts/tldr-contained.sh warm /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-contained.sh semantic index /tmp/agents/<beads-id>/<repo> --model all-MiniLM-L6-v2
```

The daemon auto-reindexes structural caches after file changes. The contained
wrapper now auto-builds a missing semantic index on first semantic search for
the target project path. Explicit `semantic index` remains useful when you want
to prewarm for lower-latency first queries or pick a specific model.
The contained wrapper ensures no
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

### Codex MCP Hydration Fallback (Daemon-Backed)

If Codex desktop exposes no `llm-tldr` MCP tool in the active thread, use the
stable local Codex wrapper instead of plain `python -m tldr.cli`:

```bash
~/agent-skills/scripts/tldr-codex.sh context \
  --repo /tmp/agents/<beads-id>/<repo> \
  --entry <symbol> \
  --depth 2

~/agent-skills/scripts/tldr-codex.sh semantic \
  --repo /tmp/agents/<beads-id>/<repo> \
  --query "where is tool routing implemented?" \
  --k 5

~/agent-skills/scripts/tldr-codex.sh tree --repo /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-codex.sh structure --repo /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-codex.sh diagnostics --path /tmp/agents/<beads-id>/<repo>/path/to/file.py
~/agent-skills/scripts/tldr-codex.sh --help
```

`tldr-codex.sh` is only a thin stable entrypoint. It prints one explicit
fallback notice, then delegates to `tldr-daemon-fallback.sh`, which calls
`tldr.mcp_server` tool functions directly after contained runtime patching so
queries stay on the daemon/socket path (`_send_command`) instead of the plain
CLI direct API path.

Current command surface mirrors the practical MCP tools:
`tree`, `structure`, `search`, `extract`, `context`, `cfg`, `dfg`, `slice`,
`impact`, `dead`, `arch`, `calls`, `imports`, `importers`, `semantic`,
`diagnostics`, `change-impact` (alias `change_impact`), and `status`.

### MCP Failure Observability

When MCP daemon transport returns invalid/empty JSON (for example parser-style
errors such as `Expecting value: line 1 column 1 (char 0)`), the contained
runtime now enriches the surfaced error with bounded diagnostics:
- project path + command summary
- daemon ping/socket/lock status
- best-effort raw daemon response probe (`bytes_received`, preview, JSON parse status)

This keeps failures explicit and actionable without changing upstream llm-tldr.

### Context Response Safety

The contained runtime now sanitizes daemon responses before socket transport.
This matters most for `context`, where upstream daemon results can include rich
objects that are not JSON-serializable by default.

Expected steady-state behavior:
- `context` over MCP should return a normal text context payload
- daemon/socket transport should not fail with empty-payload EOF just because a
  response object was not JSON-safe

### Context Recovery Steps

If `context` fails but other surfaces such as `search` still work, use this
order:

1. Probe the same entrypoint through the contained CLI:

```bash
~/agent-skills/scripts/tldr-contained.sh context <entry> --project <project> --depth 2
```

2. If the CLI works but MCP reports enriched diagnostics such as:
   - `raw_probe.bytes_received=0`
   - `probe_status=eof`
   restart the per-project `llm-tldr` daemon and retry the MCP call.

3. Restart Codex / the client only if the MCP transport itself is stale
   (for example `Transport closed` after the daemon restart).

Interpretation:
- CLI pass + MCP fail usually means runtime/MCP transport or daemon lifecycle
  state, not a repo-content problem
- `search` pass + `context` fail usually means the issue is isolated to the
  `context` response path, not a full `llm-tldr` outage

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
| `semantic` | Semantic code search by meaning (FAISS + bge-large) | No (contained auto-bootstrap) |
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

- Fleet contract: MCP-rendered tool (contained via `tldr-mcp-contained-launch.py`)
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
5. **Auto-bootstrap semantic**: contained semantic search builds missing semantic index on first use
6. **State-contained**: No `.tldr/` or `.tldrignore` in repo/worktree trees
7. **Fallback path**: Keep fallback to normal repo-local context gathering

Containment is enforced by the canonical done gate: `scripts/dx-verify-clean.sh`
fails if `.tldr/` or `.tldrignore` appear under any canonical repo.

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
Expected: no output.

### Nested Invocation Proof
```bash
cd <nested-dir>
~/agent-skills/scripts/tldr-contained.sh warm .
cd -
find . -name .tldr -o -name .tldrignore
```
Expected: no output.

### Operational Proof (V8.6)
```bash
~/agent-skills/scripts/tldr-contained.sh warm .
~/agent-skills/scripts/tldr-contained.sh semantic index . --model all-MiniLM-L6-v2
~/agent-skills/scripts/tldr-contained.sh semantic search "routing contract" --path . --k 2 --model all-MiniLM-L6-v2
~/agent-skills/scripts/tldr-contained.sh structure . --lang python
~/agent-skills/scripts/tldr-contained.sh context <real-symbol> --project .
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
