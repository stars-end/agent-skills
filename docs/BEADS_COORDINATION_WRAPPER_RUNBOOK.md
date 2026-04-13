# Beads Coordination Wrapper Runbook (P0)

This is the canonical agent-facing Beads coordination contract.

## One Command

Use `bdx` for Beads coordination commands on every host.

Examples:

```bash
bdx create --title "Task" --type task
bdx show bd-xxxx --json
bdx comments add bd-xxxx "note"
bdx preflight --json
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

## Scope Guard

`bdx` is a transport and safety shim only.

Allowed behavior:

- route allowed Beads commands to the canonical runtime
- reject local/bootstrap commands that agents must not run in coordination mode
- bound command duration
- normalize transport failures into reason codes
- protect remote argv transport

Not allowed behavior:

- choose the next task
- interpret Beads dependency semantics
- implement duplicate detection
- rewrite issue payloads
- maintain workflow state outside Beads

If a workflow needs smarter task selection, use Beads/BV/dx-runner product surfaces. Do not add Beads semantics to `bdx`.

## Remote Write Guardrails

`bdx` rejects local file-path/stream write patterns before calling remote `bd`:

- File-bearing flags (at minimum `--body-file`, `--description-file`, `--stdin`, and `--metadata @file`) are rejected on spoke hosts because those local paths or stdin streams do not exist on `epyc12`.

Use inline values for remote writes (`--description`, `--notes`, metadata key/value flags), or run path-sensitive commands directly on `epyc12`.

## Quick Health Check

From any host:

```bash
bdx preflight --json
bdx dolt test --json
bdx show <known-beads-id> --json
```

Do not use broad `bdx ready --json` as an agent startup health probe or orchestration heartbeat. Use targeted `bdx show`, `bdx search`, BV `robot-plan`, or `bdx ready --limit ...` only for deliberate manual queue browsing.

## Timeouts And Error Contract

Defaults:

- SSH connect: `BDX_SSH_CONNECT_TIMEOUT_SECONDS=5`
- read commands: `BDX_READ_TIMEOUT_SECONDS=10`
- write commands: `BDX_WRITE_TIMEOUT_SECONDS=30`
- unified override for both reads/writes: `BDX_COMMAND_TIMEOUT_SECONDS=<seconds>`
- write lock acquisition: `BDX_LOCK_TIMEOUT_SECONDS=15`
- preflight: `BDX_PREFLIGHT_TIMEOUT_SECONDS=15`

Set `BDX_JSON_ERRORS=1` or pass `--json` to receive structured failures on stderr:

```json
{"ok":false,"reason_code":"query_timeout","message":"...","command":"show","host":"epyc12"}
```

Common reason codes:

- `ssh_unreachable`
- `remote_bd_failed`
- `query_timeout`
- `mutation_timeout`
- `lock_timeout`
- `unsupported_command`
- `local_file_arg_unsupported`

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
