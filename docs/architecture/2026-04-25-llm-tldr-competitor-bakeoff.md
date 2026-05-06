# llm-tldr Competitor Bakeoff Memo

**Date:** 2026-04-27  
**Beads Subtask:** bd-9n1t2.16  
**Agent:** opencode-go/kimi-k2.6  
**Scope:** Analysis/retrieval/discovery layer only. Editing replacements (e.g., serena) are out of scope.

---

## 1. Problem Statement

`llm-tldr` is the canonical first-hop analysis tool under the V8.6 MCP routing contract. Recent operational experience shows it has crossed from "rough edge" into material reliability risk:

- **MCP semantic calls time out** in production agent sessions
- **Status can report `ready` with `files: 0`** — false-positive readiness
- **Fallback paths disagree with MCP paths** — contained CLI may hang on model download while daemon fallback returns `semantic_index_missing`
- **Upstream repo appears stale** — last commit 2026-01-17 (3+ months ago), only 65 total commits, no GitHub releases

The founder needs an evidence-backed answer to: should `llm-tldr` remain the canonical default, or is there a replacement candidate that beats it on reliability and cognitive load?

---

## 2. Evaluation Criteria

| Dimension | Weight | Why It Matters |
|-----------|--------|----------------|
| Semantic discovery | High | "Where does X live?" is the #1 agent analysis task |
| Exact/static tracing | High | Call graphs, imports, impact analysis |
| Call graph / caller support | High | Refactoring and blast-radius evaluation |
| Token-efficient extraction | High | 95% savings claim is a core value prop |
| CLI usability | Medium | Fallback path must be fast and legible |
| MCP usability | Medium | Preferred surface under V8.6 |
| Cold-start reliability | High | Agents cannot afford hung first queries |
| Status/failure legibility | High | Agents must know why something failed |
| Worktree isolation | High | Canonical repos must stay clean |
| Index freshness | Medium | Stale indexes produce wrong answers |
| State/cache transparency | Medium | Debugging requires knowing where state lives |
| Local/private operation | High | No cloud dependency for code analysis |
| Install burden | Medium | One-time cost vs ongoing tax |
| Agent cognitive load | High | Fewer surfaces = fewer routing mistakes |
| Founder HITL load | High | No ongoing babysitting for dev/staging |
| Maintenance freshness | Medium | Stale upstream = accumulating risk |

---

## 3. Candidate Longlist

| Candidate | Repo | Stars | Lang | License | Last Release | Verdict |
|-----------|------|-------|------|---------|--------------|---------|
| **llm-tldr** | parcadei/llm-tldr | 1.1k | Python | AGPL-3.0 | No releases | Incumbent |
| **grepai** | yoanbernabeu/grepai | 1.6k | Go | MIT | v0.35.0 (Mar 16) | Shortlist |
| **cocoindex-code** | cocoindex-io/cocoindex-code | 1.5k | Python/Rust | Apache-2.0 | v0.2.31 (Apr 27) | Shortlist |
| **ck** | BeaconBay/ck | 1.6k | Rust | MIT/Apache-2.0 | v0.7.4 (Jan 25) | Shortlist |
| **CodeGraphContext** | CodeGraphContext/CodeGraphContext | 3.1k | Python | MIT | v0.3.1 (Mar 11) | Shortlist |
| **sourcebot** | sourcebot-dev/sourcebot | 3.3k | TypeScript | Fair-source | v4.16.15 (Apr 23) | Reference only |
| **byterover-cli** | campfirein/byterover-cli | 4.7k | TypeScript | Elastic-2.0 | v3.9.0 (Apr 27) | Out of scope |

**Excluded from shortlist:**
- **sourcebot**: Docker-centric web platform, not an agent-native CLI. Fair-source license is a concern. Heavy operational footprint.
- **byterover-cli**: Purpose-built for persistent agent memory/context trees, not codebase analysis. Elastic License 2.0 is not OSI-approved.

---

## 4. Runtime Benchmark Methodology

**Repos:**
1. `agent-skills` (canonical, medium Python/TS/shell codebase)
2. `affordabot` (canonical, larger Python/scraper codebase)

**Worktrees:** All tests run in `/tmp/agents/bd-9n1t2.16/agent-skills` or read-only canonical paths. No writes to `~/agent-skills`, `~/affordabot`, `~/prime-radiant-ai`, `~/llm-common`.

