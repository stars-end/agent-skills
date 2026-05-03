---
name: brownfield-map-first
description: |
  Route brownfield implementation work through repo-owned architecture maps before code changes.
  Use when tracing existing pipelines, data/storage boundaries, frontend read models, or when avoiding repeated rediscovery in large existing systems.
tags: [workflow, brownfield, repo-memory, architecture]
---

# brownfield-map-first

Use this workflow when the task depends on understanding an existing system
before editing it.

This skill is process guidance only. It does not store repo-specific architecture
facts.

## When To Use

Use this skill for prompts such as:

- "map the existing pipeline end-to-end"
- "trace current data flow from ingest to output"
- "where does storage/read-model logic live today?"
- "avoid rebuilding what already exists"
- "audit current backend/frontend/data boundaries"

Do not use this skill for greenfield work with no dependency on current code
structure.

## Routing Order

Follow this order:

1. Read `AGENTS.local.md` if present; otherwise read `AGENTS.md`.
2. Open repo-owned map docs listed by AGENTS routing guidance.
3. Read Beads pointer memory for known gotchas and prior decisions.
5. Use Serena for symbol-aware changes.
6. Use ordinary patch/diff edits for non-symbolic edits.

Required framing: map docs and Beads are starting points, not proof. Source code
verification is mandatory before making changes.

## Minimal Execution Contract

For brownfield changes, capture this in your notes or handoff:

- docs consulted
- stale docs updated or explicitly waived
- whether Serena was required for symbol-safe edits

## Guardrails

- Do not embed repo architecture truth in skills.
- Do not recreate context-area generated skill maps.
- Do not skip repo map docs when stale-if paths overlap the task.
  when semantic/static analysis is available.

## Related Surfaces

- Repo map docs (canonical architecture/data/workflow map)
- Beads memory (pointer + durable decisions)
- Serena (symbol edits)
