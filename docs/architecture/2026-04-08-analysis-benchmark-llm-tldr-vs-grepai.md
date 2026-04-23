# 2026-04-08 Analysis Benchmark: `llm-tldr` vs `grepai`

## 1) Benchmark Scope
This benchmark follows the contract in `docs/architecture/2026-04-08-analysis-challenger-benchmark-contract.md` and evaluates analysis-layer capability only.

Candidates:
- `llm-tldr`
- `grepai`

Out of scope:
- editing policy
- memory policy

## 2) Capability Table (Contract Labels)
Legend:
- coverage: `full` / `partial` / `none`
- burden/risk: `low` / `medium` / `high`

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Architecture Understanding | Local/Worktree Safety | Determinism/Scriptability | Runtime Burden | Wrapper-Tax Risk |
|---|---|---|---|---|---|---|---|---|
| `llm-tldr` | `full` | `full` | `full` | `full` | `partial` | `partial` | `medium` | `medium` |
| `grepai` | `full` | `partial` | `partial` | `partial` | `partial` | `partial` | `medium/high` | `medium` |

## 3) Semantic Discovery Comparison
`grepai` is a real semantic challenger for discovery tasks. Its model is straightforward:
- `grepai init`
- `grepai watch`
- `grepai search "..."`

`llm-tldr` also has strong semantic retrieval (`tldr semantic`), with semantic integrated into a broader analysis stack and daemon query path.

Benchmark judgment for semantic discovery:
- `llm-tldr`: `full`
- `grepai`: `full`

## 4) Structural Tracing Comparison
`llm-tldr` provides explicit analysis surfaces for structure and context:
- `tldr context`
- `tldr calls`
- `tldr impact`
- `tldr change-impact`
- CFG/DFG/PDG surfaces documented in TLDR docs

`grepai` provides call graph tracing commands:
- `grepai trace callers`
- `grepai trace callees`
- `grepai trace graph`

However, `grepai` documentation and source show an emphasis on semantic search + traced relationships, not the same breadth of static-analysis depth (e.g. change-impact equivalent, broader multi-layer analysis surfaces).

Benchmark judgment for exact structural tracing:
- `llm-tldr`: `full`
- `grepai`: `partial`

## 5) Call Graph / Impact Comparison
`llm-tldr` has first-class reverse-impact style commands (`impact`, `change-impact`) in both CLI and MCP mapping.

`grepai` has usable call graph tracing via `trace` commands, but no proven parity with `llm-tldr` change-impact style scope for test selection and downstream blast-radius estimation.

Benchmark judgment:
- `llm-tldr`: `full`
- `grepai`: `partial`

## 6) Operational Burden Comparison
Both tools are not truly one-shot stateless CLIs for best results:
- `llm-tldr`: daemon-centric model with per-project indexes and warm/cache lifecycle
- `grepai`: watcher/daemon model (`grepai watch`) plus embedding provider setup (Ollama, LM Studio, or OpenAI)

Important operational distinctions:
- `grepai` has explicit embedding-provider dependency and watcher lifecycle as core setup
- `llm-tldr` has strong daemon lifecycle coupling and project-state handling

Net result:
- neither eliminates runtime lifecycle burden
- both can be local-first
- neither alone removes client/tool-surface risk if routed via MCP in a fragile environment

Benchmark burden judgment:
- `llm-tldr`: `medium`
- `grepai`: `medium/high`

## 7) What `grepai` Can Do That Matters
1. Strong semantic code discovery with natural language queries.
2. Practical call graph exploration via `trace callers/callees/graph`.
3. Local-first operation with explicit support for worktree-aware usage.
4. Clear CLI workflow and MCP integration options.

## 8) What `grepai` Still Cannot Do Relative to `llm-tldr`
1. No demonstrated parity with `llm-tldr`'s broader structural analysis surfaces.
2. No demonstrated parity with `tldr change-impact` style downstream impact/test targeting.
3. Requires watcher + embedder setup as an operational prerequisite, which raises baseline friction.

## 9) Verdict
Verdict: **`narrow llm-tldr and benchmark challengers`**

Decision for this pair:
- `grepai` is a **real semantic + trace challenger**, not noise.
- It is **not yet a parity replacement candidate** for `llm-tldr` on full analysis-layer requirements (especially structural breadth and reverse-impact coverage).
- Keep `llm-tldr` as primary analysis layer for now, narrow its role to analysis/discovery only, and keep `grepai` as an active challenger in ongoing analysis benchmarks.

## 10) Sources
Primary sources used:
- `llm-tldr` README and TLDR docs:
  - https://github.com/parcadei/llm-tldr/blob/main/README.md
  - https://github.com/parcadei/llm-tldr/blob/main/docs/TLDR.md
- `llm-tldr` source inspection:
  - `tldr/mcp_server.py`
- `grepai` README, docs, and source inspection:
  - https://github.com/yoanbernabeu/grepai
  - https://yoanbernabeu.github.io/grepai/
  - `docs/src/content/docs/trace.md`
  - `cli/watch.go`
  - `daemon/daemon.go`

Prior-art references consulted:
- PR 516
- PR 501
- PR 498
