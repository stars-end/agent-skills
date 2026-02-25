# Beads Recovery Runbook (Canonical `~/bd`)

Use this when `bd sync --import-only` hangs, reports `sqlite ... interrupted/locked`, or DX tools report stale Beads state.

## Scope
- Canonical control-plane repo: `~/bd`
- Canonical DB file: `~/bd/.beads/bd.db`
- All DX orchestration commands (`dx-runner`, `dx-batch`) must run from `~/bd`

## Fast Recovery
1. `cd ~/bd`
2. `~/.agent/skills/bd-doctor/check.sh || ~/.agent/skills/bd-doctor/fix.sh`
3. `bd doctor --json`
4. `dx-runner preflight --provider opencode`
5. `dx-batch doctor --wave-id <wave-id> --json` (if a wave is active)

## Failure Signatures and Actions
- `beads_non_canonical_cwd`: run from wrong directory.
  - Action: `cd ~/bd` and rerun.
- `beads_db_ambiguity`: both `beads.db` and `bd.db` exist.
  - Action: archive/remove `beads.db`; keep `bd.db`.
- `bd_version_out_of_policy`: host has old `bd`.
  - Action: upgrade/pin host to policy version floor.
- `sqlite ... locked/interrupted` on import:
  - Action: run `~/.agent/skills/bd-doctor/fix.sh`, then rerun doctor/preflight.

## Operator Gate (must pass before dispatch)
- `dx-runner preflight --provider <provider>`
- `dx-batch doctor --wave-id <wave-id>` returns no `critical` issues

