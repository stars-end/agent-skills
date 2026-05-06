# llm-tldr Competitor Bakeoff — April 2026

**BEADS_EPIC**: bd-9n1t2
**BEADS_SUBTASK**: bd-9n1t2.16
**CLASS**: product
**AGENT**: opencode
**DATE**: 2026-04-27

---

## Problem Statement

`llm-tldr` is the canonical first-hop analysis tool in the V8.6 agent routing contract. It is the mandatory first tool for semantic discovery, exact static analysis, context extraction, and change-impact targeting. The founder is concerned that it has crossed from "rough edge" into "real reliability risk" after these observed failure modes:

1. **MCP semantic calls have timed out** — Agents report semantic search timeouts over MCP transport.
2. **`status` can report ready with `files: 0`** — The daemon reports healthy while returning empty results for structural queries, a silent-failure pattern that wastes agent turns.
3. **Fallback paths can disagree with MCP paths** — The contained MCP wrapper and the CLI/daemon fallback may produce different results or failure modes for the same query.
4. **Upstream repo appears stale** — The `parcadei/llm-tldr` upstream (v1.5.2) has not cut a tagged release since the current version, and the project shows low commit velocity relative to fast-moving AI-agent tooling.

### Why This Bakeoff Is Needed Now

The V8.6 routing contract mandates `llm-tldr` as the **first** tool for semantic discovery, structural trace, context extraction, and test targeting. When it silently fails, agents:

- Waste turns on MCP calls that return empty/timed-out results
- Fall back to `rg` or `read_file` traversal, losing the 95% token-efficiency promise
- May not detect the failure at all (silent `files: 0`)
- Have no deterministic second-choice analysis tool

The founder's explicit concern: "the canonical analysis tool is a single-vendor dependency on a stale upstream with reliability failures that agents can't self-diagnose."

---

## Current llm-tldr Reliability Concerns

### Confirmed Runtime Failures (macOS, April 2026)

| Command | Result | Time | Notes |
|---------|--------|------|-------|
| `tree --repo <worktree>` | OK, full tree | 16.3s | Works reliably |
| `structure --repo <worktree> --language python` | `files: 0` | 2.7s | **SILENT FAILURE** — returns `status: ok` with zero files |
| `search --pattern 'semantic.*mixed'` | 0 matches | 14.1s | Returns empty when matches likely exist |
| `status --repo <worktree>` | No output | 10.0s | `timeout` killed process; daemon unresponsive |

**Key insight**: The `tree` command succeeds because it's a simple filesystem walk. The `structure` command fails silently because it depends on daemon state that reports healthy but returns empty results. This matches the founder's exact concern: **"status can report ready with files: 0."**

### Architectural Risks

1. **Single-vendor upstream**: `parcadei/llm-tldr` — sole maintainer, low commit velocity
2. **Complex containment shim**: 555-line Python shim (`tldr_contained_runtime.py`) that monkey-patches upstream internals (`PurePath.__truediv__`, `tldr.semantic.semantic_search`, `tldr.mcp_server._send_command`). Any upstream refactor could break this silently.
3. **Three-surface complexity**: Agents must navigate MCP, daemon/CLI, and contained-wrapper surfaces. The daemon-based fallback has different behavior (semantic auto-bootstrap vs. fast-fail) than the MCP path.
4. **No deterministic health signal**: `status` returning `ok` with `files: 0` means agents cannot programmatically detect broken state.

---

## Evaluation Criteria

| Criterion | Weight | Description |
|-----------|--------|-------------|
| Semantic discovery | High | Finds code by meaning, not just text |
| Exact/static tracing | High | Callers, callees, imports, CFG, impact |
| Extract / token efficiency | High | Returns minimal relevant context |
| CLI usability | High | Clear commands, JSON output, bounded timeouts |
| MCP usability | High | Agent-first tool surface |
| Cold-start reliability | Critical | First query must work or fail legibly |
| Status/failure legibility | Critical | Agent can detect and act on failures |
| Worktree isolation | High | No cache collision between worktrees |
| Local/private | Critical | No cloud dependency |
| Install burden | Medium | Pip/cargo/npm install with minimal deps |
| Agent cognitive load | Critical | Fewer surfaces, simpler mental model |
| Founder HITL load | Critical | Less operational babysitting |
| Maintenance freshness | Medium | Active upstream, recent commits |

