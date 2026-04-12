# Beads Recovery Runbook (Legacy Compatibility Fallback)

> [!WARNING]
> This runbook is an explicit break-glass fallback for local `.beads` compatibility recovery only.
> Do not use it as the active fleet workflow.
> Active hub-spoke recovery remains:
> [`docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md`](docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md).

Use this when `bd sync --import-only` hangs, reports `sqlite ... interrupted/locked`, or DX tools report stale Beads state.

## Scope
- Active runtime contract: `~/.beads-runtime/.beads/dolt` (Dolt SQL, hub-spoke)
- Legacy rollback repo: `~/bd` (historical/rollback only)
- Compatibility artifacts: `~/.beads-runtime/.beads/bd.db` and/or `~/.beads-runtime/.beads/issues.jsonl` are legacy recovery-only
- All DX orchestration commands (`dx-runner`, `dx-batch`) must run from non-app directories with `BEADS_DIR=~/.beads-runtime/.beads`

## Fast Recovery
1. `cd ~`
2. `~/.agent/skills/health/bd-doctor/check.sh || ~/.agent/skills/health/bd-doctor/fix.sh`
3. `BEADS_DIR=~/.beads-runtime/.beads bd doctor --json` (active contract check)
4. `dx-runner preflight --provider opencode`
5. `dx-batch doctor --wave-id <wave-id> --json` (if a wave is active)

## Compatibility-Only Branch (Do not use by default)
1. `export ALLOW_BEADS_LEGACY_SOURCE=1` (required to use `dx-founder-daily` compatibility reads)
2. Confirm local artifact layout:
   - `test -f ~/.beads-runtime/.beads/bd.db` (legacy SQLite)
   - `test -f ~/.beads-runtime/.beads/issues.jsonl` (legacy JSONL cache)
3. Recover only with explicit approval; immediately return to Dolt contract once the source of failure is remediated.

## Failure Signatures and Actions
- `beads_non_canonical_cwd`: run from wrong directory.
  - Action: switch to non-app directory and rerun with `BEADS_DIR=~/.beads-runtime/.beads`.
- `beads_db_ambiguity`: both `beads.db` and `bd.db` exist.
  - Action: archive/remove `beads.db`; keep `bd.db`.
- `bd_version_out_of_policy`: host has old `bd`.
  - Action: upgrade/pin host to policy version floor.
- `sqlite ... locked/interrupted` on import:
  - Action: run `~/.agent/skills/health/bd-doctor/fix.sh`, then rerun doctor/preflight.

## Operator Gate (must pass before dispatch)
- `dx-runner preflight --provider <provider>`
- `dx-batch doctor --wave-id <wave-id>` returns no `critical` issues
