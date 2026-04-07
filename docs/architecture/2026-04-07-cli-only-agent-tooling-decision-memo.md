# Decision Memo: CLI-Only Agent Tooling Stack

## 1. Problem Statement
The current agent tooling stack relies heavily on MCP-first and IDE-dependent tools (`llm-tldr`, `serena`, `cass-memory`). This introduces non-determinism, runtime fragility, and coupling to specific client desktop states. We need to reset the scope and identify a deterministic, CLI-only tooling stack that replaces these functions natively in shell environments and worktrees, without sacrificing the core capabilities required for autonomous agent operations.

## 2. Decision Boundary and Hard Constraints
Every recommended tool in the default path must adhere to the following constraints:
1. **CLI-only in normal operation**: No GUI, no background daemon requirement.
2. **Shell callable without MCP**: Must execute standard streams (stdout/stderr).
3. **Safe in worktrees**: Must operate locally within a directory without global side effects.
4. **Deterministic scripting**: Output must be predictable and machine-parsable (e.g., JSON support).
5. **No IDE/Desktop dependency**: Cannot rely on editor plugins, thread hydration, or hidden state.

## 3. Explicit Functionality Map for Current Tools
The current stack covers three main buckets. We must replace or cover:

### A. Code Understanding / Discovery (Currently `llm-tldr`)
- Semantic search
- Exact structural tracing
- File tree / symbol structure
- Call graph / callers / imports
- Change impact / reverse impact
- Architecture understanding
- Dead-code / reachability analysis
- Low-token repo understanding for agents

### B. Symbol-Aware Editing Support (Currently `serena`)
- Symbol lookup
- Reference lookup
- Rename/refactor safety
- Insertion-point awareness
- Function/class-level precision support

### C. Memory / Continuity (Currently `cass-memory`)
- Session-to-session continuity
- Cross-agent sharable notes or recall
- Explicit memory writes/reads from CLI
- Local-first state, inspectable by operators
- Non-IDE-dependent persistence

## 4. Candidate Longlist & Repo Inspections
To ensure grounded recommendations, we directly inspected the source repositories of serious candidates:

1. **Aider (Repo Map)**: We inspected `aider/repomap.py` inside the `aider` repo. It uses `grep_ast` and `tree_sitter` to parse files and build a PageRank-style repository map, allowing it to send highly compressed contexts (e.g., 1024 tokens) to LLMs for massive repos.
2. **ast-grep (`sg`)**: We cloned and inspected `crates/cli/src/lib.rs` inside the Rust-based `ast-grep` repo. It explicitly supports CLI commands like `Scan`, `Test`, `Run`, and outputs JSON directly for structural search and replace using ASTs.
3. **Universal Ctags**: We examined `docs/man/ctags-json-output.5.rst` in the `ctags` repo. It natively supports `JSON Lines` format (`{"_type": "tag", "name": "Klass", "kind": "class"}`), making it trivial for agents to parse programmatically.
4. **Zoekt**: We reviewed `cmd/zoekt/main.go`. Written in Go, it outputs search results in `FileMatch` structs and supports `JSONL` natively via `displayMatchesJSONL`. It is incredibly fast but requires `zoekt-index` to build shards first.
5. **tree-sitter CLI**: Native parser and querying tool for syntax trees, but requires complex S-expression queries.

## 5. Shortlisted Comparison Matrix

| Candidate | Code Understanding | Editing Support | Memory / Continuity | CLI Determinism | Install / Maint Burden | Worktree Safe |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ast-grep (`sg`)** | Structural search, exact match | High (Rewrite rules) | None | High (JSON out) | Low (Single binary) | Yes |
| **tree-sitter CLI** | High (S-expression queries) | None | None | Medium | Medium (Requires grammars)| Yes |
| **Universal Ctags** | Symbol maps, repo structure | Reference lookup | None | High (JSONL) | Low | Yes |
| **Zoekt** | High (Fast indexed search) | None | None | Low (Requires indexing daemon) | High | No (Global index) |
| **Plaintext/Markdown** | None | None | High | High | Zero | Yes |

## 6. Rejected Candidates and Why
- **Zoekt**: Rejected. While extremely fast for large codebases (as seen in `cmd/zoekt-index/main.go`), it requires an active indexing step and often a background daemon (`zoekt-webserver`), which violates the simple CLI/worktree-safe execution constraint.
- **cscope**: Rejected. Poor support for modern languages (TypeScript, Rust, Go) and requires maintaining a bulky cross-reference database.
- **tree-sitter CLI**: Rejected for direct editing. While excellent for discovery, writing S-expression queries on the fly is too high a cognitive load for agents compared to `ast-grep`'s intuitive pattern matching.

## 7. Recommended Target Stack
**Recommendation:** **SPLIT STACK**

We recommend splitting the stack into three focused, Unix-philosophy CLI tools:

1. **Code Understanding / Discovery:** **Universal Ctags + ripgrep**
   - *Why*: `ctags --output-format=json` provides an ultra-low token, language-agnostic map of the repo (replacing `llm-tldr`'s file skeleton/symbol structure). `ripgrep` handles fast, targeted string/regex discovery.
2. **Symbol-Aware Editing:** **ast-grep (`sg`)**
   - *Why*: `ast-grep` provides surgical, AST-based search and replace natively from the CLI. It allows agents to rewrite function signatures, replace method calls, and safely refactor across files without regex fragility (replacing `serena`'s symbol editing).
3. **Memory / Continuity:** **Git-Tracked Markdown (`.agents/memory/`)**
   - *Why*: Simple, transparent, and worktree-safe. Agents can read/write markdown files using standard `cat`/`echo`/`grep`. Cross-agent state is managed via Git commits, completely eliminating the need for `cass-memory` or local databases.

## 8. Migration Implications
- Agents must be trained on `ast-grep` pattern syntax (meta-variables like `$A`).
- Prompts must be updated to request `ctags --output-format=json` instead of `llm-tldr` MCP endpoints.
- Memory management prompts must be redirected to standard file I/O operations on a dedicated memory directory.

## 9. What We Should Stop Using By Default
- `llm-tldr`: Remove from default context. It relies on complex MCP state.
- `serena`: Demote/Remove. Symbol-aware edits should shift to `ast-grep`.
- `cass-memory`: Remove. Shift to flat-file markdown tracking.

## 10. Residual Uncertainty
- **AST-grep pattern difficulty**: Agents may struggle to write syntactically perfect `ast-grep` patterns on the first try, potentially leading to retry loops.
- **Call-graph depth**: `ctags` does not provide deep reverse-call-graph analysis (who calls this function?) as well as an LSP or `llm-tldr` does. We may need to rely on `ripgrep` for reference finding, which is less precise.

## 11. Explicit Recommendation
**SPLIT**
We should split the monoliths into `ctags`, `ast-grep`, and Markdown files.