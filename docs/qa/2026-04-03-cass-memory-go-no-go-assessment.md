# CASS Memory Cross-Agent / Cross-Repo Value Assessment

- Date: 2026-04-03
- CLASS: dx_loop_control_plane
- NOT_A_PRODUCT_BUG: true
- Source of truth repaired pilot PR: [#464](https://github.com/stars-end/agent-skills/pull/464)
- Pilot PR head SHA: `3f643876d448c2f67b41f0f7e1ae615ca889e97a`

## Summary Verdict

Verdict: **go-with-caveats for a bounded DX pilot; no-go as a default replacement for `llm-tldr` + `serena`.**

Reasoning:
1. The pilot is useful for recurring operational playbooks that cross agents, repos, and VMs.
2. The value is real when the same recovery pattern keeps reappearing in different contexts.
3. It overlaps with existing docs/runbooks for stable procedures and with `serena` for continuity, so it should stay narrow.
4. The current package is usable, but still assumes operator discipline and light setup maintenance.

## What We Tested

### Upstream contract review

Inspected upstream `cass_memory_system` docs first, starting with:
- `README.md`
- `docs/AGENT_NATIVE_ONBOARDING.md`

Relevant upstream behaviors:
- `cm context "<task>" --json` is the primary agent read path.
- `cm playbook add` stores procedural rules.
- `cm playbook list` inspects stored rules.
- `cm doctor --json` / `cm doctor --fix --no-interactive` handles setup drift.
- `cm privacy status|enable|disable` controls cross-agent enrichment.

### Repaired pilot package review

Reviewed the repaired pilot starter package in PR 464:
- `docs/specs/2026-04-03-cass-memory-cross-vm-dx-pilot.md`
- `docs/runbook/cass-memory-pilot-quickstart.md`
- `docs/runbook/cass-memory-pilot-example-entries.md`
- `templates/cass-memory-pilot-entry-template.md`
- `templates/cass-memory-pilot-reuse-log-template.csv`
- `extended/cass-memory/SKILL.md`

### QA evidence sources

Two focused QA lanes were executed against the repaired package:
- CLI/runtime lane: PR [#465](https://github.com/stars-end/agent-skills/pull/465)
- `opencode` agent-use lane: PR [#466](https://github.com/stars-end/agent-skills/pull/466)

## Concrete Advantages

1. Cross-agent procedural memory is valuable for repeated DX/control-plane incidents.
- Examples that benefited from shared playbooks:
  - MCP context EOF / empty-response recovery
  - fleet audit / host-drift remediation
  - Railway deploy-truth verification
  - Beads/Dolt recovery patterns
- These are exactly the sorts of incidents that recur across agents and repos.

2. It can reduce repeated rediscovery across hosts and sessions.
- A playbook discovered on one VM can be reused on another VM without rebuilding context.
- This matters when the same operational trick is needed in multiple canonical repos.

3. It is more specific than `serena`.
- `serena` is good for continuity and symbol-aware memory.
- `cass-memory` is better suited to distilled operational rules and cross-agent recovery bullets.
- That makes it useful for "what worked last time" knowledge that is not symbol-bound.

4. It can span multiple repos without being repo-specific.
- Useful when the same operational pattern applies to `agent-skills`, `prime-radiant-ai`, `affordabot`, and `llm-common`.
- That is hard to capture cleanly in a single repo-local runbook.

5. It is a better fit for procedural knowledge than raw chat history.
- The pilot templates push toward sanitized, actionable summaries.
- That is better than relying on transient thread memory or raw transcripts.

## Concrete Limits / Risks

1. It overlaps with existing runbooks and `serena`.
- Stable procedures can already live in repo docs.
- Assistant continuity and project memory already live in `serena`.
- `cass-memory` only adds value when the same procedural rule is reused repeatedly across contexts.

2. It is not turnkey without guidance.
- The repaired starter package is usable, but it still assumes a human/agent can initialize or repair local state.
- The pilot needs explicit `cm doctor` guidance and a clear retrieval path.

3. Retrieval tuning matters.
- Default similarity search can appear empty or noisy if the operator does not tune it.
- `cm context` is the better default read path for actual agent use.

4. Privacy discipline is required.
- The value proposition only holds if entries stay sanitized and procedural.
- Raw logs, secrets, cookies, and transcripts would defeat the purpose.

5. Cross-agent and cross-repo sharing should remain opt-in.
- That is a strength for safety, but it also means the system will be underused if it is not easy to adopt.

## Where It Adds Value

Best-fit workflows:
1. Repeated operational recovery patterns.
2. Multi-VM fleet repair playbooks.
3. Railway deploy-truth / live identity verification.
4. MCP and agent-runtime failure recovery.
5. Shared "what worked" notes that are not tied to one repo or symbol.

Most valuable when:
- the problem has already occurred more than once
- the fix is procedural, not architectural
- the lesson should travel across repos/hosts/agents
- the entry can be sanitized into a compact playbook bullet

## Where It Overlaps Instead of Adding Value

1. `llm-tldr`
- Better for repo discovery, static analysis, call graphs, and code-path tracing.
- If the task is "find the code," `cass-memory` should not be in the loop.

2. `serena`
- Better for symbol-aware continuity, project memory, and targeted edits.
- If the task is "remember this symbol or edit safely," `serena` is the default memory surface.

3. Repo docs / runbooks
- For stable procedures that do not need cross-agent learning, docs are simpler and lower risk.
- `cass-memory` should not replace a normal runbook.

## QA Evidence Summary

From the repaired pilot package and QA runs:
- `cm --version` passed.
- `cm quickstart --json` passed.
- `cm doctor --json` can report degraded setup, which means the quickstart must mention the recovery path.
- `cm context` is the right default read path.
- `cm playbook add` / `cm playbook list` are the current write/inspect surfaces.
- `cm similar` is useful, but `cm context` is the safer default when operators want the most directly usable result.
- `opencode` can read the repaired package and reason over it as an agent surface.

## Decision

### Verdict

**Go-with-caveats** for a bounded pilot.

### Interpretation

- **Go** for a narrow DX/control-plane pilot that captures sanitized procedural playbooks.
- **No-go** for making `cass-memory` the default memory layer for agents.
- **No-go** for replacing `llm-tldr` or `serena`.

### Why

The evidence says the tool is worth trying where repeated operational tricks are the real problem. It is not a broad replacement for discovery, continuity, or runbooks, and the operational guardrails need to stay explicit.

## Recommended Next Step

1. Keep the pilot bounded to DX/control-plane incidents only.
2. Use `cm context` as the default retrieval path.
3. Record only sanitized procedural bullets with links back to the source incident or PR.
4. Measure whether reused playbooks actually reduce repeated rediscovery across agents/VMs.
5. After a short trial window, decide whether to:
- promote as a lasting auxiliary memory surface
- keep it as a narrow pilot
- deprecate it if reuse is too low or noise is too high

## Operational Note

The strongest practical advantage of cross-agent / cross-repo memory sharing is not "smarter agents" in the abstract. It is faster recovery from repeated operational incidents that keep showing up in different places. If the pilot does not materially improve that, it is not worth expanding.

