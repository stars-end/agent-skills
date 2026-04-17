# OpenCode MCP Tool-First Routing Conformance Pilot

**Date**: 2026-03-29 (rerun after PR #426)
**Runtime**: OpenCode (glm-5-turbo via `opencode`)
**Epic**: bd-rb0c
**Subtask**: bd-8zzt
**Mode**: qa_pass

## Merged Source Revisions

| Repo | Merge Commit | PR |
|------|-------------|-----|
| agent-skills | `2162e21239d4b96a9d90631822c2144ae5c3abca` | [#426](https://github.com/stars-end/agent-skills/pull/426) + [#427](https://github.com/stars-end/agent-skills/pull/427) |
| prime-radiant-ai | `e1320248370ac4db9e810e22096d9beef26c9bbb` | [#1027](https://github.com/stars-end/prime-radiant-ai/pull/1027) |

## What Changed After PR #426

PR #426 (`bd-rb0c.7`) migrated the semantic discovery lane from `context-plus` to `llm-tldr` in the V8.6 routing contract. Key changes:

1. **AGENTS.md section 5.4**: `llm-tldr` is now the canonical default for both semantic discovery and exact static analysis. `context-plus` is demoted to experimental/optional.
2. **llm-tldr SKILL.md**: New "Semantic discovery" trigger contract added, covering "where does X live?" queries previously routed to `context-plus`.
3. **context-plus SKILL.md**: Demoted to experimental/optional with no required trigger contract.
4. **Routing matrix**: All semantic-discovery task shapes now point to `llm-tldr`.

This means the prior pilot's CP1/CP2 expected-tool column (`context-plus`) is stale under V8.6. The rerun uses the updated expectations.

## Why the Pre-PR-426 OpenCode Result Was Stale

The original pilot (2026-03-28) tested under the V8.5 contract where CP1/CP2 expected `context-plus`. That result is now **partially stale**:

- **Stale**: CP1's `RUNTIME FAIL` verdict. The timeout was a `context-plus` cold-start issue (wrong MCP root dir + V1 cache rejection). With `llm-tldr` as the canonical semantic lane, this failure mode no longer applies. The CP1 case itself is valid, but the expected tool changed.
- **Stale**: CP2's result was a `PASS` for `context-plus`, but under V8.6 the expected tool is `llm-tldr`. The prior result does not prove V8.6 compliance.
- **Not stale**: LT1, LT2, SE1, SE2 results remain valid — their expected tools did not change.

## Commands Run

```bash
cd ~/agent-skills && git fetch origin
cd ~/agent-skills && git checkout pr-411 -- docs/investigations/2026-03-28-opencode-tool-routing-conformance-pilot.md
cd ~/agent-skills && git checkout origin/master  # 2162e21
cd ~/prime-radiant-ai && git fetch origin && git checkout e1320248370ac4db9e810e22096d9beef26c9bbb --detach
dx-worktree create bd-8zzt agent-skills  # /tmp/agents/bd-8zzt/agent-skills
dx-worktree create bd-8zzt prime-radiant-ai  # /tmp/agents/bd-8zzt/prime-radiant-ai
opencode mcp list  # 7 servers: llm-tldr, serena, context-plus (+ 4 context-plus repo instances)
tldr warm /tmp/agents/bd-8zzt/prime-radiant-ai  # 938 files, 3130 edges
tldr semantic index /tmp/agents/bd-8zzt/prime-radiant-ai  # 3883 code units (FAISS)
```

## Preflight Validation

- `llm-tldr`: connected
- `serena`: connected
- `context-plus`: present but not required for default compliance under V8.6
- `tldr warm`: 938 files indexed, 3130 edges
- `tldr semantic index`: 3883 code units indexed for FAISS search
- prime-radiant-ai worktree HEAD: `0cec76fce95d9b2a289b9f94ff8d9022c28c92e9`

## Results (V8.6 Rerun)

| Case | Expected | First Tool Used | Verdict | Note | Vs Prior OpenCode |
|------|----------|-----------------|---------|------|-------------------|
| CP1 | llm-tldr | llm-tldr (semantic) | PASS | 10 results, scores 0.69-0.76; correct repo targeting via per-call project param | stale prior failure removed |
| CP2 | llm-tldr | llm-tldr (semantic) | PASS | 10 results, scores 0.66-0.70; artifact/chart/metrics mapping clear | better |
| LT1 | llm-tldr | llm-tldr (extract) | PASS | Full call graph + 21 functions extracted for chartSpecToRecharts | same |
| LT2 | llm-tldr | llm-tldr (impact + importers) | PASS | Zero callers via both impact and importer search; module-contained | same |
| SE1 | serena | serena (find_symbol + find_referencing_symbols) | PASS | Definition at line 525; zero refs (incomplete TS index) | same |
| SE2 | serena | serena (find_symbol) | PASS | Definition at lines 3-49; insertion point clear | same |

## Compliance Summary

- **Overall rate**: 6/6 = 100%
- **PASS**: 6
- **RUNTIME FAIL**: 0
- **FAIL**: 0
- **SOFT PASS**: 0
- **Tool routing exceptions used**: 0

## Comparison vs Prior OpenCode Artifact (PR #411)

| Metric | Prior (Pre-PR-426) | Current (Post-PR-426) | Change |
|--------|--------------------|-----------------------|--------|
| Routing compliance | 5/6 (83%) | 6/6 (100%) | +1 |
| Runtime success | 5/6 (83%) | 6/6 (100%) | +1 |
| Context-plus failures | 1 (timeout) | 0 | eliminated |
| llm-tldr semantic usage | 0 | 2 (CP1, CP2) | new lane |
| Serena compliance | 2/2 | 2/2 | unchanged |

## Key Findings

### PR #426 materially removed the old OpenCode semantic-lane drift

Yes. The CP1 `RUNTIME FAIL` (context-plus timeout) is eliminated because `llm-tldr` is now the canonical semantic tool. The root causes identified in the prior pilot (wrong MCP root dir, V1 cache rejection) no longer apply to the semantic discovery lane.

### Prior context-plus runtime conclusions are stale under V8.6

Yes. The prior pilot's context-plus analysis (wrong root dir, V1 cache discard, cold-start timeout) describes a failure mode that no longer blocks the default semantic lane. `context-plus` is now experimental/optional. The failure analysis is retained for historical reference but does not represent current system risk.

### llm-tldr per-call project parameter eliminates cross-repo confusion

The prior CP1 failure was partly caused by `context-plus` locking its root to `process.cwd()` at startup. `llm-tldr` accepts a `project` parameter on every MCP call, so cross-repo queries correctly target the intended repo without CWD coupling.

### Serena TypeScript index still incomplete

SE1 continues to show zero referencing symbols for `chartSpecToRecharts`, consistent with the prior run. This is a Serena index coverage limitation, not a routing failure. The symbol definition is correctly found.

## dx-verify-clean.sh Status

Noted: script may report FAIL due to pre-existing `.tldr/` and `.tldrignore` artifacts in canonical clones (from `tldr warm` runs). These are llm-tldr index files, not task dirt.

## Recommendation

**Advance to Codex comparison.**

Rationale:
- 6/6 cases passed with correct first-tool routing under V8.6
- 0 runtime failures (the prior CP1 timeout failure mode is eliminated by the routing change)
- 0 tool routing exceptions
- `llm-tldr` semantic search works reliably with per-call project targeting
- `serena` symbol-aware operations remain stable
- The old context-plus semantic-lane failure framing is stale and should not be carried into the Codex comparison
- The Codex comparison should test the same 6 cases under V8.6 expectations (llm-tldr for CP1/CP2/LT1/LT2, serena for SE1/SE2)
