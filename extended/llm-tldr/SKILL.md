---
name: llm-tldr
description: |
  Canonical analysis tool for semantic discovery and exact static analysis with low-token context extraction.
  Prefer the MCP surface when available; otherwise use the canonical local fallback.
tags:
  - mcp
  - static-analysis
  - semantic
  - context
  - fleet-sync
  - local-contained
  - fleet-sync
  - canonical-default
---

# llm-tldr (Fleet Sync V2.3)

Canonical analysis tool for semantic discovery and exact static analysis with reduced token overhead.

## Tool Class

**`integration_mode: local-contained MCP`**

llm-tldr is exposed through a host-local contained MCP server. Agents should
treat this as one analysis tool; the MCP process must run on a host that can
read the target project path.

## Routing Status

Default for structural/context/static-analysis operations. Semantic first-hop
discovery is no longer required; use `scripts/semantic-search` as optional
warmed hints when available.

### Agent-Facing Routing Rule

Use `llm-tldr` for analysis, structural trace, context, and exact static
analysis.

- Preferred surface: local contained MCP when the `llm-tldr` tool is visible in the active runtime
- Canonical fallback: the contained local helper when MCP is unavailable in the current runtime
- Do not manually choose between MCP, daemon, or plain CLI paths
- Do not substitute a different analysis stack unless `llm-tldr` is unavailable or fails after one reasonable attempt

### Timeout Contract (Both Layers)

`llm-tldr` routing has two timeout layers and both must be bounded:

1. MCP path timeout:
   - bounded by client/runtime policy (Codex/Claude/OpenCode/Gemini tool-call timeout)
   - this is not configured inside `tldr-daemon-fallback.sh`
2. CLI fallback timeout:
   - callers must wrap `tldr-daemon-fallback.sh` with GNU `timeout`
   - semantic fallback fails fast with `reason_code=semantic_index_missing`
     when its FAISS index is cold, instead of auto-building inside the bounded
     agent command
   - on timeout or `semantic_index_missing`, return a clear reason and fall
     back to targeted `rg` or direct source reads for the current turn

Example bounded fallback:

```bash
timeout 25 ~/agent-skills/scripts/tldr-daemon-fallback.sh semantic --repo /tmp/agents/<beads-id>/<repo> --query "where is auth bootstrapped?"
```

If that returns `semantic_index_missing`, prewarm explicitly when semantic
search is still worth the cold-start cost:

```bash
~/agent-skills/scripts/tldr-contained.sh semantic index /tmp/agents/<beads-id>/<repo> --model all-MiniLM-L6-v2
```

## Beads Memory Synergy

Beads memory is discovery input, not source truth.

Use memory first for cross-VM, cross-repo, vendor/API, infra/auth/workflow, or
repeated-friction work:

```bash
bdx memories <keyword> --json
bdx search <keyword> --label memory --status all --json
bdx show <memory-id> --json
bdx comments <memory-id> --json
```

Then validate memory claims with `llm-tldr` before acting:

- use semantic discovery to confirm where behavior currently lives
- use context/static analysis to verify referenced symbols and paths
- use change-impact/impact tooling to evaluate `mem.stale_if_paths`

Required framing for agents: memory is a lead, not proof.

### Codex Desktop Hydration Check

Before escalating to fallback scripts, daemon debugging, or replacement-tool
research for a Codex desktop visibility problem, do this cheap check first:

1. Run `codex mcp list` and confirm `llm-tldr` is configured
2. Restart Codex desktop once so the client reloads MCP server state
3. Retry one real in-thread `llm-tldr` call
4. Only then use the canonical fallback or report `Tool routing exception: ...`

This separates:
- config visible but stale client state
- tool hydrated in-thread
- actual `llm-tldr` runtime failure

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

Fleet Sync renders a host-local contained stdio launcher:

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

### Path Locality

llm-tldr reads source files from the filesystem. The MCP server can only analyze
project paths that exist on the host where the MCP server process is running.
A Mac-local worktree such as `/tmp/agents/<beads-id>/<repo>` or
`/private/tmp/agents/<beads-id>/<repo>` is not readable from `epyc12` unless it
is mirrored or mounted there.

Routing rule:

1. For normal workspace-first development, run local contained MCP on the host
   that owns the worktree.
2. If the active runtime lacks local MCP, use the local contained fallback on
   that host:

```bash
~/agent-skills/scripts/tldr-daemon-fallback.sh tree --repo /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-daemon-fallback.sh semantic --repo /tmp/agents/<beads-id>/<repo> --query "where is setup handled?"
```

3. If compute must happen on `epyc12`, create or mirror the worktree on
   `epyc12` first and pass the `epyc12` path to that host's local MCP. Prefer
   Tailscale SSH for remote setup:

```bash
tailscale ssh fengning@epyc12 'dx-worktree create <beads-id> <repo>'
```

Do not send a host-local path to an MCP server running on another host. That is
a path-locality miss, not an MCP hydration failure.

## Operational Guidance

### Warm / Index Lifecycle

`tldr warm` pre-builds structural call graph caches.
Contained MCP and contained CLI semantic search may auto-bootstrap a FAISS index
on first use when missing. The daemon-backed fallback is different: it is an
agent recovery path and must not spend a bounded fallback call doing a cold
semantic model/index build.

Use the contained wrapper for both:

```bash
~/agent-skills/scripts/tldr-contained.sh warm ~/agent-skills
~/agent-skills/scripts/tldr-contained.sh warm /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-contained.sh semantic index /tmp/agents/<beads-id>/<repo> --model all-MiniLM-L6-v2
```

The daemon auto-reindexes structural caches after file changes. The contained
MCP/CLI wrapper may auto-build a missing semantic index on first semantic
search for the target project path. Explicit `semantic index` is the preferred
fresh-device/worktree prewarm path when an agent needs semantic search.
The contained wrapper ensures no
`.tldr/` or `.tldrignore` files are created inside the project tree, even when
running `warm` from nested subdirectories.

### Worktree-Safe Project Usage

llm-tldr accepts a `project` parameter on every MCP tool call. That path must
be readable from the host running the MCP server:

```bash
semantic(project="/tmp/agents/bd-xxx/agent-skills", query="...")
context(project="/tmp/agents/bd-xxx/agent-skills", entry="main", depth=2)
```

The contained MCP server ensures the daemon's state is always redirected to
`$TLDR_STATE_HOME`, regardless of which project path is passed.

### Codex MCP Hydration Fallback (Daemon-Backed)

If the active runtime exposes no `llm-tldr` MCP tool, use the local contained
daemon helper as the canonical fallback instead of plain `python -m tldr.cli`:

```bash
~/agent-skills/scripts/tldr-daemon-fallback.sh context \
  --repo /tmp/agents/<beads-id>/<repo> \
  --entry <symbol> \
  --depth 2

~/agent-skills/scripts/tldr-daemon-fallback.sh semantic \
  --repo /tmp/agents/<beads-id>/<repo> \
  --query "where is tool routing implemented?" \
  --k 5

~/agent-skills/scripts/tldr-daemon-fallback.sh tree --repo /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-daemon-fallback.sh structure --repo /tmp/agents/<beads-id>/<repo>
~/agent-skills/scripts/tldr-daemon-fallback.sh diagnostics --path /tmp/agents/<beads-id>/<repo>/path/to/file.py
~/agent-skills/scripts/tldr-daemon-fallback.sh --help
```

This helper calls `tldr.mcp_server` tool functions directly after contained
runtime patching, so queries stay on the daemon/socket path (`_send_command`)
instead of the plain CLI direct API path.

Semantic fallback has one extra guard: if the contained semantic index is
missing, it exits quickly with `reason_code=semantic_index_missing` and prints a
prewarm command. Do not retry the same fallback command in a loop. Either run
the explicit prewarm command or use targeted `rg` / direct source reads for this
turn. Operators can opt into the older cold-build behavior with
`TLDR_FALLBACK_SEMANTIC_AUTOBUILD=1`; agents should not use that override
inside ordinary tool routing.

### Semantic Prewarm Maintenance

Canonical DX now has two proactive prewarm paths:
- `worktree-setup.sh` starts a best-effort background prewarm for each
  `/tmp/agents/<beads-id>/<repo>` path and logs to
  `~/logs/dx/tldr-semantic-prewarm-worktree.log`.
- `dx-spoke-cron-install.sh` installs a 6-hour cron prewarm job for canonical
  repos and recent active worktrees (`--since-hours 48`) using
  `scripts/tldr-semantic-prewarm.sh`.

Manual run surface (same script used by cron/worktree hook):
```bash
~/agent-skills/scripts/tldr-semantic-prewarm.sh --canonical --active-worktrees --since-hours 48
~/agent-skills/scripts/tldr-semantic-prewarm.sh --path /tmp/agents/<beads-id>/<repo>
```

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

Use `llm-tldr` first for ALL of the following analysis tasks:

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
| `semantic` | Semantic code search by meaning (FAISS; use `all-MiniLM-L6-v2` for agent prewarm) | Fallback requires prewarmed index; MCP/CLI may auto-bootstrap |
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
5. **Semantic prewarm clarity**: contained MCP/CLI may build a missing semantic index, while daemon fallback fails fast on a cold semantic index and tells agents how to prewarm
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