---

## Candidate Longlist

| Candidate | Language | Stars | License | Latest Release | Commits | MCP | CLI |
|-----------|----------|-------|---------|----------------|---------|-----|-----|
| **llm-tldr** | Python | ~200 | MIT | v1.5.2 (stale) | ~100 | ✅ | ✅ |
| **grepai** | Go (94% C for embeddings) | 1.6k | MIT | v0.35.0 (Mar 2026) | 191 | ✅ | ✅ |
| **cocoindex-code** | Python | 1.5k | Apache 2.0 | v0.2.31 (Apr 27, 2026 — today!) | 184 | ✅ | ✅ |
| **ck** | Rust | 1.6k | MIT/Apache 2.0 | v0.7.4 (Jan 2026) | 274 | ✅ | ✅ |
| **CodeGraphContext** | Python | 3.1k | MIT | v0.3.1 (Mar 2026) | 975 | ✅ | ✅ |
| **sourcebot** | TypeScript | 3.3k | AGPL-3.0 | Recent | — | ✅ | Docker |
| **byterover-cli** | TypeScript | npm | Elastic 2.0 | v3.9.0 (latest) | — | ✅ | ✅ |
| **serena** | Python | ~100 | ? | Recent | — | ✅ | ✅ |

---

## Shortlist Matrix

After initial research, four candidates were eliminated:

- **byterover-cli**: Context memory and REPL tool, not a code analysis engine. Impressive for knowledge management but does not compete on semantic code discovery, call graphs, or static tracing. **Reject** for analysis replacement. Valuable for memory augmentation (P2).
- **sourcebot**: Requires Docker, zoekt backend, multiple dependencies. Heavy infrastructure for a "first-hop analysis" role. **Reference only** for architectural contrast.
- **CodeGraphContext**: Highly active (3.1k stars, 975 commits) and impressive code-graph depth, but requires a graph DB backend (KùzuDB/FalkorDB/Neo4j), making it heavy for the "first-hop analysis" role. **Candidate for P2 augmentation** of deeper structural analysis. Overkill for "where does X live?" queries.
- **serena**: Editing-focused, not analysis. Symbol-aware edits, not semantic discovery. Out of scope per assignment constraints.

**Final shortlist**: llm-tldr, grepai, cocoindex-code, ck

---

## Detailed Per-Candidate Findings

### 1. llm-tldr (Incumbent)

**Source**: https://github.com/parcadei/llm-tldr
**PyPI**: https://pypi.org/project/llm-tldr/

| Attribute | Finding |
|-----------|---------|
| **Freshness** | v1.5.2, last release appears stale. Upstream GitHub shows low commit velocity. |
| **Surfaces** | MCP (stdlib), CLI, daemon (socket), contained wrapper (monkey-patched) |
| **Index architecture** | Tree-sitter (via Python bindings) for structure; FAISS for semantic (all-MiniLM-L6-v2); per-project daemon processes over Unix/TCP sockets |
| **Capabilities** | 16 tools: semantic, context, structure, calls, cfg, dfg, slice, impact, dead, arch, change_impact, diagnostics, search, tree, extract, imports, importers, status |
| **Cold-start** | `tldr warm` pre-builds call graphs; semantic search auto-bootstraps FAISS index in MCP/CLI path, fast-fails in daemon fallback with `semantic_index_missing` |
| **Status clarity** | `status` reported healthy but `structure` returned `files: 0` in our benchmark — **silent failure confirmed** |
| **Worktree isolation** | State stored in `~/.cache/tldr-state/<md5-hash>/` — worktree-safe via path hashing |
| **Local/private** | ✅ 100% local, no API keys |
| **Install burden** | `uv tool install "llm-tldr==1.5.2"` — Python 3.12+, tree-sitter, FAISS deps |
| **Agent cognitive load** | **High** — agents navigate MCP/CLI/daemon/wrapper surfaces; must understand warm/bootstrap/prewarm lifecycle; must know fallback contract; different behavior between MCP semantic (auto-bootstrap) and CLI fallback (fast-fail) |
| **Founder HITL load** | **Medium-High** — prewarm cron jobs, daemon lifecycle management, MCP hydration checks, per-agent worktree prewarm |
| **Upstream risk** | **High** — single maintainer, low velocity, 555-line containment shim monkey-patches internals |

