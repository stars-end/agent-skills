# 2026-04-10 Decision Memo: Cloud Analysis Alternatives to `llm-tldr`

Feature-Key: bd-9n1t2.12

## 1) Problem Statement
Previous analysis-layer memo waves (bd-9n1t2.6, bd-9n1t2.8, bd-9n1t2.9) converged on
`llm-tldr` as the local-first default and benchmarked three **local OSS** challengers
(`grepai`, `ck`, `cocoindex-code`). Those waves explicitly **under-covered hosted and
managed code-intelligence systems**. Sourcegraph/Cody and Greptile appeared only
briefly in bd-9n1t2.6's longlist with product-facing evidence, and other credible
cloud candidates (Copilot indexing, Augment Context Engine, Harness AI code search,
GitLab Duo / Knowledge Graph) were not evaluated at all.

This memo closes that gap. It evaluates whether any **cloud or cloud-backed**
analysis platform is a real competitor to `llm-tldr` on analysis-layer capability,
or whether cloud candidates are mostly managed semantic search wearing a code-graph
marketing layer.

Scope is strictly the **analysis / retrieval / discovery** layer. Editing,
orchestration, PR review, and memory tooling are out of scope.

## 2) Why Earlier Memo Waves Under-Covered Cloud Alternatives
- bd-9n1t2.6 listed Sourcegraph/Cody, Greptile, and GitHub Code Search but marked
  the hosted evidence as insufficient and deferred to local-first defaults without
  doing a deep capability audit.
- bd-9n1t2.8/bd-9n1t2.9 benchmarked only local OSS challengers (`ck`,
  `cocoindex-code`, `grepai`) against `llm-tldr`.
- No wave evaluated GitHub Copilot's managed index, Augment's Context Engine,
  Harness AI code search, or GitLab Duo's Knowledge Graph even though all four are
  actively marketed as agent-usable code-intelligence surfaces.
- The operator constraint that ruled out hosted defaults (privacy/egress +
  deterministic worktree autonomy) is real, but it is not a substitute for
  actually looking at the capability ceiling of hosted options.

## 3) Reference Point: What `llm-tldr` Actually Provides
Restated for scoring parity:
- Semantic retrieval (`tldr semantic`)
- Structural/context retrieval (`tldr context`)
- Cross-file call graph + reverse impact (`tldr calls`, `tldr impact`,
  `tldr change_impact`)
- CFG/DFG/PDG-oriented static analysis surfaces
- Architecture layering (`tldr arch`)
- Daemon acceleration + MCP tool surface for agents
- Fully local; no code egress; deterministic under worktree-first workflow

The bar a cloud candidate must clear to *replace* `llm-tldr` is not "good semantic
search." It is parity on **exact structural tracing + reverse-impact analysis**
through a surface a CLI/MCP agent can actually drive.

## 4) Required Cloud Candidate Longlist
Required by the research contract (bd-9n1t2.11):
1. GitHub Copilot repository indexing / semantic code search
2. Augment Context Engine
3. Sourcegraph / Cody / Code Graph (with SCIP + GraphQL API)
4. Greptile
5. Harness AI semantic code search
6. GitLab Duo codebase semantic search + Knowledge Graph

No additional candidates are added. The four cloud "code intelligence" entrants
not on the required list (e.g. Codeium/Windsurf indexing, Cursor's codebase index,
Continue custom RAG, Qodo/Codium) were inspected and are either (a) IDE-embedded
semantic-only indexes with no documented structural tracing surface or (b) already
evaluated under prior waves in a different shape. None would change the
recommendation in Section 10.

## 5) Candidate-by-Candidate Findings

### 5.1 GitHub Copilot repository indexing / semantic code search
- **Mechanism**: Embeds every file in the repository, stores in a managed,
  auto-updating index, retrieves top-k semantically similar files at query time.
  Unified in 2026 into a single auto-managed index; local vs remote split
  removed. Directly consumed by Copilot Chat, Copilot Coding Agent, and
  `#codebase` tool invocations.
- **Structural depth**: None beyond what an LLM can infer over retrieved chunks.
  No documented call graph, no reverse-impact primitive, no AST/CFG surface.
- **Agent usability**: Consumed internally by the Copilot Coding Agent, but there
  is **no public, stable "query the index" API** for third-party agents. The index
  is bound to Copilot's own runtime surfaces (VS Code, github.com Copilot Chat,
  Copilot Coding Agent sessions). An external CLI agent cannot issue ad-hoc
  semantic queries the way `llm-tldr semantic` can be called.
