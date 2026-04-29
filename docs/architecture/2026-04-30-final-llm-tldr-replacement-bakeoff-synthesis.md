# Final llm-tldr Replacement Bakeoff Synthesis

**Date:** 2026-04-30
**BEADS_EPIC:** bd-9n1t2.30
**BEADS_SUBTASK:** bd-9n1t2.30.4
**Feature-Key:** bd-9n1t2.30.4
**Mode:** synthesis

## Founder Decision

**Decision: ALL_IN_NOW for removing `llm-tldr` from default first-hop routing.**

This is not an all-in adoption of a third-party replacement. The final bakeoff did not produce a candidate that can replace the full `llm-tldr` surface today. The all-in action is the routing change: stop making agents try `llm-tldr semantic` before doing the reliable thing they already do after it fails.

Two follow-up corrections matter:

- grepai was not rejected. It is blocked from default routing until Ollama is installed, model-pulled, indexed, and wrapped with machine-safe readiness/error checks.
- CocoIndex as a project was not fully tested. The worker tested `cocoindex-code 0.2.31` through the `ccc` path. CocoIndex V1 is live and explicitly moves to an embedded LMDB, state-driven model that may address the daemon/state burden observed here. The tested `ccc` path is rejected; CocoIndex V1/latest deserves a focused rerun before the replacement search is closed.

Default lookup should become:

```text
critical-path discovery -> rg/fd/direct reads
known-symbol edit/refactor -> serena
bounded structural question -> direct reads first; optional bounded llm-tldr structural command only when it is known to work
semantic enrichment -> explicit async/on-demand only; no mandatory first-hop semantic tool
```

`llm-tldr semantic` should be removed from the canonical default route. Its current behavior adds a recurrent failed step (`semantic_index_missing`, MCP timeout, or index confusion) before agents fall back to `rg` anyway.

## Problem Statement

The original question was whether `llm-tldr` should remain canonical, be demoted, or be replaced. The operational problem is now sharper than the first bakeoff assumed: agents repeatedly hit a routing note like:

```text
llm-tldr was configured, but semantic fallback returned semantic_index_missing; I used targeted rg/direct reads per fallback contract.
```

That means `llm-tldr semantic` is not saving cognitive load. It is creating a ritual failure before the real work starts.

The decision must optimize:

- agent cognitive load
- founder HITL load
- critical-path latency and reliability
- privacy/IP egress
- avoiding hidden daemon/index state

## Prior-Art Summary

Prior PRs:

| PR | Head SHA | Purpose | Finding Used Here |
|---|---|---|---|
| #592 | e1476ae9e1a0a007ce77916ac60fc47367203c7b | llm-tldr semantic fail-fast hardening | Hardened failure behavior still leaves semantic missing as a common route outcome. |
| #593 | 79774cec2db1f337f54f10b3da0e9ddd95a831b3 | earlier competitor bakeoff | Docs/source review made grepai, CocoIndex, ck, and CodeGraphContext look promising. |
| #594 | d662dcabe0710860bbd9c1b42a0a35aa83d165c8 | runtime-grounded bakeoff | Runtime invalidated CocoIndex and ck for immediate use; CodeGraphContext remained structural-only; grepai required embedding-provider setup. |

The important lesson from #593 -> #594 is that docs/source attractiveness did not predict agent-ready reliability. Runtime behavior dominates the decision.

## Beads Dependency Graph

```text
bd-9n1t2
  bd-9n1t2.30 Final bakeoff: llm-tldr replacement candidates
    bd-9n1t2.30.1 grepai local Ollama semantic replacement
    bd-9n1t2.30.2 CodeGraphContext structural replacement
    bd-9n1t2.30.3 CocoIndex final semantic recheck
    bd-9n1t2.30.4 Synthesis: final llm-tldr replacement bakeoff decision
```

`bd-9n1t2.30.4` is blocked by the three worker lanes.

## Worker PRs

| Worker | Candidate | PR | Head SHA | Verdict |
|---|---|---|---|---|
| A | grepai local Ollama | https://github.com/stars-end/agent-skills/pull/600 | 2297c76c8e7e9b82fef15baba9f84e0fd050a0bc | async/on-demand semantic enrichment only |
| B | CodeGraphContext | https://github.com/stars-end/agent-skills/pull/601 | 3105ede2de16b5e44ff7695d8b98de398239d2bc | complement llm-tldr structural |
| C | CocoIndex/cocoindex-code 0.2.31 `ccc` path | https://github.com/stars-end/agent-skills/pull/602 | 4d82a2862f5012dc532e2d3c400291706a2cf4b5 | reject tested path; rerun CocoIndex V1/latest |

## Evidence-Quality Review

### grepai

Evidence quality: mixed.

Good evidence:

