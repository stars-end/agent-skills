# bd-h3f1 — CASS Memory Candidate Contract

## Summary

Allow agents to nominate "what feels important" for shared memory, but require
that nominations enter the pilot as **candidate memories** first. Candidates are
structured, scoped, and evidence-backed. They are only promoted into durable
shared `cass-memory` playbook bullets after reuse or explicit validation.

This keeps the pilot useful for cross-agent, cross-repo, cross-VM heuristics
without turning the shared memory layer into a noisy dump of opinions.

## Problem

Some of the highest-value operator rules are hard to encode in code or static
docs:

- "always use `op` CLI for dev secrets"
- "prefer Z.AI coding endpoints first when available"
- "verify live deploy identity before treating remote failures as product bugs"

These are real, portable heuristics. But if agents can write any "important"
idea directly into shared memory, the result will drift toward:

1. generic advice
2. stale preferences treated as universal truth
3. duplicated runbook content
4. conflicting rules without provenance
5. accidental sensitive-data leakage

## Goals

1. Preserve the upside of agent judgment for operator heuristics and recovery
   playbooks.
2. Keep shared memory low-noise.
3. Require provenance, redaction, and scope before durable admission.
4. Let the pilot capture cross-agent/cross-repo/cross-VM knowledge that does
   not fit naturally in `source inspection` or `serena`.

## Non-Goals

1. Replacing `source inspection` or `serena`.
2. Automatic ingestion of raw agent transcripts.
3. Free-form autonomous writes directly into durable shared memory.
4. Storing product strategy, secrets, or user-specific context.

## Active Contract

### Memory Tiers

1. **Candidate memory**
- authored when an agent believes something is important
- stored first as a structured repo artifact
- not treated as durable shared truth yet

2. **Established memory**
- promoted into durable `cass-memory` playbook storage after evidence
- eligible for broader reuse across agents and repos

### Admission Rule

Agents may nominate a candidate when all are true:

1. The item is DX/infra/operator knowledge, not product behavior.
2. The item is portable across sessions, agents, or hosts.
3. The item can be expressed without secrets or raw transcript payloads.
4. The agent can attach provenance:
   - PR URL
   - runbook/doc link
   - Beads issue
   - validated runtime evidence

### Allowed Candidate Categories

For the pilot, candidates may only be created for:

1. operator preferences
2. infra/DX heuristics
3. recovery playbooks
4. cross-VM/runtime quirks
5. tool and provider routing rules

### Disallowed Categories

Do not create candidates for:

1. product strategy
2. user-specific preferences unless explicitly confirmed
3. secrets/tokens/cookies/raw logs
4. speculative architecture claims without evidence
5. code-structure facts better handled by `source inspection`
6. symbol/project memory better handled by `serena`

## Candidate Schema

Every candidate must include:

1. title
2. category
3. scope
4. trigger pattern
5. proposed rule or playbook
6. provenance
7. redaction check
8. confidence
9. promotion gate
10. prune conditions

## Promotion Rules

A candidate becomes established only when at least one is true:

1. It is reused successfully in 2+ separate incidents, or
2. It is explicitly validated by the operator as a standing rule, or
3. It is backed by a stable runbook/contract and confirmed useful in practice

Promotion should then store a concise bullet in `cass-memory` using the current
upstream CLI surface:

```bash
cm playbook add "<sanitized summary>" --category workflow
```

The richer context should remain in repo docs/templates for auditability.

## Pruning Rules

Prune or deprecate a candidate when any are true:

1. It becomes stale or superseded
2. It is marked harmful or misleading
3. It is too repo-specific to justify shared memory
4. It duplicates an existing runbook or established memory without new value
5. It cannot be supported with provenance

## Seed Heuristics

The first seeded candidate set should focus on operator rules with real
cross-agent value, for example:

1. use `op` CLI for dev secrets and service-account auth
2. prefer Z.AI coding endpoints first when available
3. verify deploy identity before trusting remote founder-path failures
4. treat MCP EOF with search-pass as daemon/runtime state first
5. use worktrees for all canonical repo edits
6. use Railway non-interactively with explicit project/environment/service
7. treat dirty canonical clones as DX blockers, not background noise
8. prefer bounded repair docs over free-form incident folklore
9. separate product bugs from control-plane failures explicitly
10. persist only sanitized operator summaries into shared memory

## Validation

The pilot extension is successful if:

1. agents can nominate candidates without dumping raw intuition directly into
   durable shared memory
2. the first seeded operator heuristics are concrete and reusable
3. promotion/pruning can be explained in one short runbook
4. the resulting shared memory remains narrower than a generic team wiki

## Beads Mapping

- Epic: `bd-umkg`
- Task: `bd-h3f1`
- Depends on: `bd-fzfe`
