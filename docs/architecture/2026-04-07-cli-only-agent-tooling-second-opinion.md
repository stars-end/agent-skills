# Second Opinion Memo: CLI-Only Agent Tooling Stack

## 1. First-Principles Restatement of the Problem
The operational goal is to allow AI agents to securely, predictably, and autonomously navigate and mutate code. The current stack (`llm-tldr`, `serena`, `cass-memory`) attempts to solve this via MCP and IDE-bound daemons, creating latency, opaque failure modes, and coupling to host environments. 

This second-opinion investigates whether a strict CLI-only requirement is the correct answer, and if so, what the optimal minimalist stack looks like without anchoring on previous decisions.

## 2. Hard Constraints
Default-path tools must be:
- CLI-native
- Shell callable without MCP
- Safe in worktrees
- Not dependent on IDE, MCP, desktop thread hydration, or hidden client state

## 3. Independent Candidate Shortlist & Source Inspections
To avoid relying on vendor marketing, we inspected the full universe of code discovery and mutation tools, specifically expanding our search to include Local OSS and Cloud-Hosted RAG (Retrieval-Augmented Generation) engines, which are increasingly popular for agentic code discovery.

- **GNU Coreutils (`grep`, `sed`, `awk`, `find`)**: The baseline. Ubiquitous, perfectly deterministic, zero install.
- **Universal Ctags**: Natively supports `JSON Lines` format (`{"_type": "tag", "name": "Klass", "kind": "class"}`), highly deterministic for CLI piping.
- **`ast-grep` (`sg`)**: Powerful AST manipulation, but requires agents to perfectly predict AST nodes and write complex YAML rules.
- **Aider (CLI mode)**: Builds highly efficient `Tree-sitter` maps weighted by PageRank.
- **Local OSS Vector/RAG (e.g., Bloop CLI, CodeGraph)**: Tools using local vector databases (Qdrant, LanceDB) to embed AST chunks. Bloop provides hybrid search (semantic + regex), and CodeGraph adds SQLite-based dependency graph retrieval.
- **Cloud-Hosted RAG Agents (e.g., Greptile CLI)**: Connects a CLI shell to a cloud backend that traces call paths and dependencies to provide full codebase context.

## 4. Comparison Matrix

| Operational Need | `rg` + `sed` | Universal Ctags | `ast-grep` | Local RAG (Bloop/CodeGraph) | Cloud RAG (Greptile) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Semantic Code Discovery** | Low (Text only) | Medium (Symbols) | Medium (AST) | High (Vector Embeddings) | High (Cloud Graph) |
| **Exact Structural Tracing** | Low | Low | High | Medium (AST chunks) | High (Call Path Trace) |
| **Symbol-Aware Editing** | Low (Regex fragile) | None | High | None (Discovery only) | None (Discovery only) |
| **Session Memory** | None | None | None | Low | High (Cloud History) |
| **Deterministic Scripting** | High | High | High | Medium | Low (Cloud Latency) |
| **Install Burden** | Zero | Low | Low | High (Local Vector DBs) | Low (API Auth) |
| **Worktree Safe** | Yes | Yes | Yes | Partial (Heavy local indexing) | No (Syncs to Cloud) |

## 5. Editing Coverage Analysis

A critical finding of this research is that **Vector/RAG code engines completely fail the editing bucket**. They provide rich, semantic read-only context, but offer zero mechanical utility for safe code mutation. There is not a viable full replacement for the editing bucket under the current CLI-only constraints. Any CLI-only path requires accepting some degradation compared to `serena`.

We directly compare realistic editing options:

| Editing Capability | `sed` / unified diff | `ast-grep` | Aider (CLI mode) |
| :--- | :--- | :--- | :--- |
| **Symbol lookup** | None | Partial (AST matching) | Full (PageRank Map) |
| **Reference-aware edits** | None | Partial (Same-file) | Partial (Cross-file via LLM) |
| **Rename/refactor safety** | None | Partial | Partial |
| **Insertion-point awareness**| Partial (Regex boundaries)| Full (AST boundaries)| Full |
| **Scriptability / Determinism**| Full | Full | Partial (LLM in loop) |

## 6. Capability Loss Accounting

If we shift from an MCP-first structural editing tool (`serena`) to a narrowed Unix-primitive stack (`rg` + `sed` + `ctags`), we must explicitly account for the following capability losses. These represent accepted degradation, not true parity replacement:

1. **Symbol-Aware Rename/Refactor Safety**: Lost. Agents cannot confidently rename a function and implicitly update all usages across a large project. They must manually string-replace (`sed`) across all files, risking regex fragility and false positives.
2. **Reference-Aware Edits**: Lost. A basic CLI stack cannot intrinsically know if an edited variable affects shadowed variables in another scope. 
3. **Insertion-Point Precision**: Degraded. While `serena` understands exactly where a class ends, an agent using `sed` or unified diffs must rely on line numbers or pattern matching that can easily break if the file is concurrently modified or if indentation is ambiguous.

## 7. Recommendation
**NARROW AND ACCEPT DEGRADATION**

CLI-only is the right architectural constraint for reliable, cross-VM execution, but symbol-aware editing parity is not currently available without accepting degradation. We should **narrow** the toolset to the absolute baseline: **`ripgrep` + `sed`/`awk` + Universal Ctags**. 

*Why reject RAG/Vector tools?*
1. **Local RAG** (Bloop, CodeGraph) imposes massive install burdens (running Qdrant/LanceDB locally) and heavy background indexing that breaks ephemeral worktree workflows.
2. **Cloud RAG** (Greptile) breaks the "Worktree Safe" rule by requiring cloud synchronization and authentication, making it unusable for offline or secure isolated agent tasks.
3. **Editing Void**: RAG only solves code discovery. We still need a mutation tool. Replacing complex MCP tools with complex CLI tools (`ast-grep`, `tree-sitter`) merely shifts the cognitive burden to the agent's prompt generation. Agents frequently hallucinate AST pattern syntax but are pre-trained experts at standard Unix utilities (`grep`, `sed`, `patch`, standard diffs). 

**What to keep/demote:**
- **Keep**: `ripgrep` (discovery), `sed`/standard unified diffs (editing). We explicitly accept the degradation in editing precision.
- **Add**: Universal Ctags (low-token repo mapping to replace `llm-tldr` context generation).
- **Remove**: `llm-tldr` and `serena` from the default contract.
- **Remove**: `cass-memory`. Session memory should be handled entirely via flat markdown files in a `.agents/memory` directory.

## 8. What the First Memo is Likely to Get Wrong
The initial analysis is likely to recommend `ast-grep` or `tree-sitter` to achieve "parity" with `serena`'s structural editing capabilities. 
*The flaw:* Agents frequently hallucinate AST pattern syntax. Our inspection of `ast-grep/crates/cli/src/main.rs` shows it is a strict pattern matcher; an agent can write a functional `sed` replacement or python script to modify a file much faster and more reliably than it can debug a failing `ast-grep` pattern substitution. 

The first memo will also likely overvalue "semantic search" as a distinct tool. LLMs don't need heavyweight Vector/RAG search if they have a highly compressed `ctags` map (like the output of `ctags --output-format=json`); they can just read the map and `cat` the relevant files.

## 9. Conclusion
CLI-only is the right constraint. We should **NARROW** to the simplest, most globally understood Unix primitives, supplemented only by `ctags` for token-efficient repo mapping. We explicitly reject both local and cloud RAG tools due to their heavy daemon/indexing requirements, worktree unsafety, and complete lack of mutation support. We must explicitly accept the loss of complex semantic editing features in exchange for zero-maintenance, perfectly deterministic execution.