- grepai 0.35.0 installed and initialized cleanly.
- `grepai init --provider ollama --model nomic-embed-text --backend gob --yes` created predictable config.
- Failure when Ollama is unavailable was fast and legible for `grepai watch`.
- State behavior was observed: `.grepai/config.yaml`, `index.gob`, and lock file in the worktree; logs under user state.

Evidence gap:

- The worker could not complete a successful local embedding/index/search benchmark because Ollama was unavailable and the official installer required non-interactive sudo.
- `grepai search --json` returned exit code 0 with a JSON error payload when Ollama was down.
- `grepai status --no-ui` exited successfully while reporting zero indexed files.

Coordinator action: requested one repair pass to either exercise a non-sudo local Ollama path or explicitly mark successful retrieval as blocked by host setup.

Conclusion supported by evidence: grepai is not ready for mandatory first-hop routing on unmanaged hosts. It remains plausible as explicit async/on-demand enrichment if a managed Ollama invariant exists.

### CodeGraphContext

Evidence quality: good, with one artifact repair requested.

Good evidence:

- CodeGraphContext 0.4.2 installed in a venv.
- Indexed `agent-skills` in about 27s and `affordabot` in about 114s.
- Demonstrated useful caller/callee results, including `apply_containment_patches` and Affordabot `process_raw_scrape`.
- Demonstrated complexity and dead-code sweeps.
- Confirmed no LLM, embedding, API key, or model-download dependency for runtime structural queries.

Limitations:

- CLI JSON output was not available through tested flags.
- Missing symbols and missing dependency info can exit 0.
- Import/dependency behavior was weak on `tldr_contained_runtime`.
- No equivalent to `llm-tldr context` compact call-neighborhood extraction.
- Default global state under `$HOME/.codegraphcontext` needs a wrapper or per-task `HOME` isolation.

Coordinator action: requested one repair pass because the memo's embedded PR head SHA did not match GitHub's PR head. Repair landed in PR #601 head `3105ede2de16b5e44ff7695d8b98de398239d2bc`.

Conclusion supported by evidence: CodeGraphContext is a good advisory structural tool, but not a default critical-path replacement.

### CocoIndex

Evidence quality: strong reject.

Good evidence:

- Installed `cocoindex-code 0.2.31`.
- `ccc init` completed.
- `ccc index` timed out at 120s.
- `ccc search` timed out at 120s.
- `ccc doctor` timed out while the daemon remained stuck indexing.
- `ccc status` showed partial progress: 91 of 373 files indexed, project still `indexing`.
- `.cocoindex_code/` appeared in the worktree as untracked state.

Conclusion supported by evidence: reject the tested `cocoindex-code 0.2.31 / ccc` path. Do not generalize that to CocoIndex V1/latest.

CocoIndex V1 was announced live on 2026-04-22. Its published design directly targets the failure class we saw: V1 replaces the prior engine-bookkeeping shape with embedded LMDB local state and a state-driven async Python model. The final bakeoff did not exercise that V1 path. A fair final rerun should use the latest documented V1/pre-release invocation or the current `cocoindex-code` path only if it is confirmed to be V1-backed.

## Lane Decisions

### Semantic Lane

Decision: **neither third-party candidate becomes default semantic replacement.**

| Option | Decision | Reason |
|---|---|---|
| `llm-tldr semantic` | remove from default | Common failure path adds cognitive load before `rg`. |
| grepai local Ollama | async/on-demand only | Needs managed Ollama/model/index readiness; zero-exit error payload is unsafe for automation. |
| CocoIndex 0.2.31 `ccc` path | reject | Index/search/doctor timed out and left daemon/index state behind. |
| CocoIndex V1/latest | rerun required | V1 is live and claims embedded LMDB local state, which directly addresses the observed daemon/state burden. |
| rg/direct reads | default | Fast, reliable, transparent, no hidden index. |

### Structural Lane

Decision: **do not replace structural default with CodeGraphContext yet.**

| Option | Decision | Reason |
|---|---|---|
| CodeGraphContext | advisory/complement only | Good callers/callees/dead-code/complexity, but no JSON and no compact context equivalent. |
| `llm-tldr structural` | demote to bounded optional commands | Some tools still work (`imports`, `calls`, `context`), but should not be mandatory first-hop. |
| rg/direct reads | default | Fastest and lowest operational ambiguity for most structural discovery. |
| serena | keep for symbol-aware edits | Editing/refactor surface, not broad discovery. |

## Critical-Path vs Async Classification

| Tool | Critical Path | Async/On-Demand | Notes |
|---|---|---|---|
| rg/fd/direct reads | yes | n/a | Default for repo discovery. |
| serena | yes for known-symbol edits | n/a | Keep as explicit symbol-aware edit lane. |
| llm-tldr semantic | no | no default | Remove from canonical first-hop. |
| llm-tldr structural | optional bounded | optional | Use only when command shape is known and timeout-wrapped. |
| grepai | no | possible after managed Ollama/index | Needs readiness wrapper and error-payload checks. |
| CodeGraphContext | no default | possible advisory structural | Needs state wrapper and machine-readable output before default automation. |
| CocoIndex 0.2.31 `ccc` path | no | no | Reject tested path. |
| CocoIndex V1/latest | no default yet | candidate for focused rerun | Must prove bounded index/search and clean state behavior in worktrees. |

