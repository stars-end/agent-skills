# llm-tldr Two-Lane Spike Coordination Plan

Date: 2026-04-27
Beads epic: bd-9n1t2
Coordinator subtask: bd-9n1t2.17
Synthesis subtask: bd-9n1t2.20
Class: product

## Goal

Oversee two parallel replacement spikes for `llm-tldr` and produce one founder decision:

- `ALL_IN_NOW`
- `DEFER_TO_P2_PLUS`
- `CLOSE_AS_NOT_WORTH_IT`

The decision must optimize agent cognitive load and founder HITL load. Cloud embeddings are acceptable only for async, hourly, or explicit on-demand enrichment unless measured query-time reliability and latency are outstanding.

## Prior Art Read

Required refs were fetched before worktree creation:

- PR #592: `e1476ae9e1a0a007ce77916ac60fc47367203c7b`
- PR #593: `79774cec2db1f337f54f10b3da0e9ddd95a831b3`
- PR #594: `d662dcabe0710860bbd9c1b42a0a35aa83d165c8`

Required file availability:

| File | PR #592 | PR #593 | PR #594 |
|---|---:|---:|---:|
| `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md` | missing | present | present |
| `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md` | missing | present | present |
| `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md` | missing | present | present |
| `extended/llm-tldr/SKILL.md` | present | present | present |
| `fragments/dx-global-constraints.md` | present | present | present |
| `scripts/tldr_contained_runtime.py` | present | present | present |
| `scripts/tldr-daemon-fallback.sh` | present | present | present |

Key prior-art takeaways:

- PR #592 hardens semantic mixed-health behavior: semantic-only stalls should not be treated as full MCP hydration failure; bounded fallback and explicit semantic prewarm are preferred.
- PR #593 is a weaker competitor bakeoff and recommends a narrower grepai spike.
- PR #594 is the primary runtime-grounded bakeoff: keep `llm-tldr` canonical for now, use grepai and CodeGraphContext as P2 augmentation candidates, and do not accept replacement claims without runtime evidence.

## Beads Graph

```text
bd-9n1t2: CLI-only agent tooling stack decision memos
  bd-9n1t2.16: Bakeoff: llm-tldr replacement candidates on real agent workflows
  bd-9n1t2.17: Tech lead: oversee parallel llm-tldr replacement spikes
  bd-9n1t2.18: Spike B: CodeGraphContext deterministic structural analysis
  bd-9n1t2.19: Spike A: grepai OpenRouter Qwen embeddings for semantic analysis
  bd-9n1t2.20: Synthesis: llm-tldr replacement spike decision memo
```

Dependency rules verified:

- `bd-9n1t2.17` depends on `bd-9n1t2.16`
- `bd-9n1t2.18` depends on `bd-9n1t2.17`
- `bd-9n1t2.19` depends on `bd-9n1t2.17`
- `bd-9n1t2.20` depends on `bd-9n1t2.18` and `bd-9n1t2.19`

## Memory Lookup

Targeted memory lookups before dispatch returned no relevant records:

- `bdx memories llm-tldr --json` -> `{}`
- `bdx memories grepai --json` -> `{}`
- `bdx memories CodeGraphContext --json` -> `{}`
- `bdx memories OpenRouter --json` -> `{}`
- `bdx search "llm-tldr" --label memory --status all --json` -> `[]`
- `bdx search "semantic mixed-health" --label memory --status all --json` -> `[]`
- `bdx search "OpenRouter" --label memory --status all --json` -> `[]`
- `bdx search "CodeGraphContext" --label memory --status all --json` -> `[]`

## Worker Lanes

Worker A:

- Beads subtask: `bd-9n1t2.19`
- Model: `gpt-5.3-codex`
- File: `docs/investigations/2026-04-27-worker-a-grepai-openrouter-prompt.md`
- Output memo: `docs/architecture/2026-04-27-grepai-openrouter-semantic-spike.md`
- Required verdict: replace `llm-tldr` semantic, async/on-demand enrichment only, or reject

Worker B:

- Beads subtask: `bd-9n1t2.18`
- Model: `gpt-5.3-codex`
- File: `docs/investigations/2026-04-27-worker-b-codegraphcontext-prompt.md`
- Output memo: `docs/architecture/2026-04-27-codegraphcontext-structural-spike.md`
- Required verdict: replace `llm-tldr` structural, complement `llm-tldr` structural, or reject

## Review Gate

Ask a worker for one repair pass if any of these are true:

- Required memo is missing.
- Draft PR URL or 40-character head SHA is missing.
- Required repos are skipped without a clear blocker.
- Commands are summarized without exact invocations.
- Timing evidence is absent or not separated by index/build/query phases.
- grepai evidence does not distinguish indexing latency, incremental latency, live query embedding latency, and retrieval latency.
- grepai claims critical-path suitability without outstanding measured query-time latency and reliability.
- CodeGraphContext evidence does not establish whether it uses live LLM/embedding calls in the critical path.
- CodeGraphContext claims replacement while omitting callers/callees/class/dead-code/complexity coverage.
- Failure behavior, state/worktree behavior, agent cognitive load, or founder HITL load is missing.

## Synthesis Requirements

Create `docs/architecture/2026-04-27-llm-tldr-two-lane-spike-synthesis.md` after both worker results arrive or one worker is formally blocked.

The synthesis must include:

- Problem statement
- Prior-art summary from PRs #592, #593, and #594
- Beads dependency graph
- Worker PR links and head SHAs
- Evidence-quality review for each worker
- Semantic lane decision
- Structural lane decision
- Critical-path vs async/on-demand classification
- Agent cognitive-load comparison
- Founder HITL-load comparison
- Privacy, cost, and rate-limit assessment
- Recommended routing contract change, if any
- Explicit founder decision
- Exact next steps

## Validation

Before final response:

```bash
~/agent-skills/scripts/dx-verify-clean.sh
```

Report the result exactly.
