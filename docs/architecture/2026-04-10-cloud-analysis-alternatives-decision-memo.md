# 2026-04-10 Cloud Analysis Alternatives Decision Memo

## Problem Statement
We need to determine if any hosted/managed code-intelligence system provides a superior analysis, retrieval, or discovery capability compared to our current local-first `llm-tldr` stack, specifically for our headless coding agents.

## Why Earlier Memo Waves Under-Covered Cloud Alternatives
Previous evaluations focused on local, low-latency, and zero-egress tools suitable for our secure CLI-based developer experience. Cloud-based analysis tools, often packaged for IDEs or chat platforms, were ignored because they frequently lack the headless API required for automated agentic loops.

## Candidate Longlist
1. **GitHub Copilot (Repo Indexing/Search)**: Primarily an IDE-first semantic search engine.
2. **Augment Context Engine**: Graph-based context retrieval designed specifically for agents via MCP.
3. **Sourcegraph Cody (Code Graph)**: Enterprise-grade cross-repo semantic search and precise code intelligence using SCIP.
4. **Greptile**: API-first codebase intelligence platform focused on agentic usage.
5. **Harness AI (Knowledge Graph)**: Knowledge graph-based context retrieval for SDLC-wide orchestration.
6. **GitLab Duo (Knowledge Graph)**: Native structural tracing and graph-based indexing built directly into the GitLab platform.

## Semantic Search vs. Structural/Impact Analysis
- **Semantic Search**: Uses embeddings for intent-based discovery. Useful for high-level questions ("How does authentication work?"). **Insufficient for deterministic agentic action.**
- **Structural/Impact Analysis**: Uses ASTs, SCIP/LST, and call graphs to map exact references, call sites, and inheritance. **Mandatory for reliable refactoring, dead-code detection, and blast-radius analysis.**

To replace `llm-tldr`, a candidate must excel at *both*.

## Comparison Matrix

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Arch. Understanding | Agent Usability / API Surface | Privacy / IP Egress Risk | Operational Burden | Cloud Dependency Risk |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Copilot** | full | partial | partial | partial | partial | med | low | high |
| **Augment** | full | full | full | full | full | med | low | high |
| **Sourcegraph** | full | full | full | full | full | med | med | high |
| **Greptile** | full | full | full | full | full | med | low | high |
| **Harness AI** | full | full | full | full | full | med | low | high |
| **GitLab Duo** | full | full | full | partial | full | med | low | high |

## Theoretical Capability vs Operational Fit
- **Best Theoretical Capability**: **Sourcegraph (SCIP)** and **Greptile** are the clear winners for exact structural intelligence. Sourcegraph's compiler-grade graph and Greptile's API-first agentic design set the industry standard.
- **Best Operational Fit**: **llm-tldr**. Our headless agents require low-latency, zero-network dependency, and zero-egress environments. Cloud-based intelligence engines introduce latency, egress risks, and vendor lock-in that our current `llm-tldr` stack avoids.

## Recommendation
**Keep local-first (`llm-tldr`)**.

No current cloud alternative justifies the mandatory shift to cloud-dependency and IP egress. `llm-tldr` remains the only solution providing the required combination of exact structural analysis, agentic API control, and zero-network operational reliability.
