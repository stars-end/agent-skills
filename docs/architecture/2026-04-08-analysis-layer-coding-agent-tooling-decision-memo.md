# 2026-04-08 Decision Memo: Analysis Layer Tooling for Coding Agents

## 1) Problem Statement
We need a decision for the **analysis / retrieval / discovery** layer only. Prior memo waves mixed analysis with editing and overfit to either generic vector infrastructure or simplistic CLI baselines.

This memo isolates analysis and evaluates whether `llm-tldr` should be kept, narrowed, replaced, or split.

## 2) Why Prior Memos Were Insufficient for Analysis
Earlier memos were insufficient because they:
- mixed analysis and editing into one replacement decision
- treated vector infrastructure as if it were full code-intelligence
- overclaimed parity for semantic tools that do not provide structural tracing or impact analysis

## 3) Current Reference Point: What `llm-tldr` Actually Provides
`llm-tldr` is the current baseline because it combines:
- semantic retrieval (`tldr semantic`)
- structural/context retrieval (`tldr context`)
- cross-file call graph + reverse impact (`tldr calls`, `tldr impact`, `tldr change-impact`)
- CFG/DFG/PDG-oriented static analysis surfaces
- daemon acceleration for low-latency queries

Tradeoff: it is strong technically, but operational reliability can degrade when MCP/client hydration is unstable.

## 4) Longlist (Analysis Candidates)
1. `llm-tldr`
2. `grepai`
3. `cocoindex-code`
4. `ck`
5. Kilo codebase indexing architecture
6. Zoekt
7. Sourcegraph/Cody (+ Code Graph)
8. Continue custom code RAG
9. DIY local vector stack: Postgres + pgvector
10. Greptile (hosted code-intelligence candidate)
11. GitHub Code Search (hosted control)

## 5) Capability Matrix (Analysis Only)
Legend: `full` / `partial` / `none`

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Architecture Understanding | Runtime Model | Local / Worktree Safety |
|---|---|---|---|---|---|---|
| `llm-tldr` | full | full | full | full | CLI + daemon, optional MCP | partial (daemon + project state) |
| `grepai` | full | partial | partial-to-full (trace surfaces) | partial | CLI + watch daemon + MCP option | partial (daemon + embedder deps) |
| `cocoindex-code` | full | partial (AST chunking context) | none | partial | CLI + daemon + MCP | partial (local, but daemon-backed) |
| `ck` | full | partial (hybrid semantic/regex) | none | partial | CLI + embedded index + MCP server mode | full (local embedded `.ck/`) |
| Kilo indexing (legacy) | full | partial | none | partial | VS Code extension + Qdrant + embedder | none for default CLI path |
| Zoekt | none (semantic) | partial (symbol/lexical) | none | partial | indexer + search binaries / webserver | partial (works local, operationally index-heavy) |
| Sourcegraph/Cody | full | full | full (with Code Graph stack) | full | desktop/IDE + SG search stack | none-to-partial (depends on deployment, desktop limits) |
| Continue custom RAG | full | partial | none | partial | IDE-centric + custom MCP/RAG plumbing | partial |
| pgvector DIY | full (if you build pipeline) | none | none | none-to-partial | DB infra + custom chunk/embed/retrieval | full (self-host/local) |
| Greptile | full (claims) | partial/full (claims) | partial/full (claims) | partial/full (claims) | hosted service | none for local-first default |
| GitHub Code Search | partial | partial | none | partial | hosted search | none |

## 6) Local OSS Candidates
### `llm-tldr`
- Best observed combined capability across semantic + structural + impact tracing in one tool.
- Still the strongest candidate when analysis requirements include call graph/impact and architecture-level traces.

### `grepai`
- Strong semantic search with explicit trace commands (`trace callers`, `trace callees`, `trace graph`).
- Requires a watcher/daemon lifecycle and embedder provider setup; not pure one-shot CLI.

### `cocoindex-code`
- Strong AST-based semantic retrieval and practical MCP/CLI integration.
- Provides search well; does **not** provide `llm-tldr`-equivalent call graph / impact analysis.