- **Privacy / IP egress**: Repositories hosted on github.com are already under
  the GitHub trust boundary, so marginal egress is low; private-enterprise
  repositories hosted elsewhere would need to be mirrored into GitHub to be
  indexed, which is a hard **no-go** for any non-GitHub code.
- **Verdict**: Managed semantic search only. Not a structural competitor.

### 5.2 Augment Context Engine
- **Mechanism**: Real-time indexing of entire codebase including commit history,
  cross-repo dependencies, and architectural patterns. Augment's marketing
  explicitly claims a *graph of dependencies* ("understands callers, downstream
  services, API contracts, test coverage") over 400k+ files. A `DirectContext`
  SDK class allows programmatic indexing and state export; Augment also ships
  an MCP server product ("Context Engine MCP").
- **Structural depth**: Strongest product claims of any cloud candidate here.
  However, the *operator-visible surface* exposed to third-party agents is
  essentially a retrieval endpoint over a proprietary graph-aware retriever,
  not a queryable call-graph API. There is no public `callers(symbol)` or
  `reverse_impact(file)` primitive; the graph is used to bias retrieval, not
  to answer structural questions directly. You get *graph-aware context
  retrieval*, not *structural query*.
- **Agent usability**: MCP server exists and the SDK is real, so an external CLI
  agent can plug in. This is a genuine differentiator against Copilot indexing
  and Harness.
- **Privacy / IP egress**: Full index and commit history live on Augment's
  cloud. High egress. Hard operator blocker unless Augment is approved as a
  processor and their enterprise self-hosted path is used.
- **Verdict**: Closest cloud candidate to a "graph-shaped" analysis surface,
  but still retrieval-shaped, not query-shaped. Not a structural replacement
  for `llm-tldr`'s `calls`/`impact`/`change_impact`.

### 5.3 Sourcegraph / Cody / Code Graph (SCIP + GraphQL API)
- **Mechanism**: SCIP-based precise code intelligence (definitions, references,
  symbols, hover, implementations) produced by per-language indexers and
  uploaded to a Sourcegraph instance. Cody layers semantic retrieval on top.
  Both cloud and self-hostable.
- **Structural depth**: Strongest of any cloud candidate in this list. SCIP gives
  you real def/ref/symbol graphs across repos, and those queries are exposed
  through the **Sourcegraph GraphQL API** — an agent can programmatically ask
  "who references this symbol", "what are the definitions in this file",
  "navigate from this reference to its definition", across many languages.
- **Call graph / impact**: Partial. SCIP gives you the primitives (refs/defs)
  from which a call graph can be reconstructed, and cross-repo navigation is
  a real strength. But there is **no out-of-the-box `change_impact` primitive**
  the way `llm-tldr` provides; callers have to assemble impact queries from
  GraphQL ref-walks. This is closer to `llm-tldr`'s territory than anything
  else on this list.
- **Agent usability**: Very high for an API-consuming agent — GraphQL endpoint,
  stable schema, auth tokens, mature CLI (`src`). Cody's MCP integrations add
  LLM-facing surfaces on top.
- **Privacy / IP egress**: Cloud SaaS has high egress; **self-hosted
  Sourcegraph** is available and flips this to low. This is the only cloud
  candidate that can credibly be operated inside a local-first trust boundary.
- **Operator burden**: Self-hosting Sourcegraph + SCIP indexer pipelines is a
  non-trivial platform investment compared with a local `tldr warm`.
- **Verdict**: Best cloud candidate on capability. With self-hosting, privacy
  ceases to be the disqualifier; operator burden becomes the disqualifier.

### 5.4 Greptile
- **Mechanism**: Repository indexing plus a language-agnostic graph of
  functions, classes, variables, and call relationships. Multi-hop investigation
  (trace dependencies, follow call sites, check git history) is the core
  differentiator Greptile markets. Primary product surface is AI PR review,
  but there is a **public REST API** (`POST /query`, with a `genius=true` flag
  for deeper traces; pricing per "unit" at $0.15/unit, `genius` queries 3x).
- **Structural depth**: Real graph claims, and the API does expose query-style
  access rather than just retrieval. Still, the public interface is a
  natural-language `query` endpoint, not a direct call-graph primitive; the
  graph is used internally to ground the LLM answer rather than being exposed
  as a structured surface.
- **Agent usability**: Yes — REST API is first-class and documented. An
  external CLI agent can drive it.
- **Privacy / IP egress**: Hosted-only by default; self-hosted is enterprise
  contract only. High egress for standard pricing tier.
- **Verdict**: Real agent-usable cloud code-intelligence API. Structural depth
  beyond plain semantic search. But still shaped as an LLM-fronted retrieval
  endpoint, not a deterministic structural query surface.

### 5.5 Harness AI semantic code search
- **Mechanism**: The Harness AI Code Agent indexes the current VS Code
  workspace at launch and uses the semantic index to ground chat, autocomplete,
  PR generation, and inline assistance. Harness AIDA and Harness IDP layer
  natural-language search over catalog/scorecard/workflow data as well.
- **Structural depth**: None documented. This is semantic retrieval feeding an
  IDE assistant. No call graph, no impact analysis, no structural query
  primitive.
- **Agent usability**: Bound to the Harness VS Code / JetBrains extension and
  the Harness platform UI. No third-party CLI/MCP surface for ad-hoc code
  queries.
- **Privacy / IP egress**: Hosted. Harness platform trust boundary.
- **Verdict**: IDE-bound managed semantic search. Not a competitor on the
  analysis-layer axis this memo cares about.

### 5.6 GitLab Duo semantic search + Knowledge Graph
- **Mechanism**: Semantic Code Search converts the codebase to vector
  embeddings stored in Elasticsearch / OpenSearch / pgvector (pluggable via the
  `gitlab-active-context` gem) and compares query embeddings at retrieval time.
  The **GitLab Knowledge Graph** is layered on top and captures entities
  (files, directories, classes, functions) and their relationships, explicitly
  marketed as a "live, embeddable graph database for AI agents" for RAG
  applications. Semantic Code Search is exposed as a **GitLab MCP server tool**.
- **Structural depth**: Claims a real graph at the class/function level. In
  practice the public surface for agents is the MCP tool, which exposes
  semantic search primarily; the Knowledge Graph's deeper structural traversal
  is still most easily consumed through GitLab-native agents and workflows
  rather than an external CLI.
- **Agent usability**: MCP server is real — an external agent can invoke GitLab
  semantic search over a GitLab-hosted codebase. Deeper Knowledge Graph
  traversal is coupled to GitLab Duo's own agent platform.
- **Privacy / IP egress**: Requires code to be hosted in GitLab (SaaS or
  self-managed). For GitLab-resident repos, egress is within the GitLab trust
  boundary. For non-GitLab repos: hard no-go, same as Copilot.
- **Verdict**: Serious on paper, but strongly GitLab-coupled. The MCP surface
  is semantic-search shaped; the structural Knowledge Graph is mostly an
  internal agent substrate, not a general-purpose external query API.

## 6) Comparison Matrix
Legend: `full` / `partial` / `none` for capability; `low` / `medium` / `high`
for risk/burden.

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Architecture Understanding | Agent Usability (API/MCP) | Privacy / IP Egress | Operational Burden | Cloud Dependency |
|---|---|---|---|---|---|---|---|---|
| `llm-tldr` (baseline) | full | full | full | full | full (CLI + MCP) | low | low-medium | low |
| GitHub Copilot indexing | full | none | none | partial (LLM-inferred) | none (internal agent only) | low for GH-hosted / high otherwise | low | high |
| Augment Context Engine | full | partial (graph-aware retrieval) | partial (implicit via retrieval) | partial-to-full (claims) | partial-to-full (SDK + MCP) | high | medium | high |
| Sourcegraph / Cody + Code Graph | full | full (SCIP def/ref/symbols) | partial (constructible via GraphQL ref-walks) | full (cross-repo) | full (GraphQL API + `src` CLI) | low **if self-hosted**; high on cloud | high (self-host) / low (SaaS) | low (self-host) / high (SaaS) |
| Greptile | full | partial | partial (LLM-fronted graph traversal) | partial | full (REST API) | high | low | high |
| Harness AI code search | full | none | none | partial | none (IDE-bound) | medium-high | low | high |
| GitLab Duo + Knowledge Graph | full | partial | partial (graph claims) | partial | partial (MCP tool) | low for GL-hosted / high otherwise | medium | high unless self-managed GitLab |

## 7) Semantic Search vs Structural / Impact Analysis (Explicit Distinction)
The most important finding of this wave:

**Five of six required cloud candidates are managed semantic retrieval.**

- Copilot indexing, Harness AI, and (on its public agent surface) GitLab Duo
  are semantic-search shaped. They embed the codebase, retrieve top-k chunks,
  and hand them to an LLM. They do not expose a callable structural query.
- Greptile and Augment both claim an internal graph and use it to *bias
  retrieval*. Neither exposes a deterministic structural query primitive such
  as `callers(symbol)`, `reverse_impact(file)`, or `dfg(function)` to an
  external agent. The graph is a retrieval quality feature, not a query
  surface.
- **Sourcegraph is the only cloud candidate whose structural layer is
  first-class and queryable**: SCIP def/ref/symbol graph over cross-repo code,
  queryable by GraphQL. That is categorically different from the other five.

`llm-tldr`'s differentiator — `calls`, `impact`, `change_impact`, `cfg`, `dfg`,
`dead`, `arch`, `slice` — is structural *query*, not retrieval. On that axis
only Sourcegraph is in the same category, and only in the *self-hosted*
deployment shape.

## 8) Best Theoretical Capability vs Best Operational Fit
- **Best theoretical capability**: **Sourcegraph self-hosted + SCIP indexers**.
  It is the only cloud candidate whose structural surface can be driven
  programmatically by an external agent in a deterministic, non-LLM-fronted
  way, and it scales to multi-repo cross-reference graphs better than anything
  local. Its call-graph/impact story is still partial (must be reconstructed
  via GraphQL ref-walks) and weaker than `llm-tldr`'s first-class `change_impact`.
- **Best operational fit for this environment**: **`llm-tldr` (local-first,
  unchanged)**. It requires no platform team, no SCIP indexer pipeline, no
  GitLab/Greptile/Augment tenancy, and no code egress. Its weak point remains
  MCP hydration/daemon reliability, which is an execution issue, not an
  analysis-capability issue and is not fixed by any cloud candidate.

## 9) Is Anything Actually Stronger Than `llm-tldr`?
- **On semantic discovery alone**: Augment, Copilot, Sourcegraph, and Greptile
  all plausibly match or exceed `llm-tldr`'s raw semantic retrieval on large
  multi-repo corpora. This is not the decision axis.
- **On structural tracing**: Only **Sourcegraph** is in the same category, and
  only because SCIP exposes real defs/refs via GraphQL. Everything else is
  LLM-fronted retrieval, regardless of "graph" marketing.
- **On call graph / reverse impact**: **Nothing cloud-side matches
  `llm-tldr`'s `change_impact` primitive.** Not Sourcegraph (must be
  reconstructed), not Greptile (LLM-fronted), not Augment (retrieval-shaped).
