# Decision Memo: Code-Understanding Architecture Alternatives

**Date:** 2026-04-04
**Topic:** First-principles re-evaluation of the `llm-tldr` code-understanding stack for agent semantic discovery and exact static analysis.
**Context PR:** [Stars-End Agent-Skills #473](https://github.com/stars-end/agent-skills/pull/473)
**Related Issues:** [OpenAI Codex #16702](https://github.com/openai/codex/issues/16702)

## 1. What problem are we actually trying to solve?

We are attempting to provide agents with a high-fidelity, highly compressed repository map (95% token savings) across multiple UI runtimes (Codex desktop, Claude Code, etc.) without mutating the canonical project filesystem or injecting brittle orchestration shims. 

**Pain Attribution Breakdown:**
- **`llm-tldr`:** Owns the desire to write intense local state (`.tldr`) into the nearest project root. It treats statefulness as a requirement for fast contextual querying.
- **Codex desktop MCP hydration:** Exclusively owns the `#16702` bug. Codex successfully registers backend MCP tools via stdio but drops them during UI thread-database hydration. Notably, the Codex CLI does *not* suffer from this bug since it skips the Electron frontend SQLite state mechanism.
- **Our containment/runtime patching:** Owns the `PurePath.__truediv__` global python monkey-patch trap. We actively intercept standard dictionary `pathlib` queries to forcibly export `.tldr` caches. **This is a ticking time bomb.** A standard Python library refactor will crash the entire stack silently.
- **Our fallback helper complexity:** The `tldr-daemon-fallback.py` script exists entirely to route around the Codex Desktop UI bug while blindly preserving the `llm-tldr` daemon architecture.

## 2. Evaluation Criteria

Instead of assuming MCP is the right transport, the framework is evaluated against raw architectural physics:
1. **Reliability in real agent runtimes:** Across Codex (Desktop + CLI), and remote OpenCode instances.
2. **Local-first/worktree-safe behavior:** Absolutely zero path-hijacking required to remain cleanly isolated.
3. **Semantic discovery quality:** Replicating or exceeding `llm-tldr`'s verified upstream metric of 89-99% token compression via AST search.
4. **Exact structural tracing quality:** Accurate call graphs and dead-code detection without redundant coverage against existing tools like `serena`.
5. **Operational simplicity & Agent ergonomics:** Minimal moving parts for the runtime orchestration shell.
6. **Need for custom wrappers/glue:** Avoid daemons and global-override python hooks strictly.

## 3. The True Alternatives (First-Principles Analysis)

A review of the actual ecosystem (`aider`, SCIP, `mentat`) reveals a fundamental split between *Stateful Daemon Architecture* and *Stateless CLI Mapping*.

### Candidate A: Status Quo (The Hybrid Daemon Trap)
- **Description:** Preserve `llm-tldr` and the `_send_command` socket fallback. Accept the `tldr_contained_runtime.py` hook and daemon management logic to route around Codex Desktop's UI failures.
- **Protocol:** Relies on MCP and daemonized sockets.
- **Pros:** Retains current verified 95% token savings; FAISS-backed semantic discovery.
- **Cons:** Binds our core agent code-understanding stack to an explosive `__truediv__` monkey-patch and immense operational complexity merely to satisfy a localized IDE bug. 

### Candidate B: Stateless AST Native Tooling (The Aider Paradigm)
- **Description:** Deprecate MCP and daemons for structure trace completely. Utilize a stateless tree-sitter based mapping script (mirroring `aider`'s PageRank repository map) that generates token-budgeted graphs *on the fly*, entirely in-memory.
- **Protocol:** Pure CLI (Stateless/Ephemeral).
- **Pros:** 100% native worktree isolation. No `.tldr` database to contain, thus deleting the entire monkey-patching and fallback script ecosystem. Immune to Codex thread hydration drops.
- **Cons:** Requires either wrapping `aider`'s mapping logic standalone or replacing `llm-tldr`'s structural mappings manually.

### Candidate C: Upstream `llm-tldr` Stateless Refactor (The True Narrow)
- **Description:** Submit a patch to `parcadei/llm-tldr` that exposes a `--cache-dir` constraint natively, allowing us to enforce `TLDR_STATE_HOME` inside standard environmental variables rather than hijacking the Python VM logic dynamically.
- **Protocol:** MCP + CLI wrapper.
- **Pros:** Keeps the preferred structural tool while eliminating the toxic `PurePath` containment glue.
- **Cons:** Still forces us to own daemon lifecycles inside `dx-runner` transient containers to handle the Codex caching fallback.

## 4. Comparison Matrix

| Criteria | A: Status Quo | B: Stateless Native (Tree-sitter) | C: Upstream Stateless Refactor |
| :--- | :---: | :---: | :---: |
| **Reliability in runtimes** | Low (Codex UI gaps) | Extremely High | Medium |
| **Worktree Safe** | Highest Risk (Gross path hijacking) | Extremely High (In Memory) | High (Native mapping) |
| **Semantic discovery** | High | Very High (Provd by Aider) | High |
| **Structural trace** | High | High | High |
| **Operational Simplicity** | Lowest (Overrides python globals) | High | Medium |
| **Need for custom glue** | High (Daemons + Shims) | None | Medium |

## 5. Recommendation

**Verdict: Reject MCP Transport for Statefulness. Pivot to Stateless AST Tooling.**

Our mandate is minimizing custom glue and guaranteeing local-first worktree safety. 

MCP is the wrong transport layer for a transient context map tool if it demands daemonization and global dictionary path hijacking to remain safe. Relying on `PurePath.__truediv__` overrides to keep `llm-tldr` safely out of the canonical repo is an engineering failure.

We must aggressively strip out the containment patching and pursue **Candidate B**. By shifting code-understanding contexts entirely to stateless `tree-sitter` generators (like `aider`'s map methodology), we eliminate daemon fallbacks, bypass the Codex Desktop UI bugs altogether, and remove the timebomb threat of Python 3.12+ `pathlib` refactors breaking our orchestrator.

If we *must* keep `llm-tldr`, we must strictly enforce **Candidate C**—pausing all `agent-skills` local glue integration until `llm-tldr` supports stateless/cache constraints upstream natively.

## 6. What Not To Do

- **DO NOT** approve the merging of `tldr_contained_runtime.py`. It is a technical trap that hides explosive system-level overrides to mask a tool boundary mismatch.
- **DO NOT** replace `llm-tldr` with Sourcegraph SCIP or Cursor/Windsurf logic, as these rely on intensive asynchronous indexing times or proprietary cloud LSP pipelines that violate our fast, local-first transient `.tmp` lane speed requirements.

## 7. Residual Uncertainty

- **Tool Overlap:** While `serena` focuses heavily on exact symbol patching and basic structural inference, it currently lacks the PageRank-weighted file dependency graphing needed to replace `llm-tldr`. We must verify if extending `serena`'s existing minimal AST capabilities is cheaper than wrapping Aider natively.
