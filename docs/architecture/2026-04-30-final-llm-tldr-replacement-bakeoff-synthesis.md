# Final llm-tldr Replacement Bakeoff Synthesis

**Date:** 2026-04-30
**BEADS_EPIC:** bd-9n1t2.30
**BEADS_SUBTASK:** bd-9n1t2.30.4
**Feature-Key:** bd-9n1t2.30.4
**Mode:** synthesis

## Founder Decision

**Decision: ALL_IN_NOW for removing `llm-tldr` from default first-hop routing.**

This is not an all-in adoption of a third-party replacement. The final bakeoff did not produce a candidate that can replace the full `llm-tldr` surface today. The all-in action is the routing change: stop making agents try `llm-tldr semantic` before doing the reliable thing they already do after it fails.

Two repair reruns are now complete:

- grepai with local Ollama works when pre-warmed, but remains async/on-demand only because query latency is seconds, readiness is subtle, and empty indexes can produce successful empty JSON results.
- CocoIndex V1 framework works as an incremental LMDB-backed state engine, but should be deferred to P2+ because we would need to own the code-search harness, vector target, query API, readiness checks, and wrapper semantics.

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
    bd-9n1t2.30.3 CocoIndex V1 framework viability
    bd-9n1t2.30.4 Synthesis: final llm-tldr replacement bakeoff decision
```

`bd-9n1t2.30.4` is blocked by the three worker lanes.

## Worker PRs

| Worker | Candidate | PR | Head SHA | Verdict |
|---|---|---|---|---|
| A | grepai local Ollama | https://github.com/stars-end/agent-skills/pull/600 | 39abc6badb66296a483cc2859429276fee0dd1ec | async/on-demand semantic enrichment only |
| B | CodeGraphContext | https://github.com/stars-end/agent-skills/pull/601 | 3105ede2de16b5e44ff7695d8b98de398239d2bc | complement llm-tldr structural |
| C | CocoIndex V1 framework viability | https://github.com/stars-end/agent-skills/pull/604 | ffe855bde0e5f610fb088d10788178e9c2209f8f | defer CocoIndex V1 to P2+ |

## Evidence-Quality Review

### grepai

Evidence quality: adequate after repair rerun.

Good evidence:

- grepai 0.35.0 installed and initialized cleanly.
- `grepai init --provider ollama --model nomic-embed-text --backend gob --yes` created predictable config.
- Ollama 0.22.0 was active, and `nomic-embed-text:latest` was present.
- Warm index state was observed with 140 files, 798 chunks, and 4.8 MB index.
- Warm semantic search worked.
- Warm 10-query latency was about 5.15s p50 and 6.78s p95.
- State behavior was observed: `.grepai/config.yaml`, `index.gob`, and lock file in the worktree; logs under user state.

Limitations:

- `grepai status --no-ui` exits successfully while reporting zero indexed files.
- `grepai search --json` exits successfully with `[]` against an empty index after spending seconds on query embedding.
- Background/foreground watcher behavior is easy for agents to misread: a foreground watch is long-lived by design, and background readiness can time out while a watcher process remains.
- Incremental update behavior was not proven in the final bounded pass.

Coordinator action: installed and verified Ollama/model infra first, then dispatched a repair worker. The worker updated PR #600 at head `39abc6badb66296a483cc2859429276fee0dd1ec`. Coordinator stopped one stale watcher after worker shutdown.

Conclusion supported by evidence: grepai is useful as explicit async/on-demand semantic enrichment, but not as mandatory first-hop routing. A future wrapper would need to prove Ollama active, model present, nonzero index state, healthy watcher lifecycle, and non-empty/non-error payload semantics before agents wait on it.

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

### CocoIndex V1

Evidence quality: good for framework/substrate viability.

The prior Worker C evidence is superseded. It tested `cocoindex-code` / `ccc`, which is no longer part of the candidate set and was uninstalled before the V1 rerun. That evidence may explain why the CLI surface was confusing, but it does not drive the CocoIndex V1 decision.

The V1 rerun in PR #604 tested `cocoindex>=1.0.0` only.

- `uvx --from 'cocoindex>=1.0.0' cocoindex --version` reports `cocoindex version 1.0.2`.
- `ccc` was absent, as intended.
- A minimal V1 app used `COCOINDEX_DB=./cocoindex.db`.
- `agent-skills` initial update processed 861 files in about 31.4s shell time; a no-change second update still took about 17.9s while reporting 861 unchanged; a one-file incremental change took about 17.2s while reporting 1 reprocessed and 860 unchanged.
- `affordabot` initial update processed 1686 files in about 49.4s; a no-change second update took about 27.4s; a one-file incremental change took about 23.6s.
- Local LMDB/framework state was cleanly local and daemon-free.
- The framework did not provide a ready semantic query product surface; the worker had to build a minimal file-processing harness and use `rg` over emitted JSON records.
- A bad harness bug (`AttributeError`) produced component errors while the process exited 0, so a production wrapper must parse update output or a structured status surface.

Conclusion supported by evidence: CocoIndex V1 is viable as a future first-party incremental index substrate, but not a near-term `llm-tldr` replacement. Defer to P2+ unless the product goal becomes owning a local code-index/search harness.

## Lane Decisions

### Semantic Lane

Decision: **neither third-party candidate becomes default semantic replacement.**

| Option | Decision | Reason |
|---|---|---|
| `llm-tldr semantic` | remove from default | Common failure path adds cognitive load before `rg`. |
| grepai local Ollama | async/on-demand only | Works when warm, but seconds-level query latency and readiness semantics are unsafe for mandatory first-hop. |
| CocoIndex V1 framework | defer to P2+ | Framework works, but near-term usefulness requires owning a code-search/vector/query harness. |
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
| grepai | no | yes, explicit only | Works for warm local semantic enrichment, but agents should not wait on it by default. |
| CodeGraphContext | no default | possible advisory structural | Needs state wrapper and machine-readable output before default automation. |
| CocoIndex V1 framework | no | P2+ substrate | Framework state works, but no ready semantic product surface. |

## Cognitive-Load Comparison

| Route | Cognitive Load | Why |
|---|---|---|
| Current `llm-tldr semantic -> failure -> rg` | high | Agents must remember routing, fallback, index state, timeout semantics, and then still use `rg`. |
| grepai default | medium-high | Simpler CLI, but host service/model/index readiness and empty-success handling must be known first. |
| CodeGraphContext default | medium | Commands are understandable, but state mode, graph DB, no JSON, and output parsing add burden. |
| CocoIndex V1 framework default | high | App/update path works, but agents would need a first-party harness and wrapper before it helps discovery. |
| `rg`/direct reads default | low | Immediate, inspectable, deterministic. |

## Founder HITL-Load Comparison

| Route | Founder HITL Load | Why |
|---|---|---|
| Keep current llm-tldr default | high | Founder keeps seeing agents explain the same semantic-index failure. |
| Adopt grepai default now | medium-high | Requires Ollama install/service/model/index management plus readiness wrapper review. |
| Adopt CodeGraphContext default now | medium | Requires wrapper and agent retraining; automation is weakened by no JSON. |
| Adopt CocoIndex V1 framework | high now | Requires architecture and maintenance of a first-party code-search/vector/query harness. |
| Remove llm-tldr from default first-hop | low | No new daemon, no new model, no new cloud path, no hidden readiness state. |

## Privacy, Cost, and Rate Limits

- `rg`, direct reads, serena, and CodeGraphContext local structural queries have no code egress or per-query cloud cost.
- grepai with local Ollama has no code egress at query time after model setup, but it adds host resource and model-management cost; observed local query latency was seconds, not subsecond.
- grepai with OpenRouter/qwen remains acceptable only for explicit async/on-demand enrichment because every semantic query needs live cloud embedding.
- CocoIndex V1 local framework use can avoid cloud egress if paired with local embeddings, but we would own the semantic harness, vector target choice, and query surface.
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
  3. Treat CocoIndex V1 as a P2+ substrate candidate only; do not use `cocoindex-code` / `ccc`.
```