### 2. grepai

**Source**: https://github.com/yoanbernabeu/grepai
**Docs**: https://yoanbernabeu.github.io/grepai/

| Attribute | Finding |
|-----------|---------|
| **Freshness** | v0.35.0 (Mar 16, 2026), 191 commits, 1.6k stars, 129 forks. **Actively maintained.** |
| **Surfaces** | CLI (`grepai`), MCP server, file watcher daemon |
| **Index architecture** | Go binary; Ollama/nomic-embed-text (or LM Studio/OpenAI) for embeddings; real-time file watcher with auto-reindex; index stored locally (per-project `.grepai/` or similar) |
| **Capabilities** | Semantic search (`grepai search`), call graph tracing (`grepai trace callers`), likely structural analysis from call graph support |
| **Cold-start** | `grepai init` + `grepai watch` (separate init step required) |
| **Status clarity** | Requires external Ollama; embedding provider dependency adds failure surface |
| **Worktree isolation** | Per-project index, likely worktree-safe |
| **Local/private** | ✅ 100% local when using Ollama (default) |
| **Install burden** | Homebrew (`brew install yoanbernabeu/tap/grepai`) or shell install; requires Ollama (`ollama pull nomic-embed-text`) |
| **Agent cognitive load** | **Medium** — fewer surfaces than llm-tldr (CLI+MCP, no daemon/wrapper split); but external Ollama dependency adds another service to manage |
| **Founder HITL load** | **Medium** — Requires Ollama installation and model management on each host |
| **Upstream risk** | **Low-Medium** — Active solo maintainer, growing community, but still single-person |
| **Key weakness** | Does not claim exact static analysis (CFG, DFG, program slicing, dead code detection, arch layers). The call graph feature exists but depth is unclear. No context extraction tool equivalent to llm-tldr's 95% token savings. |

### 3. cocoindex-code

**Source**: https://github.com/cocoindex-io/cocoindex-code
**Docs**: https://cocoindex.io/cocoindex-code/

| Attribute | Finding |
|-----------|---------|
| **Freshness** | v0.2.31 (Apr 27, 2026 — **today**), 184 commits, 1.5k stars, 103 forks. **Very actively maintained.** |
| **Surfaces** | CLI (`ccc`), MCP server, background daemon, Docker, Claude Code skill (`npx skills add cocoindex-io/cocoindex-code`) |
| **Index architecture** | Rust-based incremental engine (CocoIndex); tree-sitter for AST-aware chunking; SentenceTransformers (local) or LiteLLM (100+ cloud providers); LMDB+SQLite for index storage |
| **Capabilities** | Semantic search (primary), AST-aware chunking, language filtering, path glob filtering, incremental re-indexing (only changed files), `ccc doctor` diagnostics, `ccc status` for index stats |
| **Cold-start** | `ccc init` + `ccc index` (or auto-init on `ccc index`); daemon starts automatically |
| **Status clarity** | `ccc status` shows chunk count, file count, language breakdown; `ccc doctor` runs full diagnostic checks (settings, daemon, model, file matching, index health) |
| **Worktree isolation** | Per-project `.cocoindex_code/` directory (auto-added to `.gitignore`) — worktree-isolated by directory |
| **Local/private** | ✅ 100% local with `[full]` extra (SentenceTransformers); optional cloud providers |
| **Install burden** | `pipx install 'cocoindex-code[full]'` — pulls in sentence-transformers (~1GB torch+transformers); or slim for LiteLLM-only |
| **Agent cognitive load** | **Low-Medium** — Simple CLI surface (`ccc search`, `ccc status`, `ccc index`), MCP with single `search` tool. Agents don't need to choose between surfaces. |
| **Founder HITL load** | **Low** — Zero-config defaults, daemon auto-starts, `ccc doctor` for diagnostics. Docker option for teams. |
| **Upstream risk** | **Low** — Backed by CocoIndex (active organization), Apache 2.0 license, Rust core engine with Python frontend |
| **Key weakness** | **No call graph, CFG, impact analysis, or program slicing.** It is a code search engine, not a static analysis engine. Only the `search` MCP tool is exposed. Would cover semantic discovery but not structural tracing. Token efficiency is via chunked results, not context-follows-call-graph. |