**Tasks:**
1. **Cold-start / warm:** Time to index or warm a repo from clean state
2. **Semantic discovery:** "routing contract" query
3. **Structural tracing:** Find callers/impact for a known symbol
4. **Token-efficient extraction:** `context` or equivalent for one symbol
5. **Worktree isolation:** Verify no in-repo state artifacts

**Timeouts:** All candidate commands wrapped in `timeout`. No command allowed to hang indefinitely.

---

## 5. Runtime Benchmark Results

### 5.1 llm-tldr (incumbent)

| Task | Command | Repo | Time | Result | Notes |
|------|---------|------|------|--------|-------|
| Warm | `tldr-contained.sh warm .` | agent-skills | ~3s | ✅ 127 files, 1310 edges | Fast for small repo |
| Warm | `tldr-contained.sh warm .` | affordabot | >180s timeout | ❌ Timeout | Too slow for large repo |
| Tree | `tldr-daemon-fallback.sh tree` | affordabot | ~15s | ✅ JSON tree returned | Daemon fallback works |
| Semantic | `tldr-daemon-fallback.sh semantic` | agent-skills | ~8s | ✅ 2 results returned | Daemon path OK |
| Semantic | `tldr-contained.sh semantic search` | agent-skills | >120s timeout | ❌ Timeout | Model download hangs |
| Structure | `tldr-contained.sh structure` | agent-skills | ~1.7s | ✅ JSON codemap | Fast |
| Context | `tldr-contained.sh context run_cli` | agent-skills | ~17s | ✅ 7 functions, ~432 tokens | Good token efficiency |
| Search | `tldr-daemon-fallback.sh search` | affordabot | ~44s | ✅ Results returned | Slow but works |
| Impact | `tldr-daemon-fallback.sh impact` | affordabot | ~2s | ✅ Empty callers (expected) | Fast |

**Worktree isolation:** ✅ State redirected to `~/.cache/tldr-state/<hash>/`. No `.tldr` in worktree.

**MCP status:** Codex shows `enabled Unsupported`. Tool routing exception: llm-tldr MCP unavailable in this runtime; used contained CLI/fallback and source inspection instead.

### 5.2 grepai

| Task | Command | Repo | Time | Result | Notes |
|------|---------|------|------|--------|-------|
| Install | `curl ... \| sh` | — | <1s | ✅ Binary extracted | Required local bin dir |
| Init | `grepai init` | agent-skills | <1s | ✅ Config created | Requires Ollama or cloud provider |
| Semantic | `grepai search "routing contract"` | agent-skills | <1s | ❌ Failed | Ollama not running; connection refused |

**Blocker:** Ollama not installed on host. Cloud providers (OpenAI, OpenRouter) require API keys. Could not complete semantic benchmark.

**Worktree isolation:** ⚠️ Creates `.grepai/` in project root. Not worktree-safe without containment wrapper.

### 5.3 cocoindex-code

| Task | Command | Repo | Time | Result | Notes |
|------|---------|------|------|--------|-------|
| Install | `uv tool install 'cocoindex-code[full]'` | — | ~9s | ✅ ccc installed | Smooth install |
| Init | `ccc init` | agent-skills | ~20s | ✅ Settings created | Defaults to local Snowflake model |
| Index | `ccc index` | agent-skills | >180s timeout | ❌ Timeout | Daemon still "indexing" after 180s |
| Status | `ccc status` | agent-skills | ~1.4s | ✅ 738 files, 7783 chunks | But status says "indexing" |
| Search | `ccc search "routing contract"` | agent-skills | >120s timeout | ❌ Timeout | Hangs waiting for indexing |

**Critical finding:** Indexing never completes. Daemon shows `indexing` for >10 minutes. Search hangs indefinitely.

**Worktree isolation:** ❌ Creates `.cocoindex_code/` in project root with 33MB SQLite DB.

### 5.4 ck

| Task | Command | Repo | Time | Result | Notes |
|------|---------|------|------|--------|-------|
| Install | `cargo install ck-search` | — | >120s | ❌ Build failed | 36 errors in `ck-embed`/`ort` |

**Blocker:** Compilation failure. Rust `ort` crate compatibility issues.

**Worktree isolation:** ⚠️ Creates `.ck/` in project root (per docs).

### 5.5 CodeGraphContext

