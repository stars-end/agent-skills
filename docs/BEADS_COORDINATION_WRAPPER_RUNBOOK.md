# Beads Coordination Wrapper Runbook (P0)

This is the canonical agent-facing Beads coordination contract.

## One Command

Use `bdx` for Beads coordination commands on every host.

Examples:

```bash
bdx create --title "Task" --type task
bdx show bd-xxxx --json
bdx comments add bd-xxxx "note"
bdx ready --json
bdx dolt test --json
```

## Runtime Topology

- Central active runtime lives on `epyc12` at `~/.beads-runtime/.beads`.
- `~/beads` is the Beads CLI source/build checkout, not runtime state.
- `~/bd` is legacy rollback state, not active runtime truth.

## Routing Contract

- `bdx` routes coordination commands via Tailscale SSH to `epyc12`.
- Direct remote Dolt SQL endpoint tuning is backend plumbing, not the agent coordination path.
- Raw `bd` is reserved for local diagnostics/bootstrap/path-sensitive operations or explicit override.

## Quick Health Check

From any host:

```bash
bdx dolt test --json
bdx show <known-beads-id> --json
```

Backend diagnostics (only when debugging service/runtime):

```bash
beads-dolt dolt test --json
beads-dolt status --json
```

## Failure Classification

- `bdx` fails, but backend checks pass:
  - routing/auth/path issue on the current host.
- backend checks fail on `epyc12`:
  - service/runtime incident.
- `sqlite3: unable to open database file` or `unknown command "dolt"`:
  - local runtime/binary misconfiguration; fix local environment first.