- **On architecture understanding**: Sourcegraph's cross-repo code graph is a
  genuine edge on *very large* multi-repo monorepos. For the scale of
  `agent-skills` / `prime-radiant-ai` / `llm-common` / `affordabot`, it is
  overkill relative to `llm-tldr arch`.
- **On agent usability**: Sourcegraph GraphQL and Greptile REST are
  first-class API surfaces; Augment has SDK+MCP. Copilot indexing and Harness
  are effectively closed surfaces to an external CLI agent. `llm-tldr` already
  ships MCP + CLI and is the most frictionless of all of them for a local
  agent loop.
- **On privacy / egress / autonomy**: Nothing in this list beats a local
  daemon. Self-hosted Sourcegraph ties for privacy but loses badly on
  operational burden.

The short answer: **no cloud candidate dominates `llm-tldr` on the dimensions
this operation cares about.** Sourcegraph self-hosted is the only serious
capability competitor, and it loses on operator burden.

## 10) Recommendation
**Recommendation: keep local-first (`llm-tldr`).**

Rationale:
1. `llm-tldr`'s differentiator is structural *query* (`calls`, `impact`,
   `change_impact`, `cfg`, `dfg`, `dead`, `arch`). Five of six required cloud
   candidates are semantic *retrieval*, and the sixth (Sourcegraph) only
   partially matches on structural query.