## Exact Next Steps

1. Open a routing-doc PR that removes `llm-tldr semantic` from mandatory first-hop discovery in AGENTS/baseline/skill docs.
2. Keep `serena` as the symbol-aware edit lane.
3. Add a short `rg`/direct-read first-hop contract for code discovery.
4. Keep `llm-tldr` structural commands only as bounded optional fallbacks, not canonical first-hop.
5. Create a P2 follow-up for a grepai readiness wrapper only if semantic enrichment remains valuable after routing cleanup.
6. Create a P2+ follow-up for CocoIndex V1 only if we explicitly want to own a first-party local code-index/search harness.
7. Create a P2 follow-up for CodeGraphContext only if a wrapper can provide per-worktree state and machine-readable output.

## Final Answer

**ALL_IN_NOW:** remove `llm-tldr` from default first-hop routing.

Do not replace it with grepai, CodeGraphContext, or CocoIndex V1 today. The replacement for the default path is the simpler existing behavior agents already fall back to: `rg`, direct reads, and `serena` for symbol-aware edits.

The two repair reruns are complete. For P0/P1 purposes, close the replacement search: no evaluated tool should replace `llm-tldr semantic` as default first-hop. Keep grepai, CocoIndex V1, and CodeGraphContext as P2+ optional lanes only if a later implementation plan shows they reduce, rather than increase, operational burden.
