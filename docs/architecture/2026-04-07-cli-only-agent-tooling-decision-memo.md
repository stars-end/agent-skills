# Decision Memo: CLI-Only Agent Tooling Stack

## 1. Problem Statement

Our current default agent assistance stack heavily relies on MCP (Model Context Protocol) servers (`llm-tldr`, `serena`, `cass-memory`) for code understanding, symbol-aware editing, and memory continuity. While powerful, these tools introduce non-deterministic execution environments, high abstraction overhead, IDE/desktop binding dependencies, and occasionally fail silently in strictly CLI-driven, headless, or worktree environments.

To stabilize our DX autonomous workflows, we need a deterministic, CLI-only toolchain that fulfills the same functional footprint while strictly running over standard pipes and standard files.

## 2. Decision Boundary and Hard Constraints

Any recommended tool or stack component must satisfy:
1. **CLI-only**: Must operate entirely via command-line arguments and standard input/output.
2. **MCP-independent**: No reliance on long-running local servers or the Model Context Protocol.
3. **Local-first / Worktree-safe**: Must function correctly within isolated git worktrees (`/tmp/agents/...`) without mutating global IDE state.
4. **Deterministic**: Behavior must be predictable and scriptable for agentic tooling.
5. **No IDE Bindings**: Tools requiring GUI editors, VSCode threads, or background desktop daemons are immediately disqualified.

## 3. Explicit Functionality Map for Current Tools

Before replacing the current stack, we must map exactly what we are replacing.

### A. Code Understanding / Discovery (Currently `llm-tldr`)
*   Semantic discovery and search.
*   Exact structural tracing (call graphs, architectural layers).
*   Change impact analysis.
*   Low-token repository understanding.
*   Dead-code and reachability analysis.

### B. Symbol-Aware Editing Support (Currently `serena`)
*   Lookup definition / references.
*   Symbol-aware rename / refactor loops.
*   Precise insertion-point awareness.

### C. Memory / Continuity (Currently `cass-memory`)
*   Session-to-session persistent context.
*   Shareable notes across agents.
*   State that is transparent and inspectable by human operators.

## 4. Candidate Longlist

During the investigation, we compiled the following candidates:
*   **A. Code Understanding:** `grep-ast` (Aider's contextual grep), `aider --show-repo-map`, `universal-ctags`, `tree-sitter` CLI, `ripgrep` (`rg`). 
*   **B. Symbol-Aware Editing:** `ast-grep` (`sg`), `fastmod`, standard `sed`/`awk`.
*   **C. Memory/Continuity:** `mem0` / `mem0-cli`, `nb` (note board CLI), Letta (MemGPT), SQLite3 local files, Plain Markdown (`AGENTS.md` / `MEMORY.md`) + `rg`. 

## 5. Shortlisted Comparison Matrix

We shortlisted 5 distinct candidates across the three buckets for deep evaluation.

| Candidate | Bucket | CLI Determinism | Worktree/Local Safety | Transparency | Utility | Operator Load |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. `grep-ast`** | A (Discovery) | High | High (no global state) | High (Standard out) | High (Token-compressed AST) | Low |
| **2. `aider` (repo-map)** | A (Discovery) | Medium | High | Low (Wrapped inside Aider) | High (PageRank token opt) | Med (Requires full Aider init) |
| **3. `ast-grep` (`sg`)** | B (Editing) | High | High (Pure functional edit)| High (Pure AST rewrite) | High (Replaces serena precisely) | Med (Requires syntax mastery) |
| **4. `mem0-cli`** | C (Memory) | Med (LLM bounds) | Low (Uses cloud config / DB) | Low (Opaque SQLite/Cloud) | Med | Med (Need external keys) |
| **5. Plain MD + `rg`**| C (Memory) | High | High (Just files) | High (Cat/Grep transparent) | High | Low |

## 6. Rejected Candidates and Why

*   **`aider --show-repo-map`**: While the PageRank-based repository map is exceptional for LLMs, Aider is not packaged as a clean, standalone CLI primitive. Bootstrapping Aider just to extract a repo map creates massive wrapper-tax.
*   **`universal-ctags`**: Completely deterministic, but requires too much LLM intelligence to re-assemble raw tags into the token-compressed, readable context blocks that `grep-ast` produces out-of-the-box.
*   **`tree-sitter-cli`**: Excellent underlying technology (powers `ast-grep` and `grep-ast`), but raw usage requires the agent to write complex S-expressions per-language, increasing cognitive load and error rates.
*   **`mem0` / Letta**: These tools require embeddings/LLM access just to recall context, and usually maintain global SQL databases or cloud ties. They violate the "inspectable local-first" transparency required for worktree continuity.

## 7. Recommended Target Stack

We recommend moving to a **Split Stack** utilizing strictly isolated Unix-philosophy tools.

### Bucket A (Code Understanding): `grep-ast` + `ripgrep`
*   **Why**: `grep-ast` natively solves the core value proposition of `llm-tldr`: providing token-efficient, hierarchical code context without reading full files. When combined with `ripgrep` for raw regex baseline searches, they fully replace `llm-tldr` discovery capabilities with complete CLI determinism.

### Bucket B (Symbol-Aware Editing): `ast-grep` (`sg`)
*   **Why**: `ast-grep` is a dedicated AST structural search-and-replace tool. It operates entirely over the CLI (`ast-grep -p pattern -r replacement`), requires zero daemon runtime, and eliminates the multi-line regex brittleness that makes tools like `sed` dangerous for agent refactoring. It fully supersedes `serena` for symbol-targeted editing.

### Bucket C (Memory/Continuity): Tracked Markdown Files + `ripgrep`
*   **Why**: We already maintain `AGENTS.md` and repository-level docs. Instead of leveraging an opaque persistent memory layer like `cass-memory`, we should enforce agents to write session context explicitly to `docs/agent-memory/` (or similar tracked Markdown paths). Human operators can effortlessly review and revert memory simply using `git` and `bat`/`cat`.

## 8. Migration Implications

*   **Agent Prompts**: Instructions must be rewritten to instruct agents on using `grep-ast` (often aliased as `gast`) and `ast-grep` for discovery and edits.
*   **Environment Setup**: We must ensure `ast-grep` (Rust binary) and `grep-ast` (Python package) are deterministically provisioned on all canonical VMs/worktrees.
*   **Loss of Impact Analysis**: Semantic change impact mapping (a feature of `llm-tldr`) will require chaining `rg` and `grep-ast` calls, meaning agents will perform the analysis themselves rather than relying on a ready-made impact graph.

## 9. What We Should Stop Using By Default

*   `llm-tldr` (MCP Server)
*   `serena` (MCP Server)
*   `cass-memory` (MCP Server)
*   Ad-hoc `grep` / `sed` for complex refactoring chains.

## 10. Residual Uncertainty

*   **AST-Grep Cognitive Load**: Writing `ast-grep` structural patterns is a higher cognitive leap for models than natural language edits via `serena`. We may experience higher retry rates initially as models learn `ast-grep` syntax limits across different languages.
*   **Token Overhead without Aider**: `grep-ast` is excellent for focused files, but lacks Aider's PageRank-based whole-repository map. For massive worktrees, we might hit context limits faster than before.

## 11. Explicit Recommendation

**REPLACE**.

The existing MCP-first layer should be replaced entirely with the CLI-native composite stack:
*   **`grep-ast`** (Contextual Navigation)
*   **`ast-grep`** (Structural Editing)
*   **Plain Markdown** (Persistent Memory)