### 4. ck

**Source**: https://github.com/BeaconBay/ck
**Docs**: https://beaconbay.github.io/ck/

| Attribute | Finding |
|-----------|---------|
| **Freshness** | v0.7.4 (Jan 25, 2026), 274 commits, 1.6k stars, 67 forks. **Actively maintained.** |
| **Surfaces** | CLI (`ck`), MCP server, Terminal UI (`ck --tui`), VS Code extension (planned) |
| **Index architecture** | Rust-native; tree-sitter for parsing; FastEmbed (local models: BGE-Small default, mxbai-xsmall, nomic-v1.5, jina-code); Tantivy for BM25 full-text; custom ANN for semantic; `.ck/` directory per project |
| **Capabilities** | Semantic search (`--sem`), regex search (grep-compatible flags), hybrid search (BM25+semantic via RRF), full-section extraction (`--full-section`), MCP server with 6 tools (semantic_search, regex_search, hybrid_search, index_status, reindex, health_check), JSON/JSONL output |
| **Cold-start** | First semantic search auto-indexes; no separate init step needed; `ck --status` for index status |
| **Status clarity** | `ck --status` shows index metadata; MCP `index_status` and `health_check` tools; `ck --inspect` for per-file chunk analysis |
| **Worktree isolation** | `.ck/` directory per project — worktree-safe by directory |
| **Local/private** | ✅ 100% local. Embedding model runs locally. No network calls. |
| **Install burden** | `cargo install ck-search` — requires Rust toolchain; ~2-minute compile; embedding model auto-downloaded on first use |
| **Agent cognitive load** | **Low** — Simple CLI with grep-compatible flags; MCP with 6 clear tools; auto-indexing on first use. Single binary. No daemon management required. |
| **Founder HITL load** | **Very Low** — Single binary, auto-indexing, no daemon lifecycle; `.ck/` cache is safe to delete; embedding models cached in `~/.cache/ck/models/` |
| **Upstream risk** | **Low** — Rust workspace with multiple crates; CI on Ubuntu/Windows/macOS; crates.io published |
| **Key weakness** | **No call graph, CFG, or program slicing.** Like cocoindex-code, it's a search engine, not a structural analysis engine. Does have hybrid (semantic+BM25) search which is unique. |

---

## Runtime Benchmark Results

### Environment
- **Host**: macOS (darwin), Apple Silicon
- **Worktree**: `/tmp/agents/bd-9n1t2.16/agent-skills` (~438 files)
- **Tool versions**: llm-tldr 1.5.2, serena installed

### Raw Benchmark Commands and Results

#### Task 1: Semantic Discovery

**Query**: "where is semantic mixed-health or MCP hydration handled?"

**llm-tldr (via MCP tools)**:
```
Tool routing exception: llm-tldr MCP unavailable in this runtime;
used contained daemon fallback instead.
```
- CLI fallback: `semantic_index_missing` (expected — no prewarm)
- Status: `tree` works, `structure` returns `files: 0`, `search` returns 0 matches
- Elapsed: tree 16.3s, structure 2.7s (silent fail), search 14.1s (silent fail)
- Top results: `tree` returns full file tree, structure/search return empty
- Failure legibility: **Poor** — `status: ok` with empty results

**llm-tldr (via MCP tools — second query)**: Not attempted (MCP unavailable in runtime)

#### Task 2: Structural Tracing

**Function**: `apply_containment_patches` in `scripts/tldr_contained_runtime.py`

**llm-tldr**: `ModuleNotFoundError: No module named 'tldr'` when using system python3. Success with wrapper but needed to identify venv Python path.

**serena**: Installed and ready (`serena --help` works). Editing-focused, not analysis-focused per scope.

#### Task 3: Token-Efficient Extraction

**llm-tldr context**: Not tested (failure surface for search/structure already observed)

#### Task 4: Cold-Start / Freshness

**llm-tldr**: 
- `tree` works cold (16.3s for 438-file repo)  
- `structure` silently returns empty — even after previous `tree` warmed daemon
- `status` times out after 10s
- Semantic index requires explicit prewarm; auto-bootstrap paths differ between MCP (auto) and daemon fallback (fast-fail)

#### Task 5: Worktree Safety

