# llm-tldr Two-Lane Spike Synthesis

Date: 2026-04-27  
Beads epic: `bd-9n1t2`  
Coordinator subtask: `bd-9n1t2.17`  
Synthesis subtask: `bd-9n1t2.20`  
Coordinator PR: https://github.com/stars-end/agent-skills/pull/595

## Problem Statement

`llm-tldr` is still the canonical V8.6 first-hop analysis tool for semantic discovery, structural trace, low-token context extraction, and change-impact targeting. Prior runtime evidence showed material reliability risk: semantic MCP timeouts, mixed-health behavior where non-semantic tools can work while semantic stalls, and agent confusion across MCP, daemon fallback, contained CLI, and direct `rg`/file-read recovery.

The founder constraint is decisive: cloud LLM or embedding usage is acceptable for async, hourly, or explicit on-demand enrichment, but not as mandatory critical-path lookup if agents must wait on it. This spike tests whether the current `llm-tldr` contract should remain canonical, be demoted, or split into narrower duties.

## Prior Art Summary

Prior-art refs were fetched before coordination worktree creation:

| PR | Head SHA | Purpose | Synthesis Use |
|---|---|---|---|
| #592 | `e1476ae9e1a0a007ce77916ac60fc47367203c7b` | Semantic mixed-health hardening | Establishes bounded fallback and explicit prewarm as the current `llm-tldr` recovery contract |
| #593 | `79774cec2db1f337f54f10b3da0e9ddd95a831b3` | Prior competitor bakeoff | Weaker contrast; recommended narrower grepai spike |
| #594 | `d662dcabe0710860bbd9c1b42a0a35aa83d165c8` | Runtime-grounded competitor bakeoff | Primary prior-art memo; recommended keeping `llm-tldr` canonical while evaluating grepai and CodeGraphContext as P2 augmentation |

Required files missing from PR #592:

- `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`
- `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`
- `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md`

All other required runtime and skill files were present in PR #592. PRs #593 and #594 had all required paths.

Key prior-art conclusions:

- `llm-tldr` remains the only incumbent covering semantic search, structural trace, imports/impact, and context extraction in one contract.
- The current risk is not just tool failure; it is agent cognitive load from multi-surface recovery and ambiguous mixed-health states.
- No prior candidate clearly replaced the full `llm-tldr` surface.
- CodeGraphContext looked promising as a deterministic structural complement.
- grepai required a narrower benchmark because previous evidence did not test OpenRouter Qwen embeddings.

## Beads Dependency Graph

```text
bd-9n1t2: CLI-only agent tooling stack decision memos
  bd-9n1t2.16: Bakeoff: llm-tldr replacement candidates on real agent workflows
  bd-9n1t2.17: Tech lead: oversee parallel llm-tldr replacement spikes
  bd-9n1t2.18: Spike B: CodeGraphContext deterministic structural analysis
  bd-9n1t2.19: Spike A: grepai OpenRouter Qwen embeddings for semantic analysis
  bd-9n1t2.20: Synthesis: llm-tldr replacement spike decision memo
```

Verified dependency rules:

- `bd-9n1t2.17` depends on `bd-9n1t2.16`
- `bd-9n1t2.18` depends on `bd-9n1t2.17`
- `bd-9n1t2.19` depends on `bd-9n1t2.17`
- `bd-9n1t2.20` depends on `bd-9n1t2.18` and `bd-9n1t2.19`

## Worker Results

| Lane | Beads ID | PR | Head SHA | Result |
|---|---|---|---|---|
| Semantic: grepai + OpenRouter Qwen embeddings | `bd-9n1t2.19` | none | none | `BLOCKED: secret_auth_cache_unavailable` |
| Structural: CodeGraphContext | `bd-9n1t2.18` | https://github.com/stars-end/agent-skills/pull/596 | `87848bb595d15c6b8d437165b6649962b6db4508` | Draft PR returned; evidence supports complement, not replacement |

## Evidence-Quality Review

### Worker A: grepai + OpenRouter

Worker A reached the required hard blocker:

```text
BLOCKED: secret_auth_cache_unavailable
```

This is a valid formal block under the assignment because the worker was required to fail closed if cached/service-account access to the OpenRouter secret was unavailable and was forbidden from falling back to GUI-backed 1Password or raw `op` commands.

Evidence quality:

- No runtime semantic benchmark evidence was produced.
- No Worker A PR exists.
- No conclusion about grepai/OpenRouter replacement fitness can be drawn from this lane.

Decision implication:

- Cloud embedding as a semantic lane remains unproven.
- Because auth setup itself blocked the worker under normal agent-safe constraints, grepai + OpenRouter cannot be promoted into the default critical-path lookup loop now.

### Worker B: CodeGraphContext

Worker B created a draft PR and memo with command-level evidence across `agent-skills` and `affordabot`.

Evidence strengths:

- Exact setup and benchmark commands are listed.
- Two real repos were indexed.
- Install and index timings were recorded.
- Query latencies were measured for callers, callees, dead code, complexity, and content search.
- State behavior was tested in global and per-repo modes.
- Bounded `llm-tldr` structural comparisons were run where feasible, with actual command-shape corrections documented.
- No-LLM critical-path assessment is grounded in docs, dependencies, local package grep, and measured local query latency.

Evidence limitations:

- `--json` was not supported for tested `cgc analyze` flows, which increases wrapper/parsing burden.
- Dependency/import relationship queries were weak in this run.
- Global mode can hide index-boundary mistakes by returning misses instead of explicit "repo not indexed" errors.
- Per-repo mode creates `.codegraphcontext` and `.cgcignore` in the worktree, which needs containment policy if used.
- The worker memo includes an embedded PR head SHA, but the live PR `headRefOid` is authoritative because a commit cannot reliably embed its own final SHA without changing that SHA. Authoritative Worker B head: `87848bb595d15c6b8d437165b6649962b6db4508`.

