# 2026-04-10 Cloud Analysis Alternatives Decision Memo

## Problem Statement
Earlier research waves focused heavily on local, token-efficient analysis tools but under-covered hosted and managed cloud code-intelligence systems. We need to determine if any cloud option meaningfully competes with our local-first `llm-tldr` on analysis-layer capability, structural tracing, and operational fit for headless coding agents.

## Why Earlier Memo Waves Under-Covered Cloud Alternatives
Previous evaluations prioritized zero-latency, local-first execution, and strict IP egress boundaries. Because most cloud alternatives heavily market themselves as IDE extensions (e.g., Copilot Chat) or SaaS products rather than headless agent infrastructure, they were bypassed in favor of tools custom-built for our CLI / headless agent loop.

## Candidate Longlist
1. GitHub Copilot (Repository Indexing / Semantic Code Search)
2. Augment Context Engine
3. Sourcegraph / Cody / Code Graph
4. Greptile
5. Harness AI Semantic Code Search
6. GitLab Duo (Codebase Semantic Indexing / Knowledge Graph)

## Semantic Search vs. Structural/Impact Analysis
- **Semantic Search** relies on vector embeddings and natural language matching. It is excellent for "where is the auth logic?" but fails at exact constraints like "find all callers of `foo()` across the codebase."
- **Structural / Impact Analysis** relies on parsed Abstract Syntax Trees (ASTs), precise symbol resolution, and call graphs. It provides deterministic answers required for refactoring, dead-code detection, and exact blast-radius calculations.
To replace `llm-tldr`, a candidate must excel at *both*, providing structural and impact analysis accessible via API to a headless agent.

## Comparison Matrix

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Arch. Understanding | Agent Usability / API Surface | Privacy / IP Egress Risk | Operational Burden | Cloud Dependency Risk |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **GitHub Copilot** | full | partial | partial | partial | partial | medium | low | high |
| **Augment Context Engine** | full | full | full | full | full | medium | low | high |
| **Sourcegraph / Cody** | full | full | full | full | full | medium | medium | high |
| **Greptile** | full | full | full | full | full | medium | low | high |
| **Harness AI** | full | full | full | full | full | medium | low | high |
| **GitLab Duo / GKG** | full | full | full | partial | full | medium | low | high |

*Note: Copilot is marked "partial" for structural tracing and API surface because its advanced structural features are heavily IDE-bound and lack a robust headless agent API outside of specific MCP server integrations.*

## Best Theoretical Capability vs Best Operational Fit
- **Best Theoretical Capability**: **Sourcegraph** and **Greptile** offer the most comprehensive exact structural tracing. Sourcegraph's SCIP (Semantic Code Intelligence Protocol) is the industry standard for precise cross-repository graphs, while Greptile is purpose-built for agentic API consumption.
- **Best Operational Fit**: **llm-tldr**. Our agents run in secure, isolated environments (e.g., workspaces, dx-runner). Introducing a cloud context engine requires shipping code out of the environment (High/Medium IP egress risk) and introduces network latency into tight agent loops (Cloud Dependency).

## What is actually stronger than llm-tldr?
From a purely analytical standpoint, **Sourcegraph's Code Graph** (SCIP) is stronger than `llm-tldr` because it can seamlessly cross repository boundaries and handles complex language edge cases with compiler-level precision. **Greptile** provides a more modern, agent-native graph API that simplifies blast-radius calculations compared to `llm-tldr`'s local parsers. However, both come at the cost of cloud dependency and egress.

## Explicit Recommendation
**keep local-first (`llm-tldr`)**

While candidates like Greptile and Sourcegraph offer full structural tracing and excellent agent APIs, they introduce unacceptable cloud dependency risks and IP egress concerns for our headless agent stack. `llm-tldr` remains the best operational fit because it provides the required 95% token savings, exact call graph analysis, and context extraction entirely locally with zero external network dependency. No cloud alternative justifies the architectural shift and egress risk required to replace our local analysis layer.
