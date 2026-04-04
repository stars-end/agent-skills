# Decision Memo: Code-Understanding Stack & llm-tldr Alternatives

**Date:** 2026-04-04
**Topic:** Re-evaluating the `llm-tldr` code-understanding stack for agent semantic discovery and exact static analysis.
**Context PR:** [Stars-End Agent-Skills PR #473](https://github.com/stars-end/agent-skills/pull/473)
**Related Issues:** [OpenAI Codex #16702](https://github.com/openai/codex/issues/16702)

## 1. Current-State Summary

The current canonical routing contract (as per recent V8.6 updates) establishes `llm-tldr` as the primary tool for semantic discovery (via FAISS + `bge-large`) and exact static analysis (CFG/DFG, slicing, call graphs). `context-plus` has been fully removed, and `serena` is explicitly designated for symbol-aware edits and persistent assistant memory.

However, the operational reality of this stack is currently laden with heavy custom glue and significant failure modes in certain runtimes:

1. **Codex Desktop MCP Hydration Gap:** In Codex desktop (version `0.118.0-alpha.2`), MCP tools are successfully registered and show as `enabled` via `codex mcp list`. The backend server processes are alive. Yet, the `thread_dynamic_tools` sqlite state frequently fails to expose `llm-tldr` and `serena` to the active thread context. The model silently falls back to reading raw files instead of utilizing token-saving context tools (which offer up to 95% token savings). 
2. **Containment Complexity:** Because of our strict "no canonical write" rules and worktree-first paradigm, `llm-tldr` requires significant monkey-patching and wrapper logic (`tldr_contained_runtime.py`) to prevent its `.tldr` cache and `.tldrignore` files from leaking into the repository.
3. **Fallback Helper Burden:** To circumnavigate the Codex thread hydration gap, we have built a daemon-backed CLI fallback helper (`tldr-daemon-fallback.py`). This adds a complex secondary API surface agents must selectively use when MCP fails.

### Problem Attribution
- **`llm-tldr`:** Responsible for the desire to write cache state (`.tldr`) locally in the nearest project root.
- **Codex desktop MCP hydration:** 100% responsible for the missing thread surface despite active/registered MCP tool configuration.
- **Our containment/runtime patching:** Responsible for the heavy file-system hijacking necessary to force `llm-tldr` into compliance with our worktree-safe standards.
- **Our fallback helper complexity:** A direct downstream consequence of the interaction between the Codex desktop bug and the need for agent workflow continuity.

## 2. Evaluation Criteria

Any proposed stack or alternative must be evaluated against the following:

1. **Reliability in real agent runtimes:** Across Codex, standard CLI endpoints, and remote `dx-runner`/OpenCode instances.
2. **Local-first/worktree-safe behavior:** No leaking of build/cache artifacts into canonical repositories or temporary worktrees.
3. **Semantic discovery quality:** Ability to effectively perform intent-based "Where does X live?" queries.
4. **Exact structural tracing quality:** Accurate call graphs, slicing, dead-code analysis, and structural maps.
5. **Operational simplicity & Agent ergonomics:** Minimal custom configurations and straightforward prompts describing tool usage. 
6. **Need for custom wrappers/glue:** Our core constraint is zero-to-low custom operational overhead.

## 3. Candidate Shortlist

1. **Candidate A: Keep `llm-tldr` + current mitigation glue (The Status Quo)**
   - *Pros:* High token efficiency (95% savings), excellent semantic discovery, powerful CFG/DFG capabilities. We have already written the containment patches.
   - *Cons:* Extremely fragile glue logic. If Codex continues to drift, fallback scripts will break or require continuous maintenance.

2. **Candidate B: Narrow `llm-tldr` to a Pure CLI tool (No MCP Daemon)**
   - *Description:* Drop the MCP config rendering for Codex entirely. Call `llm-tldr` strictly via a single unified CLI wrapper (which agents invoke using standard shell tools). 
   - *Pros:* Exposes one reliable interface across all runtimes. Solves the Codex thread hydration gap by side-stepping MCP in affected tools.
   - *Cons:* The CLI approach doesn't benefit from MCP UI integrations. We still have to run the containment wrappers (`tldr_contained_runtime.py`) to keep `.tldr` data isolated. 

3. **Candidate C: Split the Stack (Native Tools + Ripgrep/Ctags)**
   - *Description:* Abandon unified semantic/structural AI search. Use `ripgrep` for discovery, standard AST/TreeSitter scripts for structure, and `serena` exclusively for navigation. 
   - *Pros:* Purely local, completely stateless (no `.tldr` directories to contain), and works natively without custom daemons. 
   - *Cons:* Destroys semantic "intent-based" discovery. It reverts us to keyword-guessing and requires agents to read massive files to infer CFG, ballooning token usage and regressing context efficiency. 

4. **Candidate D: Standardize on an alternative local MCP Server (e.g., `qdrant-mcp` or generic language servers)**
   - *Description:* Use standalone LSP servers for structure, and a different vector-DB based tool for search.
   - *Pros:* Highly standardized.
   - *Cons:* LSPs provide poor semantic discovery and lack the "95% token compression" features of `llm-tldr`'s context extraction tool. It replaces our custom glue with configuring multiple independent language environments for every worktree.

## 4. Comparison Matrix

| Criteria | A: Status Quo | B: Narrow (CLI only) | C: Split (RG/Ctags) | D: Alternative MCPs |
| :--- | :---: | :---: | :---: | :---: |
| **Reliability in runtimes** | Low (Codex MCP gap) | High | High | Low (Same Codex bugs) |
| **Worktree-safe** | High (but expensive glue) | High (but expensive glue) | High (Native) | Varies |
| **Semantic discovery** | High | High | None | Medium |
| **Structural trace**| High | High | Low | High (Language dependent) |
| **Operational Simplicity** | Low | Medium | High | Low |

## 5. Recommendation

**Verdict: Keep but Narrow.**

We should **narrow the role** of `llm-tldr` to a purely CLI-backed surface (using our contained CLI wrappers) for endpoints exhibiting the MCP hydration bug (Codex desktop), while allowing valid MCP integrations to continue on platforms that natively support it (e.g. Claude Code).

**Why?**
The token savings and structural analysis precision of `llm-tldr` are unmatched and impossible to replicate with simple split tools like `ripgrep` without sacrificing significant accuracy. The actual root cause of the current pain is an upstream `Codex` issue (#16702) combined with our fallback routing complexity. 

By standardizing agent instructions to use the CLI fallback `tldr-contained.sh` script as the first-class interaction point specifically for the Codex lane (bypassing the daemon/MCP socket), we immediately isolate the fault. This simplifies agent ergonomics and relies reliably on `tldr_contained_runtime.py`, treating the Codex MCP unreliability as an environment restriction, not a reason to discard our best tool. 

## 6. What Not To Do

- **DO NOT** replace `llm-tldr` with a hosted service or cloud vector-database. This fundamentally violates our local-first, worktree-safe constraints.
- **DO NOT** discard the `tldr_contained_runtime.py` containment patches. They are functioning properly and cleanly redirect state to `~/.cache/tldr-state/`, which honors the `dx-verify-clean` gate on canonical clones.
- **DO NOT** spend engineering cycles building custom CFG/slicing python AST scripts just to bypass `llm-tldr`. `llm-tldr` is already doing the heavy lifting.

## 7. Residual Uncertainty

- **Codex Upstream Resolution:** It remains unconfirmed if or when OpenAI will release a fix for bug #16702 correcting the MCP thread-hydration failure.
- **Performance Overhead of CLI Invocation:** Continually invoking the CLI wrapper over the daemon reduces caching efficiency compared to the constant socket connection. We must measure if the cold-start overhead of consecutive `llm-tldr` CLI commands outweighs the token savings inside deep agent loops.
