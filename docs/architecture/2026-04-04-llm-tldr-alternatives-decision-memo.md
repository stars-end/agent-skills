# Decision Memo: Code-Understanding Architecture Alternatives

**Date:** 2026-04-04
**Topic:** Tactical re-evaluation of the `llm-tldr` code-understanding stack fallback path.
**Context PR:** [Stars-End Agent-Skills #475](https://github.com/stars-end/agent-skills/pull/475)
**Context PR SHA:** acf52a50e5fc93244f1ca6bf76cfda88899e772a
**Related Issues:** [OpenAI Codex #16702](https://github.com/openai/codex/issues/16702)

## 1. What problem are we actually trying to solve?

We are attempting to provide agents with a high-fidelity, token-efficient repository context while routing around the Codex Desktop MCP hydration failure (#16702).

**Pain Attribution Breakdown:**
- **Codex desktop MCP hydration:** Codex successfully registers backend MCP tools via stdio but drops them during frontend UI hydration (a general desktop hydration uncertainty).
- **The Local Fallback:** To maintain `llm-tldr` functionality inside Codex until the upstream bug is fixed, we built native fallback paths that bypass exactly the MCP socket. 
- **The Core Decision:** Do we keep the background daemon architecture for this fallback (`tldr-daemon-fallback.py`), or simplify significantly to `tldr-contained.sh` CLI runs at the cost of cold-start evaluation latency?

## 2. Evaluation Criteria

Instead of seeking a full replacement of the entire stack, we evaluate the immediate tactical options based on:
1. **Cold-start & Warm Query Latency:** Does a stateless CLI run materially degrade the agent loop speed vs the daemon?
2. **Context Quality (Completeness):** Does the pure CLI fallback produce identical structural CFG/DFG contexts to the daemon payload?

## 3. The Tactical Fallback Candidates

### Candidate A: Preserve the Daemon-Backed Fallback (Status Quo)
- **Description:** Maintain the `tldr-daemon-fallback.py` script bridging the Codex loop explicitly into `llm-tldr`'s caching socket.
- **Pros:** Retains in-memory index speeds.
- **Cons:** Extremely high local orchestrator complexity, relying on `tldr_contained_runtime.py` to intercept filesystem operations to keep state isolated natively.

### Candidate B: Replace with Pure Contained CLI Fallback
- **Description:** Deprecate the daemon dependency inside the fallback script entirely and replace all fallback interactions with `tldr-contained.sh` CLI commands strictly.
- **Pros:** Lowers operational complexity wildly. No daemon sockets required for the fallback path.
- **Cons:** Drops the warm-cache speed because every query pays the heavy cost of Python interpreter spin-up and local context mapping.

## 4. Benchmark Validation

To conclusively settle between Candidate A and Candidate B, we measured latency via raw bash timings (`context main --project .`):

- **Contained CLI (Candidate B):**
  - Cold Run: ~7.92 seconds
  - Warm Run: ~7.60 seconds
- **Daemon Fallback (Candidate A):**
  - Warm Run: ~0.89 seconds
  
*(Output completeness tests verified structural AST match probability as identical 1:1.)*

## 5. Recommendation

**Verdict: Modest Hold (Transitional Daemon-Fallback)**

Our current direction is functionally correct and solidly evidenced by the benchmark:
- `llm-tldr` stays the canonical semantic tool.
- We will NOT migrate to hosted vector DBs, nor to stateless AST mappers natively.
- The `tldr-contained.sh` pure CLI fallback speed (7.6 seconds) materially degrades the common agent loop. An 8.5x latency penalty is structurally unacceptable.

**The Fallback Path:**
The `daemon-backed fallback` stays. However, it must be clearly marked as **tactical and transitional**, pending an upstream Codex fix for issue #16702 that restores reliable MCP socket visibility natively.