2. No cloud candidate provides a first-class `change_impact`-style primitive
   exposed to external agents. Every cloud "graph" offering (Greptile, Augment,
   GitLab Knowledge Graph) uses the graph to bias retrieval, not to answer
   structural questions deterministically.
3. Sourcegraph self-hosted is the only credible capability competitor and is
   disqualified by operator burden (SCIP indexer pipelines, infra team,
   per-repo indexing CI), not by capability.
4. Privacy / IP egress and cloud-dependency risk remain hard constraints under
   the canonical-repo and worktree-first workflow; all five non-Sourcegraph
   cloud options are `high` on cloud dependency risk.
5. The unresolved operational pain with `llm-tldr` (MCP hydration, daemon
   stability) is an **execution** issue, not an **analysis capability** issue,
   and no cloud candidate fixes it.

**Secondary recommendation (optional augmentation, not replacement):** If a
future initiative crosses into true cross-repo symbol navigation at scale
(e.g. a large monorepo of the size of `prime-radiant-ai` × `llm-common` ×
external services), **self-hosted Sourcegraph + SCIP** is the one cloud option
worth revisiting as an *augmentation* of `llm-tldr`, specifically for
cross-repo `callers`/`definitions` navigation. This is a P2+ consideration and
should not be taken up now under the Founder Cognitive Load Policy.