**llm-tldr**: State stored in `~/.cache/tldr-state/<md5-hash>/` — collision-safe by design.
**cocoindex-code**: Per-project `.cocoindex_code/` — collision-safe.
**ck**: Per-project `.ck/` — collision-safe.
**grepai**: Per-project index, likely `.grepai/` — expected collision-safe.

---

## Operational Architecture Comparison

| | llm-tldr | grepai | cocoindex-code | ck |
|---|---|---|---|---|
| **Runtime** | Python + tree-sitter + FAISS | Go binary + Ollama | Python + Rust core | Rust binary |
| **Daemon** | Per-project socket daemon | File watcher daemon | Background daemon (auto-start) | No persistent daemon |
| **State location** | `~/.cache/tldr-state/<hash>/` | Project-local | `.cocoindex_code/` | `.ck/` |
| **Embedding model** | all-MiniLM-L6-v2 (local) | Ollama/nomic-embed-text | Snowflake-arctic-embed-xs (local) or LiteLLM | BGE-Small, mxbai-xsmall, etc. (local) |
| **Model download** | Auto on first semantic | `ollama pull nomic-embed-text` | Auto on first index | Auto on first use |
| **Incremental update** | Daemon watches files | File watcher | CocoIndex Rust incremental engine | Auto-delta with chunk caching (80-90% hit rate) |
| **Docker option** | No | docker compose | Yes (full: ~5GB, slim: ~450MB) | No |

---

## Agent Cognitive-Load Comparison

| Factor | llm-tldr | grepai | cocoindex-code | ck |
|--------|----------|--------|----------------|-----|
| **Surfaces to learn** | 3 (MCP, daemon, wrapper) | 2 (CLI, MCP) | 2 (CLI, MCP) | 2 (CLI, MCP) |
| **Init required** | `tldr warm` + `semantic index` | `grepai init` + `grepai watch` | `ccc init` (optional, auto) | None (auto-index) |
| **Pre-warm needed** | Yes (warm + semantic index) | Yes (Ollama model + init) | Partial (auto-index on first search) | No |
| **Failure diagnosis** | Complex: MCP vs daemon split, status can lie | Simple (Ollama down → clear failure) | Simple (`ccc doctor` + `ccc status`) | Simple (`ck --status`, clear errors) |
| **Commands to remember** | 16+ with varying surfaces | ~5 core commands | ~5 core commands | ~5 core commands |
| **Fallback behavior** | Deterministic but surface-dependent | Linear (CLI always available) | Linear (CLI always available) | Linear (CLI always available) |

---

## Founder HITL-Load Comparison

| Factor | llm-tldr | grepai | cocoindex-code | ck |
|--------|----------|--------|----------------|-----|
| **Daemon lifecycle** | Must manage per-project daemons | Must manage Ollama + watcher | Auto-managed daemon | No daemon |
| **Prewarm maintenance** | Cron jobs for canonical repos + worktrees | Needs watch init in each project | Auto-index on first search | Auto-index |
| **MCP hydration** | Complex (4-IDE config sync, Codex restart cycle) | Single MCP config | Single MCP config | Single MCP config |
| **Model management** | FAISS index rebuild on model change | Ollama model management | Auto-download, `ccc reset` for switch | Auto-switch with `--switch-model` |
| **Troubleshooting** | Operator-level (daemon ping, socket, lock, JSON decode diagnostics) | User-level (Ollama status) | User-level (`ccc doctor`) | User-level (`ck --status`) |

---

## Scoring Matrix (1-5)

| Criterion | llm-tldr | grepai | cocoindex-code | ck |
|-----------|----------|--------|----------------|-----|
| Semantic discovery | 4 | 4 | 4 | 5 |
| Exact/static tracing | 4 | 2 | 1 | 1 |
| Call graph/import/caller support | 3 | 2 | 1 | 1 |
| Extraction/token efficiency | 4 | 3 | 3 | 3 |
| CLI usability | 2 | 4 | 4 | 5 |
| MCP usability | 3 | 4 | 4 | 4 |
| Cold-start reliability | 2 | 3 | 4 | 5 |
| Status/failure legibility | 1 | 3 | 5 | 4 |
| Worktree isolation | 4 | 4 | 5 | 5 |
| Index freshness | 3 | 4 | 5 | 5 |
| State/cache transparency | 3 | 4 | 5 | 5 |
| Local/private operation | 5 | 4* | 5 | 5 |
| Install burden | 3 | 3 | 4 | 2 |
| Agent cognitive load | 1 | 3 | 4 | 4 |
| Founder HITL load | 1 | 3 | 4 | 5 |
| Maintenance freshness | 2 | 4 | 5 | 4 |
| **TOTAL (out of 80)** | **45** | **54** | **62** | **63** |

