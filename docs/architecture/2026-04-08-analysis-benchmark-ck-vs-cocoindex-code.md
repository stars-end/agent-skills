# 2026-04-08 Analysis Benchmark: `ck` vs `cocoindex-code`

## 1) Benchmark Scope
This benchmark follows the contract in `docs/architecture/2026-04-08-analysis-challenger-benchmark-contract.md` and evaluates analysis-layer capability only.

Candidates:
- `ck`
- `cocoindex-code`

Out of scope:
- editing policy
- memory policy

## 2) Capability Table (Contract Labels)
Legend:
- coverage: `full` / `partial` / `none`
- burden/risk: `low` / `medium` / `high`

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Architecture Understanding | Local/Worktree Safety | Determinism/Scriptability | Runtime Burden | Wrapper-Tax Risk |
|---|---|---|---|---|---|---|---|---|
| `ck` | `full` | `partial` | `none` | `partial` | `full` | `full` | `low/medium` | `low/medium` |
| `cocoindex-code` | `full` | `partial` | `none` | `partial` | `partial` | `partial` | `medium` | `medium` |

## 3) Semantic Discovery Comparison
Both tools are real semantic-discovery challengers.

`ck` offers:
- semantic search
- regex search
- hybrid search via reciprocal rank fusion
- automatic local indexing into `.ck/`

`cocoindex-code` offers:
- AST-based semantic code search
- `ccc search`
- project-scoped indexing into `.cocoindex_code/`
- agent integration via skill or MCP

Benchmark judgment for semantic discovery:
- `ck`: `full`
- `cocoindex-code`: `full`

## 4) Structural Tracing Comparison
Neither tool demonstrates parity with `llm-tldr` on exact structural tracing.

`ck`:
- supports semantic, regex, lexical, and hybrid search
- chunks/indexes code with tree-sitter-aware processing
- does not expose call graph, dependency trace, CFG/DFG, or reverse-impact commands

`cocoindex-code`:
- uses AST-based chunking and indexing
- improves semantic retrieval quality by code-aware chunk boundaries
- does not expose callers/callees graphing, dependency tracing, or impact analysis surfaces

Benchmark judgment for exact structural tracing:
- `ck`: `partial`
- `cocoindex-code`: `partial`

The `partial` score reflects code-aware retrieval and chunking context, not true trace parity.

## 5) Call Graph / Impact Comparison
For this benchmark category, both candidates remain below replacement threshold.

`ck`:
- no first-class caller/callee or impact commands found in README/source
- roadmap mentions possible future refactoring assistance, which reinforces that current capability is not there yet

`cocoindex-code`:
- no first-class caller/callee or impact commands found in README/source
- daemon, doctor, and status surfaces focus on indexing/search health, not graph/impact analysis

Benchmark judgment:
- `ck`: `none`
- `cocoindex-code`: `none`

## 6) Operational Burden Comparison
This pair is where the candidates differ most.

`ck` operational model:
- local embedded `.ck/` sidecar
- automatic delta indexing
- CLI-first operation
- optional MCP server mode (`ck --serve`)
- no required always-on background daemon for basic use

`cocoindex-code` operational model:
- local `.cocoindex_code/` project state and SQLite-backed index
- background daemon starts automatically on first use
- explicit daemon commands (`ccc daemon status/restart/stop`)
- CLI and MCP are available, but runtime still revolves around a daemon lifecycle

Net result:
- `ck` is materially better on worktree-local simplicity
- `cocoindex-code` is more local than cloud systems, but not actually zero-daemon

Benchmark burden judgment:
- `ck`: `low/medium`
- `cocoindex-code`: `medium`

## 7) What `ck` Can Do That Matters
1. Strong local semantic discovery with hybrid lexical + semantic search.
2. Embedded `.ck/` index model that is removable and worktree-friendly.
3. Clear CLI-first workflow with optional MCP server mode rather than MCP-only usage.
4. Very good operator story for offline/local code search.

## 8) What `cocoindex-code` Can Do That Matters
1. Strong AST-aware semantic retrieval.
2. Practical CLI commands (`ccc index`, `ccc search`, `ccc status`) and MCP support.
3. Local project-scoped index/state with good agent integration ergonomics.
4. Better code-aware chunking than generic vector infrastructure.

## 9) What Neither Tool Still Does Relative to `llm-tldr`
1. No demonstrated parity on explicit structural tracing.
2. No demonstrated parity on callers/callees/dependency graph workflows.
3. No demonstrated parity on reverse-impact or `change-impact` style analysis.
4. No demonstrated parity on architecture-level multi-hop static analysis.

## 10) Verdict
Verdict: **`narrow llm-tldr and benchmark challengers`**

Decision for this pair:
- `ck` is the stronger operational challenger of the two because its embedded index model is simpler and more worktree-friendly.
- `cocoindex-code` is a credible AST-aware semantic challenger, but the earlier claim that it was effectively a zero-daemon replacement was overstated.
- Neither `ck` nor `cocoindex-code` is a parity replacement candidate for `llm-tldr` on full analysis-layer requirements today.
- Treat both as semantic-discovery challengers, with `ck` the more attractive local-first discovery tool if we ever want a lightweight complement lane.

## 11) Sources
Primary sources used:
- `ck` repository and README:
  - https://github.com/BeaconBay/ck
  - local source inspection of `README.md`, `CHANGELOG.md`, `PRD.txt`
- `cocoindex-code` repository and README:
  - https://github.com/cocoindex-io/cocoindex-code
  - local source inspection of `README.md`, `src/cocoindex_code/daemon.py`, `docker/entrypoint.sh`

Prior-art references consulted:
- PR 517
- PR 516
- PR 501
- PR 498
