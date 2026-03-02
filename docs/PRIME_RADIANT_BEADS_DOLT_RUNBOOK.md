# Prime Radiant Agent Runbook: Beads + Dolt Fleet Mode

## Scope

This is the operating contract for agents working in `~/prime-radiant-ai` with centralized Beads on `~/bd`.

- Canonical Beads repo: `~/bd` (`git@github.com:stars-end/bd.git`)
- Canonical backend: Dolt server mode
- Canonical hosts: `macmini`, `epyc12`, `epyc6`, `homedesktop-wsl`

## 1) Preflight (Required Before Dispatch)

Run on the host where dispatch will run:

```bash
cd ~/bd
bd dolt test --json
bd status --json
```

Linux hosts must pass:

```bash
systemctl --user is-active beads-dolt.service
```

macOS host must pass:

```bash
launchctl print gui/$(id -u)/com.starsend.beads-dolt
```

Expected result:
- `bd dolt test --json` shows `"connection_ok": true`
- `bd status --json` returns non-zero `summary.total_issues`
- service state is active/running
- exactly one listener on `127.0.0.1:3307`, owned by managed `dolt sql-server --data-dir ~/bd/.beads/dolt`

## 2) Prime Radiant Worktree Flow

Never write in canonical clone. Always use worktrees:

```bash
dx-worktree create bd-xxxx prime-radiant-ai
cd /tmp/agents/bd-xxxx/prime-radiant-ai
```

Before dispatching wave jobs:

```bash
dx-runner preflight --provider opencode
dx-runner beads-gate --repo /tmp/agents/bd-xxxx/prime-radiant-ai --probe-id bd-xxxx
```

## 3) Dispatch Patterns

### Small/Narrow outcomes (<60 min)

Implement directly in your current session.

### Parallel feature outcomes (>=60 min)

Use `dx-batch` (orchestration-only over `dx-runner`):

```bash
dx-batch start --items bd-a,bd-b,bd-c --max-parallel 2
dx-batch status --wave-id <wave-id> --json
dx-batch doctor --wave-id <wave-id> --json
```

`dx-batch` should be used as controller only; model execution remains in `dx-runner`.

## 4) Daily Health Checks

```bash
cd ~/bd
bd dolt test --json
bd ready --limit 5 --json
```

Fleet checks from macmini:

```bash
ssh epyc12 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
ssh homedesktop-wsl 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
ssh feng@epyc6 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
```

## 5) Incident Triage

### A) `connection_ok: false`

1. Verify service state (systemd/launchd)
2. Check logs:

Linux:
```bash
journalctl --user -u beads-dolt.service -n 80 --no-pager
```

macOS:
```bash
tail -n 80 ~/bd/.beads/dolt-launchd.err.log
```

3. Restart service:

Linux:
```bash
systemctl --user restart beads-dolt.service
```

macOS:
```bash
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt
```

### B) Lock contention (`database ... is locked by another dolt process`)

- Ensure exactly one Dolt server per host for `~/bd/.beads/dolt`
- Stop ad hoc/manual Dolt processes, then restart managed service

Port-owner checks:

```bash
# exactly one listener expected
lsof -nP -iTCP@127.0.0.1:3307 -sTCP:LISTEN
ps -p "$(lsof -t -iTCP@127.0.0.1:3307 -sTCP:LISTEN)" -o command=
```

### C) Divergent host counts

- Select source host (normally `epyc12`)
- Stop source + target services
- Copy source `.beads/dolt` snapshot to target
- Restart services
- Re-run `bd dolt test --json` and compare `bd status --json` summaries

## 6) Recovery: Corrupt/Unusable Dolt Data

1. Stop service
2. Move bad data aside
3. Restore from latest `dolt.pre-sync-*` backup or known-good host snapshot
4. Start service and validate

Linux example:

```bash
systemctl --user stop beads-dolt.service
cd ~/bd/.beads
mv dolt dolt.bad.$(date +%Y%m%d%H%M%S)
# restore copied snapshot into ./dolt
systemctl --user start beads-dolt.service
cd ~/bd && bd dolt test --json && bd status --json
```

## 7) Fleet Sync (Canonical: Dolt Remote Origin)

Canonical fleet sync path is native Dolt `push`/`pull` against `origin` from
`~/bd/.beads/dolt/beads_bd` on each host.

### Canonical Sync Workflow

```bash
# Source host after local mutations
cd ~/bd/.beads/dolt/beads_bd
dolt push origin main

# Target host before continuing work
cd ~/bd/.beads/dolt/beads_bd
dolt pull origin main --ff-only
```

### Daily Operator Checklist

```bash
cd ~/bd
bd dolt test --json
bd status --json

cd ~/bd/.beads/dolt/beads_bd
dolt remote -v
dolt pull origin main --ff-only
```

### Hard-Fail Conditions

- `dolt pull origin main --ff-only` fails (divergence or connectivity)
- more than one listener exists on `127.0.0.1:3307`
- listener command does not match managed data dir `~/bd/.beads/dolt`

### Recovery (Deterministic Peer Restore)

If local Dolt data is corrupt or service loops:

```bash
# 1) stop service
systemctl --user stop beads-dolt.service  # Linux
launchctl bootout gui/$(id -u)/com.starsend.beads-dolt  # macOS

# 2) move bad data aside
cd ~/bd/.beads
mv dolt "dolt.corrupted.$(date +%Y%m%d%H%M%S)"

# 3) restore from healthy peer snapshot
# example (macmini <- epyc12):
ssh epyc12 'tar -C /home/fengning/bd/.beads/dolt -cf - .' | tar -C ~/bd/.beads/dolt -xf -

# 4) restart and validate
systemctl --user start beads-dolt.service  # Linux
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.starsend.beads-dolt.plist 2>/dev/null || true
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt  # macOS
cd ~/bd && bd dolt test --json && bd status --json
```

### Deprecated (Historical)

The MinIO `file://` mirror workflow and `~/.beads/beads_sync.sh` path are historical only.
Do not use them for active fleet sync.

## 8) Operator Rules

- Do not run mutating `bd` commands from non-`~/bd` repos.
- Do not launch unmanaged long-running Dolt servers during active waves.
- Keep one managed service per host and validate before dispatch.
- Treat `bd status --json` + `bd dolt test --json` as the source of truth.
- Sync via `dolt push/pull origin main` before switching hosts.