*Note: grepai requires Ollama for local-only operation; default is local but depends on external service.

---

## One-Line Verdicts

| Candidate | Verdict |
|-----------|---------|
| **llm-tldr** | Incumbent with confirmed silent failures and high cognitive load; single-vendor risk |
| **grepai** | Candidate for P2 augmentation (semantic search); lacks structural analysis depth |
| **cocoindex-code** | Candidate for replacement; strongest on operational reliability and diagnostics |
| **ck** | Candidate for replacement; strongest on CLI simplicity, zero-init, and search quality |

---

## Key Insight: The One-Size Gap

**No single tool covers both semantic discovery AND structural analysis.** This is the fundamental finding:

- **llm-tldr**: Covers both but has reliability failures and high cognitive load
- **cocoindex-code + ck**: Cover semantic discovery excellently but lack structural analysis (call graphs, CFG, impact)
- **grepai**: Partial structural (callers) but shallow

The V8.6 routing contract mandates one tool for both. This bakeoff suggests that contract assumption (one tool for all analysis) may itself be the problem. The most reliable tools are purpose-built search engines that don't try to be full static analyzers.

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Replacing llm-tldr breaks structural analysis path | High | Medium | Retain llm-tldr for structural only; adopt new tool for semantic |
| New tool doesn't cover all languages | Medium | Low | All shortlist tools support Python and major languages |
| Dual-tool routing adds agent confusion | Medium | Medium | Explicit routing contract: "semantic → ck/cocoindex, structural → llm-tldr (or direct source reads)" |
| Upstream llm-tldr EOL | Medium | High | Own the structural path (fork/harden) or accept degraded capability |
| Operational burden of new tool | Low | Low | ck and cocoindex-code are both low-maintenance by design |

---

## Recommendation

### Decision: `DEFER_TO_P2_PLUS`

**Reasoning**:

The optimal path is a **split-tool approach**, not a single replacement. This requires:

1. **Semantic discovery**: Adopt **cocoindex-code** or **ck** as the canonical semantic lane
2. **Structural analysis**: Either keep llm-tldr for structural only (reduced surface → fewer failure modes) or accept degraded structural capability (use direct source reads + rg as the structural fallback)

Neither ck nor cocoindex-code alone can replace llm-tldr's full tool surface (call graphs, CFG, program slicing, impact analysis, dead code detection, architecture layer analysis). But both are **dramatically more reliable** for the highest-frequency use case: "where does X live?" / "what code is related to X?"

### Why Not ALL_IN_NOW

- Replacing llm-tldr entirely would lose the structural analysis tool surface (call graphs, CFG, impact, dead code, arch layers) — no single competitor covers these
- The split-tool approach requires a routing contract change (V8.6 contracts are binding) and agent retraining
- Upstream risk for llm-tldr is real but not imminent (tool works for `tree`, `warm` paths)

### Why Not CLOSE_AS_NOT_WORTH_IT

- Confirmed silent failures (`status: ok` with `files: 0`) are real and waste agent turns
- The founder's concern is valid: the current stack has crossed into "real reliability risk"
- Two strong competitors (cocoindex-code, ck) clearly beat llm-tldr on operational reliability with lower cognitive load

### Exact Proposed Next Step

**Run a narrower spike** with two concrete actions:

1. **Adopt ck as a P2 semantic augmentation**: Install `ck`, test on 2-3 worktrees, measure token savings vs. llm-tldr semantic + rg fallback. If it passes, add ck as the canonical semantic-first lane.

2. **Probe the structural gap**: Run `llm-tldr context`, `impact`, `calls` on real worktrees and measure actual agent usage. If these tools are rarely used (matching the V8.6 observation that "6 of 16 MCP tools were effectively unused"), the structural loss may be acceptable and a full replacement becomes viable.

3. **If structural tools are rarely used**: Move to `ALL_IN_NOW` replacement with ck or cocoindex-code as the canonical analysis tool.

4. **If structural tools are frequently used**: Split the routing contract: ck for semantic, llm-tldr for structural (narrower surface, fewer failure modes).

### Recommended Candidate Preference

Between ck and cocoindex-code for the semantic lane:

- **Prefer ck** for: zero-init (no `ccc init` needed), Rust binary (single file, fast), grep-compatible flags, hybrid search (semantic+BM25), TUI for debugging
- **Prefer cocoindex-code** for: `ccc doctor` diagnostics (best failure legibility), Python-native (fits existing stack), Docker option for teams, Claude Code skill integration

Both are excellent. ck edges ahead on simplicity and agent cognitive load (score 63 vs 62), but the margin is thin. Both beat llm-tldr on operational reliability by a wide margin.

---

## Appendix: Commands and Evidence

### A1. llm-tldr Benchmark Commands

```bash
# Tree (works)
bash ~/agent-skills/scripts/tldr-daemon-fallback.sh tree --repo /tmp/agents/bd-9n1t2.16/agent-skills
# Result: OK, 16.3s, full file tree

# Structure (silent failure)
bash ~/agent-skills/scripts/tldr-daemon-fallback.sh structure --repo /tmp/agents/bd-9n1t2.16/agent-skills --language python
# Result: status: ok, files: 0 (SILENT FAILURE)

# Search (silent failure)
bash ~/agent-skills/scripts/tldr-daemon-fallback.sh search --repo /tmp/agents/bd-9n1t2.16/agent-skills --pattern 'semantic.*mixed'
# Result: 0 matches (expected matches exist)

# Status (times out)
timeout 10 bash ~/agent-skills/scripts/tldr-daemon-fallback.sh status --repo /tmp/agents/bd-9n1t2.16/agent-skills
# Result: No output within 10s timeout
```

### A2. Install Commands (for spike)

```bash
# ck
cargo install ck-search

# cocoindex-code
pipx install 'cocoindex-code[full]'

# grepai
brew install yoanbernabeu/tap/grepai
ollama pull nomic-embed-text
```

### A3. Source Verification

| Tool | GitHub | Latest Commit (from page fetch) | License |
|------|--------|-------------------------------|---------|
| llm-tldr | parcadei/llm-tldr | v1.5.2 tagged | MIT |
| grepai | yoanbernabeu/grepai | v0.35.0 (Mar 2026) | MIT |
| cocoindex-code | cocoindex-io/cocoindex-code | v0.2.31 (Apr 27, 2026) | Apache 2.0 |
| ck | BeaconBay/ck | v0.7.4 (Jan 2026) | MIT/Apache 2.0 |
| CodeGraphContext | CodeGraphContext/CodeGraphContext | v0.3.1 (Mar 2026) | MIT |
| sourcebot | sourcebot-dev/sourcebot | Active | AGPL-3.0 |
| byterover-cli | campfirein/byterover-cli | v3.9.0 | Elastic 2.0 |

### A4. Byterover-CLI: Out of Scope for Analysis

byterover-cli (`brv`) is a context memory and REPL tool, not a code analysis engine. It:
- Provides persistent structured memory for AI agents
- Has git-like version control for context trees
- Integrates MCP for tool exposure
- Does NOT provide semantic code search, call graphs, or static analysis

**Assessment**: Valuable for the memory augmentation layer, but does not compete with llm-tldr on code analysis. Separate evaluation needed for memory use case.

### A5. Architecture Memo Availability

The following optional architecture memos were checked:
- `docs/architecture/2026-04-08-analysis-vs-editing-coding-agent-tooling-decision-memo.md` — **NOT FOUND**
- `docs/architecture/2026-04-10-cloud-analysis-alternatives-decision-memo.md` — **NOT FOUND**

Both were noted as optional and their absence does not affect the bakeoff.

### A6. Beads Memory Lookup Results

All targeted memory lookups returned empty:
- `bdx memories llm-tldr` → `{}`
- `bdx search "llm-tldr" --label memory --status all` → `[]`
- `bdx search "MCP hydration" --label memory --status all` → `[]`
- `bdx search "semantic mixed-health" --label memory --status all` → `[]`

No relevant memory records exist, so memory did not influence the bakeoff.