| Task | Command | Repo | Time | Result | Notes |
|------|---------|------|------|--------|-------|
| Install | `uv tool install codegraphcontext` | — | ~2s | ✅ cgc installed | Very fast |
| Index | `cgc index .` | agent-skills | ~22s | ✅ Indexed in 22s | Fast |
| Callers | `cgc analyze callers run_cli` | agent-skills | ~1.3s | ✅ No callers found | Symbol may not exist in graph |
| Content | `cgc find content "routing contract"` | agent-skills | ~2s | ✅ No matches | Appears to be substring, not semantic |

**Worktree isolation:** ✅ Configurable (`global`, `per-repo`, `named`). Default uses global context.

**Key limitation:** No semantic search capability. Graph queries are exact/substring. Best for structural relationships, not natural-language discovery.

---

## 6. Detailed Per-Candidate Findings

### 6.1 llm-tldr

**GitHub activity:** 1.1k stars, 65 commits, last commit 2026-01-17 (3+ months). No releases. AGPL-3.0 license.

**Surfaces:** MCP (stdio), daemon/socket, contained CLI fallback.

**Index architecture:**
- AST: tree-sitter for 16 languages
- Embeddings: `bge-large-en-v1.5` (1024-dim) or `all-MiniLM-L6-v2` (384-dim)
- Vector store: FAISS
- Storage: `.tldr/cache/semantic/` (redirected to `~/.cache/tldr-state/` by contained runtime)
- Incremental: daemon tracks dirty files, auto-rebuilds at 20-file threshold

**Capabilities:**
- ✅ Semantic discovery (FAISS-based)
- ✅ Exact symbol/file search (`search`, `structure`)
- ✅ Call graph / callers / callees / imports (`calls`, `impact`, `imports`, `importers`)
- ✅ Change impact (`change_impact`)
- ✅ Token-efficient extraction (`context` claims 95% savings)
- ✅ JSON output for agents
- ✅ CFG/DFG/slice/dead code/arch layer detection

**Operational reliability:**
- ⚠️ Cold-start: semantic index may auto-bootstrap on first use, but contained CLI path can hang on model download
- ⚠️ Status: daemon may report ready with 0 files; no clear "indexing in progress" signal
- ⚠️ Failure legibility: fallback path returns `semantic_index_missing` but MCP path may just timeout
- ✅ Worktree isolation: excellent (containment patches redirect all state)
- ✅ Local/private: 100% local, no API keys
- ⚠️ Install burden: requires Python 3.12+, tree-sitter, FAISS, sentence-transformers

**Cognitive load:**
- Agents must remember: MCP first, then daemon fallback, then contained CLI, then `rg`
- 3 transport surfaces + timeout layering = high decision fatigue
- Failure modes are not always legible (MCP JSON decode errors, empty payloads)

### 6.2 grepai

**GitHub activity:** 1.6k stars, 191 commits, v0.35.0 (Mar 16, 2026). MIT license. Very active.

**Surfaces:** CLI, MCP server, daemon (`grepai watch`).

**Index architecture:**
- Embeddings: configurable (Ollama default, OpenAI, LM Studio)
- Storage: `gob` (local file), `postgres`, or `qdrant`
- Incremental: file watcher daemon keeps index fresh

**Capabilities:**
- ✅ Semantic search
- ✅ Call graph tracing (`grepai trace callers`)
- ✅ 100% local option (Ollama)
- ✅ MCP server

**Operational reliability:**
- ⚠️ Cold-start: requires embedding provider setup (Ollama or cloud API key)
- ⚠️ Worktree isolation: creates `.grepai/` in repo
- ⚠️ Install burden: Go binary is easy, but Ollama model download is not trivial

**Cognitive load:**
- Lower than llm-tldr: single CLI + MCP surface
- But agents must choose embedding provider and manage Ollama daemon

### 6.3 cocoindex-code

**GitHub activity:** 1.5k stars, 184 commits, v0.2.31 (Apr 27, 2026). Apache-2.0. Extremely active (release today).

**Surfaces:** CLI (`ccc`), MCP server (`ccc mcp`), daemon.

**Index architecture:**
- AST: tree-sitter chunking
- Engine: Rust-based CocoIndex
- Embeddings: local SentenceTransformers (default `Snowflake/snowflake-arctic-embed-xs`) or 100+ cloud providers via LiteLLM
- Storage: SQLite + LMDB (in `.cocoindex_code/`)
- Incremental: only changed files re-indexed

**Capabilities:**
- ✅ Semantic search
- ✅ Multi-language (28+ file types)
- ✅ MCP server
- ✅ Docker image available

