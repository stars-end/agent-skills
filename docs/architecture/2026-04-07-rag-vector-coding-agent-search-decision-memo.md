# 2026-04-07 Decision Memo: RAG/Vector Search Layer for Coding Agents

## 1) Problem Statement
We need a retrieval/discovery layer for coding agents that is materially stronger than the recent CLI-only memo wave. That wave was useful for deterministic local workflows, but it did not adequately evaluate the full design space of vector/RAG systems, hosted code intelligence products, and hybrid architectures.

This memo evaluates the full universe of practical candidates and recommends the search-layer direction for `agent-skills`.

## 2) Why Prior CLI-Only Memos Were Insufficient
The prior memo set (`#490`, `#491`, `#492`) focused primarily on deterministic CLI primitives. That answered part of the operations question, but it did not deeply evaluate:
- hosted code-intelligence systems (capability ceiling)
- mature vector backends (local and managed)
- hybrid designs that combine structural retrieval and semantic retrieval

So those memos were good control baselines, not complete search-layer decisions.

## 3) Decision Boundary and Constraints
Primary boundary: search/retrieval/discovery for coding agents.

Hard constraints for default-path suitability:
- determinism and scriptability for autonomous agents
- local/worktree-safe operation for daily development
- clear state/cache ownership and inspectability
- acceptable privacy/IP egress profile
- low wrapper-tax and low operator burden

Secondary considerations:
- composition with symbol-aware editing
- composition with memory/continuity systems

## 4) Current Reference Point (`llm-tldr`)
`llm-tldr` combines:
- semantic retrieval (`tldr semantic`)
- structural/context extraction (`tldr context`, CFG/DFG/calls layers)
- daemonized low-latency retrieval
- MCP bridge layer

Based on upstream docs/repo, this remains a strong baseline for combined semantic + structural context in one tool, with strong latency under daemon mode. It is also operationally sensitive to runtime integration surfaces (MCP/client hydration), which is an external reliability dependency rather than core retrieval quality.

## 5) Candidate Longlist (Evaluated)
1. `llm-tldr` (reference)
2. Sourcegraph Cody + Code Graph + Zoekt
3. Continue + custom code RAG (self-built index)
4. Qdrant-based local code RAG stack
5. Weaviate (OSS/self-host + managed)
6. Milvus OSS + Zilliz Cloud
7. Chroma OSS + Chroma Cloud
8. LanceDB OSS + LanceDB Cloud
9. Postgres + pgvector
10. Pinecone (managed vector backend)
11. GitHub Code Search (non-vector control)
12. Zoekt standalone (non-vector structural/lexical control)

## 6) Shortlist Matrix (Capability + Fit)
Legend: `full` / `partial` / `none`

| Candidate | Mode | Semantic Discovery | Exact Structural Tracing | Impact/Reverse Impact | Local/Worktree Safety | Determinism for Agents | Privacy/IP Risk | Operator Burden |
|---|---|---|---|---|---|---|---|---|
| `llm-tldr` | local OSS | full | full | partial | partial | partial | low | medium |
| Sourcegraph + Cody (+Zoekt) | hosted/hybrid | full | full | partial | partial | partial | high (hosted) | medium/high |
| Continue + custom RAG | hybrid | full | partial | none | partial | partial | variable | high |
| Qdrant stack | local/hybrid | full | none | none | full | full | low (self-host) | high |
| Weaviate | local/hybrid/managed | full | none | none | full (self-host) / partial (managed) | full | variable | high |
| Milvus + Zilliz | local/hybrid/managed | full | none | none | full (self-host) / partial (managed) | full | variable | high |
| Chroma | local/hybrid/managed | full | none | none | full (local) / partial (cloud) | full | variable | medium/high |
| LanceDB | local/hybrid/managed | full | none | none | full (local) / partial (cloud) | full | variable | medium |
| pgvector | local/hybrid | full | none | none | full | full | low (self-host) | medium/high |
| Pinecone | hosted | full | none | none | none | partial | high | medium |
| GitHub Code Search (control) | hosted | partial | partial | none | none | full | high | low |
| Zoekt standalone (control) | local OSS | none | partial | none | full | full | low | medium |

## 7) Local OSS Options
### `llm-tldr`
- Best integrated local candidate for semantic + structural combined retrieval.
- Strength: one system does both behavior-level and structure-level retrieval.
- Weakness: operational fragility when client/runtime integration is unreliable.

### Vector DB-based local stacks (`Qdrant`, `LanceDB`, `Chroma`, `pgvector`, `Milvus` self-hosted)
- Strong semantic retrieval building blocks.
- But these are retrieval engines, not code-structure analyzers.
- To reach coding-agent quality, they require custom chunking, AST/symbol layering, filtering strategy, re-indexing strategy, and often reranking.
- Net: high flexibility, high engineering tax.

### Zoekt (control)
- Excellent deterministic lexical/symbol-aware code search baseline.
- Not semantic by itself.

## 8) Hosted/Cloud Options
### Sourcegraph Cody/Code Graph
- Highest overall product maturity for code-intelligence workflows.
- Strong context system and code graph integration.
- Tradeoff: hosted dependency and potential data egress/privacy constraints depending on deployment mode.