## Cognitive-Load Comparison

| Route | Cognitive Load | Why |
|---|---|---|
| Current `llm-tldr semantic -> failure -> rg` | high | Agents must remember routing, fallback, index state, timeout semantics, and then still use `rg`. |
| grepai default | medium-high | Simpler CLI, but host service/model/index readiness must be known first. |
| CodeGraphContext default | medium | Commands are understandable, but state mode, graph DB, no JSON, and output parsing add burden. |
| CocoIndex 0.2.31 default | high | Daemon/indexing state and timeout behavior recreate the same problem. |
| CocoIndex V1/latest default | unknown | Not tested; V1 claims embedded LMDB local state and must be validated separately. |
| `rg`/direct reads default | low | Immediate, inspectable, deterministic. |

## Founder HITL-Load Comparison

| Route | Founder HITL Load | Why |
|---|---|---|
| Keep current llm-tldr default | high | Founder keeps seeing agents explain the same semantic-index failure. |
| Adopt grepai default now | medium-high | Requires Ollama install/service/model/index management on every relevant host. |
| Adopt CodeGraphContext default now | medium | Requires wrapper and agent retraining; automation is weakened by no JSON. |
| Adopt CocoIndex 0.2.31 `ccc` path | high | Requires monitoring stuck index/daemon state. |
| Adopt CocoIndex V1/latest | unknown | Potentially lower, but unproven in this bakeoff. |
| Remove llm-tldr from default first-hop | low | No new daemon, no new model, no new cloud path, no hidden readiness state. |

## Privacy, Cost, and Rate Limits

- `rg`, direct reads, serena, and CodeGraphContext local structural queries have no code egress or per-query cloud cost.
- grepai with local Ollama has no code egress at query time after model setup, but it adds host resource and model-management cost.
- grepai with OpenRouter/qwen remains acceptable only for explicit async/on-demand enrichment because every semantic query needs live cloud embedding.
- The tested CocoIndex 0.2.31 local mode avoids cloud egress, but its reliability failure dominates.
- CocoIndex V1/latest may reduce local state/daemon burden through embedded LMDB, but that was not measured in the worker lane.
- Any OpenRouter/qwen embedding path must avoid the default critical path unless a future managed index/search contract proves query latency, rate-limit behavior, and fallback semantics.

## Recommended Routing Contract Change

Replace the current `llm-tldr` tool-first discovery language with this contract:

```text
For repo discovery and "where does X live?":
  1. Use rg/fd/direct reads first.
  2. Use serena when the task is a known-symbol edit/refactor.
  3. Do not call llm-tldr semantic as a required first-hop.

For structural questions:
  1. Prefer direct reads and targeted rg.
  2. Use bounded llm-tldr structural commands only when the exact command is known to be useful.
  3. Treat CodeGraphContext as optional/advisory until a wrapper provides isolated state and machine-readable output.

For semantic enrichment:
  1. Use grepai only when explicitly requested or when a managed Ollama/index readiness check passes.
  2. Treat OpenRouter/qwen semantic enrichment as async/on-demand only.
  3. Reject the tested CocoIndex 0.2.31 `ccc` path.
  4. Re-run CocoIndex V1/latest before closing the semantic replacement search.
```

## Exact Next Steps

1. Open a routing-doc PR that removes `llm-tldr semantic` from mandatory first-hop discovery in AGENTS/baseline/skill docs.
2. Keep `serena` as the symbol-aware edit lane.
3. Add a short `rg`/direct-read first-hop contract for code discovery.
4. Keep `llm-tldr` structural commands only as bounded optional fallbacks, not canonical first-hop.
5. Run one focused grepai repair bakeoff after Ollama is installed and `nomic-embed-text` is pulled on the host.
6. Run one focused CocoIndex V1/latest bakeoff that confirms whether the CLI/MCP path is actually V1-backed and whether embedded LMDB state fixes the observed daemon/index hang.
7. Create a P2 follow-up for CodeGraphContext only if a wrapper can provide per-worktree state and machine-readable output.

## Final Answer

**ALL_IN_NOW:** remove `llm-tldr` from default first-hop routing.

Do not replace it with grepai, CodeGraphContext, or the tested CocoIndex 0.2.31 path today. The replacement for the default path is the simpler existing behavior agents already fall back to: `rg`, direct reads, and `serena` for symbol-aware edits.

Do not close the replacement search until two short repair reruns complete:

- grepai with Ollama already installed and `nomic-embed-text` available.
- CocoIndex V1/latest, explicitly verifying the embedded-LMDB state path.