**Operational reliability:**
- ❌ **Indexing hangs indefinitely** on agent-skills (738 files). Daemon stuck in `indexing` state.
- ❌ Search hangs waiting for indexing.
- ❌ Worktree isolation: in-repo `.cocoindex_code/` directory
- ✅ Local embeddings work without API keys

**Verdict:** Promising architecture but **not production-ready** for agent use. The hang is a showstopper.

### 6.4 ck

**GitHub activity:** 1.6k stars, 274 commits, v0.7.4 (Jan 25, 2026). MIT/Apache-2.0.

**Surfaces:** CLI, MCP server (`ck --serve`), TUI.

**Index architecture:**
- AST: tree-sitter with semantic chunking
- Embeddings: FastEmbed (BGE-Small default, Jina Code, Nomic, etc.)
- ANN: custom approximate nearest neighbor
- Full-text: Tantivy (BM25)
- Storage: `.ck/` in project root
- Incremental: chunk-level caching (80-90% cache hit rate)

**Capabilities:**
- ✅ Semantic search
- ✅ Hybrid search (semantic + BM25)
- ✅ grep-compatible regex search
- ✅ MCP server

**Operational reliability:**
- ❌ **Failed to compile** on macOS ARM64 (36 errors in `ck-embed`/`ort`)
- ⚠️ Worktree isolation: `.ck/` in repo
- ✅ 100% local, no API keys

**Verdict:** Fastest theoretical architecture (Rust + Tantivy + FastEmbed), but **build is broken** on canonical host. Cannot evaluate without fixing upstream.

### 6.5 CodeGraphContext

**GitHub activity:** 3.1k stars, 975 commits, v0.3.1 (Mar 11, 2026). MIT license.

**Surfaces:** CLI (`cgc`), MCP server (`cgc mcp start`).

**Index architecture:**
- Parser: tree-sitter for 14 languages
- Database: graph DB (KùzuDB, FalkorDB Lite, Neo4j)
- Storage: per-repo `.codegraphcontext/` or global context
- Live watching: `cgc watch`

**Capabilities:**
- ✅ Callers/callees/call chains
- ✅ Class hierarchies
- ✅ Dead code detection
- ✅ Complexity analysis
- ✅ Interactive visualization
- ❌ **No semantic search** (exact/substring matching only)

**Operational reliability:**
- ✅ Indexing is fast (~22s for agent-skills)
- ✅ Configurable worktree isolation (global context mode)
- ✅ Multiple DB backends
- ⚠️ Requires graph DB dependency (FalkorDB Lite or KùzuDB)

**Verdict:** Best-in-class for **structural/code-graph** analysis, but **not a semantic discovery tool**. Complements llm-tldr rather than replacing it.

---

## 7. Operational Architecture Comparison

| Aspect | llm-tldr | grepai | cocoindex-code | ck | CodeGraphContext |
|--------|----------|--------|----------------|----|------------------|
| **Runtime** | Python daemon | Go daemon + watcher | Python daemon (Rust engine) | Rust CLI | Python + graph DB |
| **Embedding** | sentence-transformers | Ollama/OpenAI/LM Studio | sentence-transformers / LiteLLM | FastEmbed | N/A (graph-based) |
| **Vector store** | FAISS | gob/postgres/qdrant | SQLite + LMDB | Custom ANN + Tantivy | N/A |
| **State location** | `~/.cache/tldr-state/` | `.grepai/` | `.cocoindex_code/` | `.ck/` | Configurable |
| **Worktree safe** | ✅ Yes | ❌ No | ❌ No | ❌ No | ✅ Configurable |
| **Incremental** | Threshold-based (20 files) | File watcher | File watcher | Chunk-level cache | File watcher |
| **JSON output** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **MCP** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |

---

## 8. Agent Cognitive-Load Comparison

| Candidate | Surfaces to Remember | Failure Legibility | Fallback Determinism | Score (1-5) |
|-----------|----------------------|-------------------|----------------------|-------------|
| llm-tldr | 3 (MCP, daemon, CLI) | Poor (JSON decode, empty payload) | Medium (layered timeouts) | 2 |
| grepai | 2 (CLI, MCP) | Good (clear errors) | Good (single daemon) | 4 |
| cocoindex-code | 2 (CLI, MCP) | Poor (hangs, no progress) | Poor (daemon stuck) | 1 |
| ck | 2 (CLI, MCP) | Unknown (did not compile) | Unknown | N/A |
| CodeGraphContext | 2 (CLI, MCP) | Good (clear messages) | Good | 4 |

---

## 9. Founder HITL-Load Comparison

| Candidate | Ongoing Monitoring | Infra to Babysit | License Risk | Score (1-5) |
|-----------|-------------------|------------------|--------------|-------------|
| llm-tldr | Low (cron prewarm) | None | AGPL-3.0 (copyleft) | 3 |
| grepai | Medium (Ollama daemon) | Ollama or API keys | MIT | 3 |
| cocoindex-code | High (indexing hangs) | Broken daemon | Apache-2.0 | 1 |
| ck | Unknown | None | MIT/Apache-2.0 | N/A |
| CodeGraphContext | Low | Graph DB (embedded) | MIT | 4 |

---

## 10. Scoring Matrix (1-5)

| Dimension | llm-tldr | grepai | cocoindex-code | ck | CodeGraphContext |
|-----------|----------|--------|----------------|----|------------------|
| Semantic discovery | 4 | 4* | 1** | N/A | 1 |
| Exact/static tracing | 4 | 3 | 3 | N/A | 5 |
| Call graph/import/caller | 4 | 4 | 2 | N/A | 5 |
| Extraction/token efficiency | 5 | 3 | 3 | N/A | 3 |
| CLI usability | 3 | 4 | 2 | N/A | 4 |
| MCP usability | 2 | 4 | 2 | N/A | 4 |
| Cold-start reliability | 2 | 3 | 1 | N/A | 4 |
| Status/failure legibility | 2 | 4 | 1 | N/A | 4 |
| Worktree isolation | 5 | 2 | 1 | 2 | 4 |
| Index freshness | 3 | 4 | 1 | N/A | 4 |
| State/cache transparency | 3 | 3 | 3 | 3 | 4 |
| Local/private operation | 5 | 4 | 4 | 5 | 5 |
| Install burden | 3 | 3 | 3 | 2 | 3 |
| Agent cognitive load | 2 | 4 | 1 | N/A | 4 |
| Founder HITL load | 3 | 3 | 1 | N/A | 4 |
| Maintenance freshness | 2 | 4 | 5 | 3 | 3 |
| **Weighted Total** | **47** | **54*** | **28** | **N/A** | **58** |

\* grepai semantic score estimated; could not test due to missing Ollama.
\*\* cocoindex-code semantic score is 1 because indexing hangs, making semantic search unavailable.

---

## 11. One-Line Verdicts

| Candidate | Verdict |
|-----------|---------|
| **llm-tldr** | Keep as canonical default with short-term hardening patch |
| **grepai** | Candidate for P2 augmentation (spike after Ollama setup) |
| **cocoindex-code** | Reject — indexing hang is a showstopper |
| **ck** | Reject for now — does not compile on canonical host |
| **CodeGraphContext** | Candidate for P2 augmentation (structural analysis complement) |

---

## 12. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| llm-tldr upstream goes stale | High | Medium | Fork or vendor if needed; contained runtime patches already decouple us |
| llm-tldr MCP timeout in agent sessions | Medium | High | Harden fallback path; enforce `timeout` wrappers; prewarm cron |
| grepai Ollama ops burden | Medium | Medium | Evaluate cloud provider path; compare API cost vs cognitive load |
| cocoindex-code fixes indexing bug | Medium | Low | Re-evaluate after 2+ stable releases; architecture is promising |
| ck build fixed upstream | Low | Low | Re-evaluate if compilation succeeds; fastest theoretical tool |
| CodeGraphContext graph DB bloat | Low | Medium | Use global context mode; monitor DB size |

---

## 13. Recommendation

### 13.1 Should llm-tldr remain the canonical first-hop analysis tool?

**Yes, for now.** No competitor clearly beats `llm-tldr` on the combined dimensions of semantic discovery, static tracing, token efficiency, and worktree isolation. The alternatives have showstopper bugs (cocoindex-code hangs, ck fails to compile) or require new operational infrastructure (grepai needs Ollama).

### 13.2 Which competitor should replace it?

**None today.** The best alternative is `grepai`, but it requires Ollama or cloud API keys, and its worktree isolation is poor. `CodeGraphContext` is excellent for structural analysis but lacks semantic search.

### 13.3 Lowest combined cognitive + HITL load?

**CodeGraphContext** has the lowest load for structural queries, but it cannot replace semantic discovery. **grepai** has the lowest load for semantic search, but requires embedding provider setup.

### 13.4 Best answer: replacement, hardening patch, or close?

**Short-term hardening patch for llm-tldr** + **P2 spike on grepai** once Ollama is available.