### Pinecone / managed vector providers
- Excellent vector infrastructure and scaling.
- Not code-structure systems; still require substantial code-specific retrieval design.

### Greptile
- Strong market signal for code-review/codebase-context claims, but verification depth here is limited by runtime access issues for docs/API materials in this wave.
- Should be treated as candidate-to-validate, not assumed winner.

### Chroma Cloud / Zilliz Cloud / Weaviate Cloud / LanceDB Cloud
- Strong managed backend options when operating a vector service is not desired.
- Same structural gap: they solve vector retrieval infra, not full code intelligence.

## 9) Hybrid Options
Most realistic architecture patterns are hybrid:
1. Structural engine + semantic vector store
- Example: `Zoekt` (or equivalent structural index) + `Qdrant`/`pgvector`/`LanceDB`.
2. Productized code-intelligence platform + local controls
- Example: Sourcegraph for high-ceiling retrieval + local deterministic fallback path.
3. `llm-tldr`-style integrated local engine + optional external augmentation
- Keep local baseline strong, only call hosted services for targeted high-recall tasks.

## 10) Rejected or De-Prioritized
### Vector backend alone as full replacement
Rejected as complete solution: vector DBs alone do not provide exact structural tracing or impact analysis without substantial extra system design.

### Hosted-only default path
Rejected for default path in this environment due to privacy/IP egress concerns, deterministic operation concerns, and external dependency risk.

### CLI primitives alone as complete answer
Rejected as full answer for search layer: deterministic but capability ceiling is too low for semantic code discovery at scale.

## 11) Best Theoretical Capability vs Best Operational Fit
### Best theoretical capability
Sourcegraph-like productized code intelligence (or similarly mature hosted/hybrid systems) has the highest near-term capability ceiling for retrieval quality and codebase understanding UX.

### Best operational fit for this environment
Local-first hybrid: keep retrieval/control local by default, with optional hosted augmentation only where explicitly approved.

Rationale:
- lower privacy/IP risk
- better deterministic execution for autonomous agents
- less dependence on flaky client tool-surface hydration paths
- still allows semantic retrieval gains via local vector components

## 12) Recommended Architecture Direction
Recommendation: **SPLIT STRATEGY (LOCAL-FIRST HYBRID)**

Default architecture:
1. Local structural retrieval baseline (deterministic)
- keep a strong structural index/search layer (existing `llm-tldr` structural features or a local structural alternative)
2. Local semantic retrieval layer
- add/standardize one local vector backend path (prefer `pgvector` if Postgres operations are already core; otherwise `LanceDB` for fastest local setup)
3. Optional hosted augmentation lane
- allow Sourcegraph/other hosted systems only as explicit opt-in for approved repos/tasks

This avoids both extremes:
- not CLI-only underpowered
- not hosted-only high-risk

## 13) Concrete Next Experiments
1. Build a 2-week benchmark harness across three tracks:
- Track A: current `llm-tldr`
- Track B: local hybrid (`Zoekt` + local vector store with AST-aware chunking)
- Track C: one hosted candidate (Sourcegraph or Greptile if accessible)

2. Use one fixed evaluation suite:
- semantic discovery tasks
- exact structural tracing tasks
- change-impact approximation tasks
- latency p50/p95
- index freshness behavior
- operator actions per successful query

3. Include explicit governance metrics:
- data egress profile
- failure modes under offline/partial connectivity
- reproducibility in worktrees

## 14) Residual Uncertainty
- Hosted candidate verification depth is uneven in this wave (especially Greptile technical docs/API details from this runtime).
- Structural+semantic quality depends heavily on chunking and reranking design for DIY vector stacks.
- This memo is decision-grade for direction, but final selection should follow the benchmark harness above.

## 15) Sources
- `llm-tldr` repo/docs:
  - https://github.com/parcadei/llm-tldr
  - https://github.com/parcadei/llm-tldr/blob/main/README.md
  - https://github.com/parcadei/llm-tldr/blob/main/docs/TLDR.md
- Zoekt:
  - https://github.com/sourcegraph/zoekt
- Sourcegraph Cody docs:
  - https://sourcegraph.com/docs/cody/core-concepts/context
  - https://sourcegraph.com/docs/cody/core-concepts/code-graph
  - https://sourcegraph.com/docs/cody/core-concepts/local-indexing
- Continue docs/repo:
  - https://github.com/continuedev/continue
  - https://docs.continue.dev/guides/custom-code-rag
  - https://docs.continue.dev/guides/codebase-documentation-awareness
- Qdrant:
  - https://github.com/qdrant/qdrant
  - https://qdrant.tech/documentation/
- Weaviate:
  - https://github.com/weaviate/weaviate
  - https://docs.weaviate.io/
- Milvus/Zilliz:
  - https://github.com/milvus-io/milvus
  - https://milvus.io/docs
  - https://zilliz.com/
- Chroma:
  - https://github.com/chroma-core/chroma
  - https://docs.trychroma.com/
- LanceDB:
  - https://github.com/lancedb/lancedb
  - https://lancedb.com/docs
- pgvector:
  - https://github.com/pgvector/pgvector
- Pinecone:
  - https://docs.pinecone.io/
- GitHub Code Search docs:
  - https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax
- Greptile (public site):
  - https://www.greptile.com/
