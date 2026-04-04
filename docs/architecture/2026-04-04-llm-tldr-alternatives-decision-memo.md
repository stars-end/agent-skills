# Decision Memo: Code-Understanding Architecture Alternatives

**Date:** 2026-04-04
**Topic:** Tactical re-evaluation of the `llm-tldr` code-understanding stack fallback path.
**Context PR:** [Stars-End Agent-Skills #475](https://github.com/stars-end/agent-skills/pull/475)
**Context PR SHA:** 2186b9ff0ef114e557f93153f2a0a5d883d21fa9
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

To conclusively settle the fallback path, we measured latency via raw timings on the `agent-skills` repository:
- **Baseline Command:** `context main --project .`
- **Contained CLI (Candidate B):**
  - Cold Run: 7.92s
  - Warm Run: 7.60s
- **Daemon Fallback (Candidate A):**
  - Warm Run: 0.89s
  
**Result:** The stateless CLI fallback imposes an 8.5x latency penalty. Output completeness tests verified 1:1 parity between payloads.

## 5. Recommendation

**Verdict: Modest Hold (Transitional Daemon-Fallback)**

The benchmark data confirms the tactical necessity of the daemon-backed fallback:
- `llm-tldr` stays the canonical tool.
- The `tldr-contained.sh` pure CLI fallback is too slow (7.6s) for interactive agent loops.
- **The Fallback Path:** The `daemon-backed fallback` stays as a **tactical and transitional** bridge, specifically to mitigate the OpenAI Codex Desktop hydration uncertainty (#16702). It should be deprecated if/when an upstream fix restores reliable MCP surface visibility.