Evidence-quality verdict:

- Sufficient to classify CodeGraphContext as a promising structural complement.
- Not sufficient to replace `llm-tldr` structural/context routing now.

## Semantic Lane Decision

Decision: keep `llm-tldr` semantic as the incumbent bounded lane; do not adopt grepai + OpenRouter as default.

Rationale:

- The grepai/OpenRouter worker could not reach runtime benchmarking because agent-safe secret auth was unavailable.
- OpenRouter embedding usage would necessarily put live cloud embedding in the query path unless grepai has a separate local query-vector cache strategy, which was not proven.
- The founder constraint rules out mandatory cloud query embedding in the critical path without outstanding measured latency and reliability.

Allowed future shape:

- grepai + OpenRouter may be re-spiked as async/on-demand semantic enrichment after agent-safe secret auth works and after measurement separates indexing calls, incremental indexing calls, live query embedding, and retrieval latency.

## Structural Lane Decision

Decision: classify CodeGraphContext as a structural complement, not a replacement.

Rationale:

- It appears deterministic and local in the tested query path.
- It was fast for caller/callee/dead-code/complexity queries after indexing.
- It can reduce agent wait time for some structural questions versus `llm-tldr context`.
- It does not yet replace the existing `llm-tldr` structural contract because JSON output is missing in tested flows, dependency/import behavior was weak, and state mode policy is unresolved.

## Critical Path vs Async/On-Demand

| Use Case | Recommended Lane | Classification |
|---|---|---|
| Fast lexical lookup | `rg`, direct file reads | Critical path |
| Existing bounded structural/context lookup | `llm-tldr` non-semantic tools with timeout fallback | Critical path |
| Semantic mixed-health recovery | PR #592 bounded fallback/prewarm rule | Critical path recovery |
| CodeGraphContext callers/callees/dead-code/complexity | Optional structural complement after explicit index | Critical path candidate, not default |
| grepai + OpenRouter semantic search | Not adopted | Async/on-demand candidate only |
| Cloud query embeddings | Not adopted | Not critical path |

## Cognitive-Load Comparison

| Lane | Agent Cognitive Load | Founder HITL Load |
|---|---|---|
| Current `llm-tldr` bounded contract | Medium-high: MCP/fallback/prewarm concepts remain, but PR #592 improves mixed-health handling | Medium: prewarm and MCP health remain operational concerns |
| grepai + OpenRouter | Unknown-to-high: auth/provider setup blocked; query-time cloud embeddings add failure and cost questions | High until agent-safe secret auth and rate/cost observability are proven |
| CodeGraphContext | Medium: simple structural CLI, but state mode and missing JSON output add wrapper/policy burden | Medium: requires index/state policy and possibly wrappers before default routing |

## Privacy, Cost, and Rate-Limit Assessment

grepai + OpenRouter:

- Privacy/IP egress risk remains unresolved because no runtime benchmark completed.
- Cost estimate remains unresolved because embedding call counts were not observable in a completed run.
- Rate-limit behavior remains unresolved.
- Agent-safe auth was unavailable, which is itself a blocker for autonomous default usage.

CodeGraphContext:

- No live LLM/embedding calls were observed or implied by the tested structural path.
- Privacy risk is low for local graph queries.
- Cost risk is low after local install, bounded primarily by local CPU/disk/indexing time.
- Rate-limit risk is not applicable for tested local structural queries.

## Recommended Routing Contract Change

Do not make an immediate global routing change.

Recommended near-term contract:

1. Keep current `llm-tldr` routing as canonical.
2. Preserve PR #592 semantic mixed-health rule:
   - semantic-only stalls are semantic degradation, not full MCP hydration failure
   - use one bounded fallback/prewarm attempt
   - then fall back to targeted `rg` or direct reads and report the routing exception
3. Add CodeGraphContext only as an explicit optional structural probe for:
   - callers
   - callees
   - dead-code
   - complexity
4. Do not require agents to use CodeGraphContext by default until:
   - JSON or machine-readable output is available through a wrapper or upstream flag
   - global vs per-repo state policy is fixed
   - index-boundary misses fail legibly
5. Re-run grepai/OpenRouter only after `OPENROUTER_API_KEY` is available through agent-safe cache/service-account auth.

## Founder Decision

`DEFER_TO_P2_PLUS`

Why:

- No candidate can replace a meaningful `llm-tldr` lane now without adding unresolved operational burden.
- grepai + OpenRouter is blocked at agent-safe auth and unmeasured on the decisive latency/cost/privacy axes.
- CodeGraphContext is promising and local, but currently complements structural analysis rather than replacing the canonical surface.
- An `ALL_IN_NOW` cutover would create a dual-tool/default-tool ambiguity and likely increase founder/agent monitoring.
- `CLOSE_AS_NOT_WORTH_IT` would ignore useful CodeGraphContext evidence and the unresolved but still plausible async semantic enrichment lane.

## Exact Next Steps

1. Fix OpenRouter agent-safe secret availability or intentionally close `bd-9n1t2.19` as blocked.
2. If auth is fixed, re-dispatch Worker A with the same grepai prompt and require the same latency/call-count separation.
3. Create a P2 CodeGraphContext wrapper/design note only if the team wants to pursue structural complement:
   - choose global mode or contained external state
   - add machine-readable output or parser
   - add an "unindexed repo" legibility check
4. Keep current `llm-tldr` canonical routing and PR #592 mixed-health recovery as the default until a candidate proves lower cognitive load with equal or better coverage.
