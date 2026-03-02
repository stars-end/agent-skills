# Beads ID Reconciliation (2026-03-02)

## Purpose

Record canonical mapping for legacy fleet-sync IDs that appear in handoff text but are not present
as issue rows in the current canonical Beads database (`~/bd`).

## Canonical Rule

For planning, dispatch, PR validation, and closeout checks, always use canonical IDs from Beads
state in `~/bd`. Treat missing IDs as aliases only.

## Mapping

| Legacy alias (not present as issue row) | Canonical ID | Status | Notes |
|---|---|---|---|
| `bd-eigu` | `bd-dnhf` | closed | Fleet Sync V2 epic |
| `bd-3m51` | `bd-6m88` | closed | Rollback drill task |
| `bd-rvyc` | `bd-ke5a` | closed | Legacy sync deprecation task |
| `bd-rr7f` | `bd-dnhf` | closed | Alias only; no canonical row |
| `bd-t4pz` | `bd-dnhf` | closed | Alias only; no canonical row |
| `bd-8hxm` | `bd-dnhf` | closed | Alias only; no canonical row |

## Evidence

- PR reference containing alias IDs: <https://github.com/stars-end/agent-skills/pull/269>
- Canonical recovered issues verified in Beads:
  - `bd-dnhf`
  - `bd-6m88`
  - `bd-ke5a`
- Reconciliation tracking task: `bd-wh4m`

## Operator Guidance

1. If an agent reports alias IDs above, map them to canonical IDs before review decisions.
2. Do not block merges on non-canonical alias IDs.
3. If needed for audit, cite both alias and canonical IDs in handoff notes.