### `ck`
- Strong local-first semantic/hybrid retrieval and embedded `.ck/` index model.
- Useful discovery engine, but currently not a full structural tracing/impact replacement.

### Zoekt
- Excellent deterministic lexical/symbolic search and ranking.
- Not semantic by itself; no native call-graph/impact parity.

## 7) Hosted/Cloud Candidates
### Sourcegraph/Cody
- Highest capability ceiling for context retrieval plus code graph integration.
- Local indexing docs show desktop/IDE constraints and remote limitations; less suitable as default autonomous CLI substrate.

### Greptile
- Credible hosted candidate with strong product signal.
- Evidence in this wave remains mostly product-facing and hosted-first; insufficient to replace local default path without deeper operator-level validation.

### GitHub Code Search
- Good hosted lexical/symbolic control, but not sufficient as full analysis layer.

## 8) Hybrid Candidates
### Continue custom code RAG
- Practical pattern for custom retrieval with vector DB + MCP server.
- Strong as a framework pattern, not a drop-in analysis engine with structural/impact parity.

### DIY pgvector stack
- Valid infra for semantic retrieval if you build chunking/indexing/ranking logic.
- Infra only; does not solve code-intelligence structure by default.

## 9) Rejected As Full Replacements (and Why)
1. `ck` / `cocoindex-code` as full replacements:
- Rejected as full replacements today because evidence supports semantic discovery strength, not full tracing/impact parity.

2. Generic vector infra (`pgvector` / similar) as full replacements:
- Rejected because infrastructure still needs significant custom code-intelligence layers.

3. Hosted-only default (Sourcegraph/Greptile/GitHub search):
- Rejected for default path due to privacy/egress and deterministic autonomy constraints.

## 10) Best Theoretical Capability vs Best Operational Fit
### Best theoretical capability
- Sourcegraph/Cody + Code Graph has the strongest integrated capability ceiling.

### Best operational fit for this environment
- Local-first default where analysis must be deterministic and worktree-safe, with hosted augmentation optional.

## 11) Recommendation (Analysis Layer)
Recommendation: **NARROW**

- Keep `llm-tldr` as the primary analysis layer **for now**, because it still provides the most complete semantic + structural + impact surface.
- Narrow its role explicitly to analysis/discovery (not editing or memory).
- Treat `grepai`, `ck`, and `cocoindex-code` as semantic-discovery challengers, not parity replacements, until they demonstrate structural tracing and impact parity on benchmark tasks.

In short: do **not** replace `llm-tldr` yet; narrow and benchmark challengers in parallel.

## 12) Concrete Next Experiments (Only Because Evidence Is Not Yet Sufficient for Replacement)
Run a fixed benchmark across `llm-tldr`, `grepai`, `ck`, and `cocoindex-code` on the same repos/questions:
1. Semantic discovery tasks
2. Exact structural tracing tasks
3. Reverse-impact tasks
4. Architecture-understanding tasks
5. p50/p95 query latency and index freshness
6. Operator burden (startup/repair steps)

Exit criterion for replacement:
- challenger must reach parity on structural + impact tasks, not just semantic retrieval.

## 13) Sources
- `llm-tldr` repo/docs: https://github.com/parcadei/llm-tldr
- `grepai` repo/docs: https://github.com/yoanbernabeu/grepai
- `cocoindex-code` repo/docs: https://github.com/cocoindex-io/cocoindex-code
- `ck` repo/docs: https://github.com/BeaconBay/ck
- Kilo indexing docs: https://kilo.ai/docs/customize/context/codebase-indexing
- Zoekt repo/docs: https://github.com/sourcegraph/zoekt
- Sourcegraph Cody docs:
  - https://sourcegraph.com/docs/cody/core-concepts/context
  - https://sourcegraph.com/docs/cody/core-concepts/code-graph
  - https://sourcegraph.com/docs/cody/core-concepts/local-indexing
- Continue custom code RAG docs: https://docs.continue.dev/guides/custom-code-rag
- pgvector repo: https://github.com/pgvector/pgvector
- Greptile site: https://www.greptile.com/
- GitHub Code Search docs: https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax
