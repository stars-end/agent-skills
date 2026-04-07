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
To avoid relying on vendor marketing or the framing of the first memo, we cloned and inspected the source code of several serious candidates:
- **GNU Coreutils (`grep`, `sed`, `awk`, `find`)**: The baseline. Ubiquitous, perfectly deterministic, zero install.
- **Universal Ctags**: We examined `docs/man/ctags-json-output.5.rst` in the `ctags` repo. It natively supports `JSON Lines` format (`{"_type": "tag", "name": "Klass", "kind": "class"}`), making it highly deterministic for CLI piping.
- **`ast-grep` (`sg`)**: We cloned the repo and inspected the `crates/cli` implementation. While powerful for AST manipulation, it requires the agent to perfectly predict AST nodes and write complex YAML rules or meta-variables.
- **Aider (CLI mode)**: We inspected `aider/repomap.py`. Aider builds highly efficient `Tree-sitter` maps weighted by PageRank.
- **Zoekt**: We inspected `cmd/zoekt/main.go`. While it outputs fast `JSONL` search results, it mandates a separate `zoekt-index` daemon compilation step, violating the simple worktree execution rule.

## 4. Comparison Matrix

| Operational Need | `rg` + `sed` | Universal Ctags | `ast-grep` | Aider (CLI/Map) |
| :--- | :--- | :--- | :--- | :--- |
| **Semantic Code Discovery** | Low (Text only) | Medium (Symbols) | Medium (AST) | High (PageRank AST Map) |
| **Exact Structural Tracing** | Low | Low | High | Medium |
| **Symbol-Aware Editing** | Low (Regex fragile) | None | High | High (AI driven) |
| **Session Memory** | None | None | None | Low |
| **Deterministic Scripting** | High | High | High | Medium |
| **Install Burden** | Zero | Low | Low | Medium |
| **Wrapper Tax Risk** | Zero | Low | Medium | High |

## 5. Editing Coverage Analysis

There is not a viable full replacement for the editing bucket under the current CLI-only constraints. Any CLI-only path requires accepting some degradation compared to `serena`.

We directly compare three realistic editing options:

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

*Why?* Replacing complex MCP tools with complex CLI tools (`ast-grep`, `tree-sitter`) merely shifts the cognitive burden from the infrastructure to the agent's prompt generation. Agents frequently hallucinate AST pattern syntax but are pre-trained experts at standard Unix utilities (`grep`, `sed`, `patch`, standard diffs). 

**What to keep/demote:**
- **Keep**: `ripgrep` (discovery), `sed`/standard unified diffs (editing). We explicitly accept the degradation in editing precision.
- **Add**: Universal Ctags (low-token repo mapping to replace `llm-tldr` context generation).
- **Remove**: `llm-tldr` and `serena` from the default contract.
- **Remove**: `cass-memory`. Session memory should be handled entirely via flat markdown files in a `.agents/memory` directory.

## 8. What the First Memo is Likely to Get Wrong
The initial analysis is likely to recommend `ast-grep` or `tree-sitter` to achieve "parity" with `serena`'s structural editing capabilities. 
*The flaw:* Agents frequently hallucinate AST pattern syntax. Our inspection of `ast-grep/crates/cli/src/main.rs` shows it is a strict pattern matcher; an agent can write a functional `sed` replacement or python script to modify a file much faster and more reliably than it can debug a failing `ast-grep` pattern substitution. 

The first memo will also likely overvalue "semantic search" as a distinct tool. LLMs don't need vector search if they have a highly compressed `ctags` map (like the output of `ctags --output-format=json`); they can just read the map and `cat` the relevant files.

## 9. Conclusion
CLI-only is the right constraint. We should **NARROW** to the simplest, most globally understood Unix primitives, supplemented only by `ctags` for token-efficient repo mapping. We must explicitly accept the loss of complex semantic editing features in exchange for zero-maintenance, perfectly deterministic execution.