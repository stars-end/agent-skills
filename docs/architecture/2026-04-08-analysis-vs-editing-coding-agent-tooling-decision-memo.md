# Decision Memo: Analysis vs. Editing Layers for Coding Agent Tooling

## 1. Problem Statement
To build a secure, deterministic, and autonomous coding agent ecosystem, we need to select the optimal tooling stack. Previous attempts to identify a CLI-only replacement stack treated code understanding (analysis) and code mutation (editing) as a single monolithic problem. This led to flawed recommendations that either sacrificed editing precision to meet CLI constraints or rejected valid analysis tools because they lacked editing capabilities.

This memo explicitly decouples the search/retrieval layer from the mutation/refactor layer. It evaluates the full universe of modern code-intelligence systems—including hyper-local embedded RAG engines—and provides distinct architectural recommendations for analysis, editing, and memory.

## 2. Why Earlier Memos Were Insufficient
The previous memo wave (PRs #490, #491, #492, #498) was too shallow because it:
1. **Blurred Analysis and Editing**: It assumed that if a vector RAG tool couldn't edit code, it was a failed tool. This forced an unnatural narrowing to `ctags` + `sed`.
2. **Over-indexed on Generic Vector Backends**: It evaluated raw vector databases (like Qdrant or LanceDB) as if they were turnkey code-search tools, overestimating the installation and maintenance burden.
3. **Missed Hyper-Local, Embedded MCP Tools**: It completely missed an emerging class of modern, zero-daemon, embedded semantic search engines (like `cocoindex-code`, `ck`, and `grepai`) that solve the "Worktree Safe" constraint perfectly while integrating cleanly via MCP.

## 3. Explicit Separation of Layers
To correctly architect an agent stack, we must evaluate three distinct layers independently:
- **Analysis / Retrieval / Discovery**: How does the agent find the right files, understand the architecture, and trace call graphs?
- **Editing / Refactor / Patching**: How does the agent safely mutate the code once the correct context is found?
- **Memory / Continuity**: How does the agent persist state across sessions?

## 4. Current Reference Architecture
- **Analysis**: `llm-tldr` (Semantic + structural extraction, CFG/DFG, daemonized, MCP-bound).
- **Editing**: `serena` (Symbol-aware editing, high precision, MCP-bound).
- **Memory**: `cass-memory` (CLI-based episodic memory).

## 5. Analysis Layer: Longlist and Evaluation

We evaluated 10 candidates, cloning and inspecting the source of `grepai`, `cocoindex-code`, `ck`, and `continue`.

1. **`llm-tldr`**: Our baseline. Excellent structural and semantic hybrid, but relies heavily on daemon hydration and client MCP state.
2. **`grepai`**: Privacy-first semantic grep and call-graph tracer (`grepai trace callers`). **Issue**: Requires a background daemon (`grepai watch`) to keep the index fresh.
3. **`cocoindex-code`**: Ultra-lightweight, AST-based semantic search. **Strength**: 100% local, zero-config, embedded LMDB/SQLite stored directly in `.cocoindex_code/`. Perfect for ephemeral worktrees.
4. **`ck` (Seek)**: Hybrid search (Semantic + Regex). **Strength**: 100% offline, stores indexes in `.ck/`, chunk-level incremental caching, exposes an MCP server natively.
5. **Kilo Codebase Indexing**: Uses Tree-sitter for AST blocks but relies on Qdrant (local Docker or cloud), breaking the zero-daemon/ephemeral worktree requirement.
6. **Zoekt**: Extremely fast trigram/structural search, but requires a persistent background indexer (`zoekt-index`).
7. **Sourcegraph / Cody**: The highest capability ceiling for full code graph and semantic context, but mandates cloud hosting/syncing (high IP/egress risk).
8. **Continue Custom RAG**: Uses LanceDB/SQLite for chunked AST embeddings. Highly effective but heavily bound to the Continue IDE extension ecosystem.
9. **Local DIY Vector (e.g., LanceDB / Chroma)**: Raw infrastructure. Requires building custom AST chunkers, rankers, and routing logic. High wrapper tax.
10. **Hosted Intelligence (e.g., Greptile / Bloop)**: Powerful cross-file analysis and PR review features, but breaks worktree safety and offline execution requirements.

### Analysis Layer Shortlist Matrix

| Candidate | Semantic Discovery | Exact Structural Tracing | Call Graph / Impact | Worktree Safe (Zero Daemon) | Agent Determinism | Privacy / IP Risk |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`llm-tldr`** | High | High | High | Partial (Daemon) | Medium (MCP bound) | Low |
| **`cocoindex-code`**| High (AST) | Low | None | **Yes (Embedded DB)** | High (MCP skill) | Low |
| **`ck` (Seek)** | High (Hybrid) | Low | None | **Yes (Embedded DB)** | High (MCP server) | Low |
| **`grepai`** | High | Medium | High | No (Needs watch) | Medium | Low |
| **Sourcegraph** | High | High | High | No (Cloud sync) | High | High |
| **Kilo Indexing** | High | Medium | Low | No (Qdrant Docker)| Medium | Medium |

## 6. Editing Layer: Shortlist and Evaluation

Unlike analysis, editing requires mechanical safety and precision. Vector/RAG tools provide zero editing capability. 

### Editing Layer Shortlist Matrix

| Candidate | Symbol-Aware Edits | Rename/Refactor Safety | Insertion-Point Awareness | Precision (Zero-Shot) | Determinism / Scriptability |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`serena` (MCP)** | Full | High | Full | High (MCP handles AST) | Medium (Client bound) |
| **`ast-grep` (CLI)** | Full | High | Full | Low (LLMs hallucinate YAML/patterns) | High (CLI native) |
| **Unified Diff / Patch**| None | None | Partial (Regex boundary) | Medium (Indentation sensitive)| High (CLI native) |
| **`sed` / `awk`** | None | None | Low (Line/Regex fragile)| Low (Highly error prone) | High (CLI native) |

**Conclusion on Editing**: There is no CLI-native tool that an LLM can reliably use zero-shot for structural editing. `ast-grep` is theoretically perfect but operationally disastrous because agents cannot accurately predict AST meta-variables without trial-and-error loops. `sed` and diffs are highly deterministic but context-blind and fragile. 

## 7. Memory Layer: Brief Assessment

- **`cass-memory` / `serena` memory**: Introduce complex state management and database dependencies for episodic recall.
- **Markdown/Git-Tracked Notes**: Storing context in `.agents/memory/` as flat markdown files provides 100% of the required continuity with 0% of the operational burden. LLMs natively understand file I/O and Git history perfectly.
- **Verdict**: A dedicated memory software layer is an unnecessary tax. Demote/remove.

## 8. Rejected Candidates and Why
- **Generic Vector DBs (Qdrant, Chroma, LanceDB)**: Rejected as standalone solutions. They are infrastructure, not code-intelligence systems. Building a custom agentic code-chunker on top of them is a massive, unnecessary engineering tax.
- **Kilo / Greptile / Hosted RAG**: Rejected for the default path due to privacy/IP egress risks, lack of worktree safety, and background daemon/Docker requirements.
- **`ast-grep` (as default editor)**: Rejected. While structurally perfect, the cognitive load for an LLM to generate syntactically flawless AST rules in a single turn is too high, leading to failure loops.

## 9. Best Theoretical Capability vs. Best Operational Fit
- **Best Theoretical Capability**: Sourcegraph/Cody (Analysis) + `serena` (Editing). This provides a massive, globally resolved code graph paired with precise, MCP-mediated AST mutations.
- **Best Operational Fit**: A hyper-local, embedded hybrid-RAG tool like `ck` or `cocoindex-code` (Analysis) + "No dedicated editing tool" (relying on standard CLI diffs/sed). This stack operates entirely offline, lives ephemerally inside the `.ck/` or `.cocoindex_code/` directory in the worktree, requires zero daemons, and forces determinism.

## 10. Explicit Architecture Recommendations

### A. Analysis Layer Recommendation: REPLACE with Hyper-Local Embedded RAG
We should replace `llm-tldr`'s analysis features with **`ck`** or **`cocoindex-code`**. 
*Why?* They provide semantic and structural search that is completely contained within the worktree. Because their databases (Tantivy/LMDB) are embedded directly into the repo folder, they require no background daemons, matching the strict operational constraints of CLI environments while exposing clean MCP interfaces for agents.

### B. Editing Layer Recommendation: KEEP `serena` (Accept MCP Dependency) OR NO DEDICATED TOOL
We have two paths depending on our tolerance for MCP:
1. **If MCP is acceptable**: **KEEP `serena`**. It is the only tool that reliably translates an LLM's intent into safe, symbol-aware AST mutations without forcing the LLM to write flawless CLI syntax.
2. **If strict CLI-only is enforced**: **NO DEDICATED EDITING TOOL**. Rely on standard Unix utilities (`sed`, `awk`, unified diffs). We must explicitly accept the massive degradation in refactoring safety, as tools like `ast-grep` are too brittle for zero-shot LLM usage.

### C. Memory Layer Recommendation: DEMOTE
Remove `cass-memory` and `serena` memory functions. Use flat, git-tracked Markdown files.

### D. Overall Stack Recommendation
**SPLIT STACK: Replace Analysis, Keep Editing (if MCP allowed)**

The optimal architecture treats analysis and editing as completely separate domains. 
1. Adopt **`ck`** or **`cocoindex-code`** via their MCP servers for robust, zero-daemon, worktree-safe semantic discovery. 
2. Keep **`serena`** strictly for its symbol-aware editing capabilities. 
3. Remove all complex memory layers in favor of file I/O.

This architecture maximizes retrieval capability while acknowledging that safe, structural code mutation currently requires the specialized guardrails of a tool like `serena`.