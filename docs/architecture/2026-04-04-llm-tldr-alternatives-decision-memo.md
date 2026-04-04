# Decision Memo: Code-Understanding Architecture Alternatives

**Date:** 2026-04-04
**Topic:** Tactical re-evaluation of the `llm-tldr` code-understanding stack fallback path.
**Context PR:** [Stars-End Agent-Skills #475](https://github.com/stars-end/agent-skills/pull/475)
**Context PR SHA:** 2bab70996011da8aade10b96c112f379893df9bb
**Related Issues:** [OpenAI Codex #16702](https://github.com/openai/codex/issues/16702)

## 1. What problem are we actually trying to solve?

We are attempting to provide agents with a high-fidelity, token-efficient repository context while routing around the Codex Desktop MCP hydration failure (#16702).

**Pain Attribution Breakdown:**
- **Codex desktop MCP hydration:** Codex successfully registers backend MCP tools via stdio but drops them during frontend UI hydration.
- **The Local Fallback:** To maintain `llm-tldr` functionality inside Codex until the upstream bug is fixed, we built native fallback paths that bypass exactly the MCP socket. 
- **The Core Decision:** Do we keep the background daemon architecture for this fallback (`tldr-daemon-fallback.py`), or simplify significantly to `tldr-contained.sh` CLI runs at the cost of cold-start evaluation latency?

## 2. Evaluation Criteria

Instead of seeking a full replacement of the entire stack, we evaluate the immediate tactical options based on:
1. **Cold-start & Warm Query Latency:** Does a stateless CLI run materially degrade the agent loop speed vs the daemon?
2. **Context Quality (Completeness):** Does the pure CLI fallback produce identical structural CFG/DFG contexts to the daemon payload?

## 3. The Tactical Fallback Candidates

### Candidate A: Preserve the Daemon-Backed Fallback (Status Quo)
- **Description:** Maintain the `tldr-daemon-fallback.py` script bridging the Codex loop explicitly into `llm-tldr`'s caching socket.
- **Pros:** Retains in-memory index speeds (100ms queries).
- **Cons:** Extremely high local orchestrator complexity, relying on `tldr_contained_runtime.py` to intercept filesystem operations to keep state isolated natively.

### Candidate B: Replace with Pure Contained CLI Fallback
- **Description:** Deprecate the daemon dependency inside the fallback script entirely and replace all fallback interactions with `tldr-contained.sh` CLI commands strictly.
- **Pros:** Lowers operational complexity wildly. No daemon sockets required for the fallback path.
- **Cons:** Drops the 100ms warm-cache speed because every query pays the heavy cost of Python interpreter spin-up and local context mapping.

## 4. Recommendation

**Verdict: Modest Hold (Transitional Daemon-Fallback)**

Our current direction is functionally correct:
- `llm-tldr` stays the canonical semantic tool.
- We will NOT migrate to hosted SCIP vector DBs, and we will NOT revive `context-plus`. We will adhere strictly to our local-first constraints using `llm-tldr` and `tree-sitter`.

**The Fallback Path:**
The `daemon-backed fallback` stays for now. However, it must be clearly marked as **tactical and transitional**, pending one of two specific triggers:
1. An upstream Codex fix for issue #16702 that restores reliable MCP socket visibility natively.
2. Direct benchmark proof definitively establishing that the `tldr-contained.sh` pure CLI fallback speed does not materially degrade the common agent loop and produces identical context coverage as the daemon mode.

Pending the results of the latency benchmark wave, we will remain on Candidate A to preserve the highly-optimized query speed for existing UI workloads.
