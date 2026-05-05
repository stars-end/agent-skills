# bd-hayo / bd-eyiu — dx-check Active-Runtime MCP Exposure Preflight

## Summary
Add a small preflight to `scripts/dx-check.sh` that verifies the active client/runtime can see the canonical required MCP discovery stack before deeper review or investigation work begins. The preflight should stay lightweight, should not build indexes or run expensive probes, and should surface a precise blocker when `source inspection` or `serena` are not exposed in the active runtime.

## Problem
We saw a runtime-specific tool-routing exception where a heavy review pass expected to use `source inspection`, but the active runtime could not access it. The host was otherwise healthy, and later checks showed `source inspection` available in canonical Codex. That means the failure mode is not necessarily fleet-wide tool outage; it is often active-runtime exposure drift.

Today `dx-check` verifies baseline DX health and can auto-hydrate the environment, but it does not explicitly answer the question that matters before a deep review pass:

- can the active client/runtime see `source inspection`?
- can the active client/runtime see `serena`?

## Goals
1. Extend `dx-check` with a lightweight active-runtime MCP exposure preflight.
2. Check the canonical required MCP tools:
   - `source inspection`
   - `serena`
3. Keep the preflight cheap:
   - use client-native `mcp list` commands or equivalent visibility checks
   - do not run semantic indexing, warm, or deep MCP call probes
4. Produce a clear outcome:
   - pass when required tools are visible in the active runtime
   - warn/fail with exact actionable message when they are not
5. Keep existing `dx-check` behavior intact outside this narrow addition.

## Non-Goals
- replacing `mcp-doctor`
- fleet-wide rollout validation inside `dx-check`
- semantic index readiness checks
- expensive smoke calls against `source inspection` or `serena`
- adding new MCP tools beyond the canonical required pair

## Active Contract
`dx-check` should answer two distinct questions:
1. Is the machine broadly healthy?
2. Is the active runtime ready for canonical MCP-first discovery/editing?

This wave only adds the second answer in a lightweight way.

Expected behavior:
- if the active runtime is Codex, use `codex mcp list`
- if the active runtime is Claude/OpenCode/Gemini and there is a deterministic way to infer that runtime, use the matching client list command
- if active runtime cannot be determined safely, default to the local canonical runtime for the current lane and emit a clear note about what was checked
- fail loudly only for the required runtime being checked, not for every installed client on the machine

## Design
### Preferred shape
Implement a small helper in `scripts/dx-check.sh` that:
- detects or accepts an explicit runtime target
- runs the matching `<client> mcp list`
- verifies visibility of `source inspection` and `serena`
- returns a compact pass/fail summary

### Runtime selection
Support a minimal override such as:
- `DX_CHECK_RUNTIME=codex`
- `DX_CHECK_RUNTIME=claude`
- `DX_CHECK_RUNTIME=opencode`
- `DX_CHECK_RUNTIME=gemini`

Default behavior should remain simple and local. The most likely default is:
- `codex` on local macOS canonical host

If the implementation finds an existing repo convention for runtime selection, use that instead of inventing a parallel variable.

### Failure mode
On failure, `dx-check` should print a precise message like:
- active runtime: codex
- missing MCP exposure: `source inspection`, `serena`
- action: run Fleet Sync / repair MCP config / retry after runtime restart

This should be a DX-blocking failure for heavy MCP-first work, not a silent warning.

## Execution Phases
1. Add spec and Beads structure.
2. Implement narrow `dx-check` helper and wiring.
3. Add focused validation for pass/fail detection.
4. Update docs only where the live contract changes.
5. Run local validation and open/update PR.

## Beads Structure
- `BEADS_EPIC`: `bd-hayo` — Add active-runtime MCP exposure preflight to dx-check
- `BEADS_CHILDREN`:
  - `bd-eyiu` — Implement dx-check MCP exposure preflight for source inspection and serena
- `BLOCKING_EDGES`: none beyond parent-child

## Validation
1. `DX_CHECK_RUNTIME=codex ./scripts/dx-check.sh` passes on the current canonical local runtime.
2. A synthetic failure proof exists, for example by stubbing the runtime command or using a controlled missing-tool output fixture if the implementation supports it.
3. Existing `dx-check` baseline behavior still works.
4. If docs are touched, they match the new active-runtime MCP preflight contract.

## Risks / Rollback
### Risk
`dx-check` becomes noisy or brittle if it tries to validate every client instead of the active runtime.

### Mitigation
Keep the contract narrow:
- one active runtime per invocation
- two required tools only
- visibility only, not deep tool health

### Rollback
Remove the new helper and restore previous `dx-check` behavior. This wave should be isolated enough for a simple revert.

## Recommended First Task
Start with `bd-eyiu`.

Why first:
- the spec is stable
- the code surface is small (`scripts/dx-check.sh`, possibly one helper/test/doc)
- it directly hardens the exact failure mode we just saw without expanding into broader fleet health work