**Not recommended under any reading of this wave's evidence:**
- Augment Context Engine as replacement (proprietary graph, high egress,
  retrieval-shaped surface)
- Greptile as replacement (LLM-fronted query API, hosted-only, no deterministic
  structural primitive)
- Copilot indexing as analysis layer (no external agent API, semantic only)
- Harness AI as analysis layer (IDE-bound, semantic only)
- GitLab Duo as analysis layer unless the fleet is already GitLab-resident
  (strongly GitLab-coupled, MCP surface is semantic-only)

## 11) Decision
**KEEP LOCAL-FIRST: `llm-tldr` remains the canonical analysis layer.**

No cloud or cloud-backed alternative justifies replacement. One option
(self-hosted Sourcegraph) is defensible as *future augmentation* for
cross-repo symbol navigation if the fleet's scale demands it, and is explicitly
deferred to P2+.

## 12) Sources
- GitHub Copilot repository indexing:
  - https://docs.github.com/copilot/concepts/indexing-repositories-for-copilot-chat
  - https://github.blog/changelog/2025-03-12-instant-semantic-code-search-indexing-now-generally-available-for-github-copilot/
  - https://github.blog/changelog/2026-03-17-copilot-coding-agent-works-faster-with-semantic-code-search/
  - https://code.visualstudio.com/docs/copilot/reference/workspace-context
- Augment Context Engine:
  - https://www.augmentcode.com/context-engine
  - https://www.augmentcode.com/product/context-engine-mcp
  - https://docs.augmentcode.com/context-services/sdk/api-reference
  - https://www.augmentcode.com/blog/announcing-context-lineage
- Sourcegraph / Cody / Code Graph:
  - https://sourcegraph.com/docs/cody/core-concepts/code-graph
  - https://sourcegraph.com/docs/cody/core-concepts/context
  - https://sourcegraph.com/docs/code-search/code-navigation/precise_code_navigation
  - https://sourcegraph.com/docs/api/graphql
  - https://github.com/sourcegraph/scip
- Greptile:
  - https://www.greptile.com/
  - https://docs.greptile.com/pricing
  - https://www.greptile.com/blog/greptile-v4
- Harness AI code search / Code Agent:
  - https://developer.harness.io/docs/platform/harness-ai/code-agent/
  - https://developer.harness.io/docs/platform/harness-aida/aida-code/
  - https://www.harness.io/products/harness-ai
- GitLab Duo semantic search + Knowledge Graph:
  - https://docs.gitlab.com/user/gitlab_duo/semantic_code_search/
  - https://docs.gitlab.com/development/ai_features/semantic_search/
  - https://docs.gitlab.com/user/project/repository/knowledge_graph/
  - https://about.gitlab.com/gitlab-duo/
- Prior internal waves (read from PRs 516/518/519/520):
  - `docs/architecture/2026-04-08-analysis-layer-coding-agent-tooling-decision-memo.md`
  - `docs/architecture/2026-04-08-analysis-benchmark-llm-tldr-vs-grepai.md`
  - `docs/architecture/2026-04-08-analysis-benchmark-ck-vs-cocoindex-code.md`
  - `docs/architecture/2026-04-10-cloud-analysis-alternatives-research-contract.md`
