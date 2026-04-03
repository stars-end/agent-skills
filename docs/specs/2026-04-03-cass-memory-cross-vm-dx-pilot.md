# bd-953g — CASS Memory Cross-VM DX Pilot

## Summary

Run a bounded pilot for `cass-memory` as an explicit cross-agent, cross-VM procedural memory surface for DX/control-plane work. This pilot is additive and manual; it does not change canonical routing for repo discovery (`llm-tldr`) or assistant continuity/symbol-aware memory (`serena`).

## Problem

Agents repeatedly rediscover the same operational tricks across hosts and sessions (for example MCP recovery patterns, fleet sync breakages, Railway deploy-truth quirks, and Beads/Dolt repair steps). Today that learning is mostly trapped in PR text or transient thread context.

## Goals

1. Capture reusable DX playbooks in a shared, queryable memory surface.
2. Keep risk low via explicit opt-in usage and strict redaction.
3. Prove whether `cass-memory` adds measurable value beyond existing workflow docs and `serena`.
4. Preserve canonical defaults: no silent activation in normal agent loop.

## Non-Goals

1. Replacing `llm-tldr` or `serena`.
2. Product behavior changes.
3. Automatic transcript sync or autonomous memory ingestion.
4. Fleet-wide runtime integration changes in this wave.

## Canonical Boundary

- `llm-tldr`: semantic discovery and static analysis.
- `serena`: assistant continuity and symbol-aware memory/editing context.
- `cass-memory` pilot: cross-agent procedural playbooks and learned recovery tricks across sessions/VMs.

If a use case is covered by the first two surfaces, do not route to `cass-memory`.

## Pilot Entry Contract

Pilot may run only when all are true:

1. Named owner: `fengning@stars-end.ai` (or explicitly reassigned).
2. Hypothesis documented before execution:
   - "Shared procedural memory reduces repeated rediscovery time for DX/control-plane incidents."
3. Explicit evaluation window:
   - 14 days from pilot start.
4. Scope restricted to DX/infra/control-plane incidents only.

## Operational Flow (Manual / Low-Risk)

1. Resolve an eligible incident in normal workflow.
2. Create a sanitized "playbook memory" entry with:
   - trigger pattern
   - validated fix steps
   - rollback/failure signals
   - host/runtime qualifiers
3. Retrieval is explicit (`cm recall ...`), never implicit.
4. Any memory used in a fix wave must still be validated against live repo/runtime truth.

No background ingestion, no default-loop hooks, no automatic sharing of raw logs/transcripts.

## Privacy / Redaction Rules

1. Never store secrets, tokens, credentials, cookies, full auth traces, or full user transcripts.
2. Store only redacted procedural summaries and stable operational signals.
3. Include source references as repo paths/PR URLs, not pasted sensitive payloads.
4. If redaction confidence is low, do not store; keep the knowledge in standard docs/PR artifacts instead.

## Success Criteria

Pilot is successful only if all are met during the evaluation window:

1. At least 10 pilot-eligible incidents were handled.
2. At least 6 incidents reused a prior `cass-memory` playbook entry.
3. Median time-to-action for repeated incidents improved by >=20% versus baseline.
4. Zero privacy violations (no prohibited data stored).
5. Operator assessment: retrieval noise acceptable (<=20% irrelevant recalls in sampled queries).

## Exit Criteria

Stop/deprecate pilot if any of these occur:

1. No active owner.
2. Fewer than 3 meaningful reuse events in the window.
3. Privacy/redaction breach.
4. Operational overhead exceeds benefit (for example high-noise recalls, maintenance burden).
5. Observed value is duplicative of `serena`/existing runbooks without clear incremental gain.

## Validation Plan

### Baseline checks (pilot start)

```bash
cm --version
cm quickstart --json
cm doctor --json
```

### Per-incident validation

For each claimed reuse event, record:

1. recall query used
2. recalled entry id/title
3. whether recalled steps resolved or accelerated diagnosis
4. linked evidence (PR/runbook/incident note)

### End-of-window review

Produce a short outcome memo with:

1. metrics vs success criteria
2. privacy audit result
3. recommendation: promote, extend as pilot, or deprecate

## Beads Mapping

- Epic: `bd-umkg`
- Spec task: `bd-953g`
- This document defines the pilot contract only; implementation and rollout, if approved, should be tracked in follow-on child tasks.
