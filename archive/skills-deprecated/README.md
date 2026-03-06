# Deprecated Skills Archive

These skills are archived and no longer part of the active skill surface:

- `parallelize-cloud-work`
- `jules-dispatch`

## Reason

Their prompt-shaping responsibilities were re-scoped into active skills:

- Outbound delegation contract: `extended/prompt-writing`
- Inbound review packaging: `core/tech-lead-handoff`
- Runtime orchestration/dispatch loop: `extended/dx-runner`, `extended/dx-batch`, `dispatch/multi-agent-dispatch`

## Migration Guidance

If you previously used archived cloud/jules delegation prompt flows:

1. Use `prompt-writing` to generate the dispatch contract and enforcement flags.
2. Execute dispatch using governed orchestration (`dx-runner` / `dx-batch` / `multi-agent-dispatch`).
3. Require implementer return via `tech-lead-handoff` (implementation-return mode).

## Date Archived

2026-03-06
