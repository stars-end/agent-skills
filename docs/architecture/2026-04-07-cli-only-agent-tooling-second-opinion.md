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

## 5. Recommendation
**NARROW**

Instead of building a complex "split" stack of specialized CLI tools (like forcing agents to learn `ast-grep` syntax), we should **narrow** the toolset to the absolute baseline: **`ripgrep` + `sed`/`awk` + Universal Ctags**.

*Why?* The constraint "CLI-only" is correct, but replacing complex MCP tools with complex CLI tools (`ast-grep`, `tree-sitter`) merely shifts the cognitive burden from the infrastructure to the agent's prompt generation. LLMs are universally pre-trained to be absolute experts at standard Unix utilities (`grep`, `sed`, `patch`, standard diffs). They are not universally experts at writing `ast-grep` YAML rules or Tree-sitter S-expressions without trial and error.

**What to keep/demote:**
- **Keep**: `ripgrep` (discovery), `sed`/standard unified diffs (editing).
- **Add**: Universal Ctags (low-token repo mapping to replace `llm-tldr` context generation).
- **Remove**: `llm-tldr` and `serena` from the default contract.
- **Remove**: `cass-memory`. Session memory should be handled entirely via flat markdown files in a `.agents/memory` directory.

## 6. What the First Memo is Likely to Get Wrong
The initial analysis is likely to recommend `ast-grep` or `tree-sitter` to achieve "parity" with `serena`'s structural editing capabilities. 
*The flaw:* Agents frequently hallucinate AST pattern syntax. Our inspection of `ast-grep/crates/cli/src/main.rs` shows it is a strict pattern matcher; an agent can write a functional `sed` replacement or python script to modify a file much faster and more reliably than it can debug a failing `ast-grep` pattern substitution. 

The first memo will also likely overvalue "semantic search" as a distinct tool. LLMs don't need vector search if they have a highly compressed `ctags` map (like the output of `ctags --output-format=json`); they can just read the map and `cat` the relevant files.

## 7. What Not to Build
- **Do not build** a wrapper CLI around `ast-grep` to make it "easier" for agents. This creates a wrapper tax.
- **Do not build** a custom SQLite memory store. File I/O is universally understood by agents.
- **Do not build** a background indexer (like Zoekt). Rely on ephemeral, on-the-fly indexing (`ctags` takes milliseconds).

## 8. Explicit Uncertainty and Follow-up Experiments
- **Uncertainty**: Can `ctags` + `rg` adequately replace the complex call-graph tracing of `llm-tldr`? Deeply nested impact analysis might require too many sequential `rg` loops.
- **Follow-up Experiment**: Benchmark an agent fixing a cross-file TypeScript typing bug using only `rg` and `sed` vs. `ast-grep` to measure token usage and execution time.
- **Is CLI-only the right constraint?** Yes, for deterministic execution. However, we must accept that some "magic" (like automatic refactoring of all references) will be slower or require more agent turns than an LSP-backed tool would provide.

## 9. Conclusion
We should **NARROW** to the simplest, most globally understood Unix primitives, supplemented only by `ctags` for token-efficient repo mapping. We accept the loss of complex semantic features in exchange for zero-maintenance, perfectly deterministic execution.