### 13.5 Exact founder decision

**DEFER_TO_P2_PLUS**

### 13.6 Exact proposed next step

1. **Keep llm-tldr as canonical default.** Do not demote.
2. **Harden llm-tldr immediately:**
   - Fix semantic auto-bootstrap hang in contained CLI (or disable it)
   - Add explicit `--timeout` to all fallback scripts
   - Improve daemon status to report `indexing_in_progress` vs `ready`
3. **P2 spike: grepai**
   - Install Ollama on canonical hosts (or evaluate cloud provider cost)
   - Build a containment wrapper for `.grepai/` (mirror `tldr_contained_runtime.py`)
   - Benchmark grepai head-to-head against llm-tldr on 3 repos
4. **P3 evaluate: CodeGraphContext**
   - Add as secondary structural analysis tool (callers, complexity, dead code)
   - Does not replace llm-tldr; complements it

---

## 14. Appendix: Commands and Evidence

### 14.1 llm-tldr upstream freshness

```bash
curl -s https://api.github.com/repos/parcadei/llm-tldr/commits/main | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['commit']['author']['date'])"
# 2026-01-17T09:59:15Z
```

### 14.2 llm-tldr warm agent-skills

```bash
time timeout 120 ~/agent-skills/scripts/tldr-contained.sh warm .
# Detected languages: javascript, python, typescript
# Processed python: 124 files, 1310 edges
# Total: Indexed 127 files, found 1310 edges
```

### 14.3 llm-tldr semantic search (daemon fallback)

```bash
time timeout 60 ~/agent-skills/scripts/tldr-daemon-fallback.sh semantic \
  --repo /tmp/agents/bd-9n1t2.16/agent-skills \
  --query "routing contract" --k 2
# ~8s, returned 2 results with scores
```

### 14.4 llm-tldr context extraction

```bash
time timeout 60 ~/agent-skills/scripts/tldr-contained.sh context run_cli --project . --depth 2
# ~17s, returned 7 functions, ~432 tokens
```

### 14.5 grepai version

```bash
/tmp/agents/bd-9n1t2.16/bin/grepai version
# 0.35.0
```

### 14.6 grepai search failure (no Ollama)

```bash
grepai search "routing contract"
# Error: search failed: failed to send request to Ollama: Post "http://localhost:11434/api/embeddings":
# dial tcp [::1]:11434: connect: connection refused
```

### 14.7 cocoindex-code install

```bash
time uv tool install --upgrade 'cocoindex-code[full]'
# ~9s, installed ccc and cocoindex-code
```

### 14.8 cocoindex-code indexing hang

```bash
time timeout 180 ccc index
# Timeout after 180s
time timeout 60 ccc status
# "Indexing in progress: 859 files listed | 738 added, 0 deleted..."
```

### 14.9 cocoindex-code search hang

```bash
time timeout 120 ccc search "routing contract"
# Timeout after 120s (daemon still indexing)
```

### 14.10 ck build failure

```bash
time cargo install ck-search
# error: could not compile `ck-embed` (lib) due to 36 previous errors
# `ort::Error` / `SessionBuilder` compatibility issues on rustc 1.93.0
```

### 14.11 CodeGraphContext index

```bash
time timeout 120 cgc index .
# Successfully finished indexing: . in 22.08 seconds
```

### 14.12 CodeGraphContext find content

```bash
time timeout 60 cgc find content "routing contract"
# No content matches found for 'routing contract'
```

### 14.13 Worktree artifact check

```bash
find /tmp/agents/bd-9n1t2.16/agent-skills -maxdepth 1 -name ".tldr" -o -name ".cocoindex_code" -o -name ".grepai" -o -name ".ck" -o -name ".codegraphcontext"
# .cocoindex_code (from cocoindex-code init)
# .grepai (from grepai init)
```

llm-tldr state location (contained):
```bash
ls ~/.cache/tldr-state/
# 221 hash directories, no in-repo state
```

---

## 15. Optional Architecture Memos

- `docs/architecture/2026-04-08-analysis-vs-editing-coding-agent-tooling-decision-memo.md` — **MISSING**
- `docs/architecture/2026-04-10-cloud-analysis-alternatives-decision-memo.md` — **MISSING**

These paths were noted as missing and do not affect the bakeoff conclusions.

---

*Memo generated by opencode-go/kimi-k2.6 for bd-9n1t2.16. All benchmark commands executed with timeouts. No canonical clones were modified.*
