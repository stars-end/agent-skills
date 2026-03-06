# Prime Radiant Agent Runbook: Beads + Dolt Fleet Mode

## Scope

This is the operating contract for agents working in `~/prime-radiant-ai` with centralized Beads on `~/bd`.

- Canonical Beads repo: `~/bd` (`git@github.com:stars-end/bd.git`)
- Canonical backend: Dolt SQL server mode
- Canonical fleet: `epyc12` hub, `macmini`, `homedesktop-wsl`, `epyc6` spokes

Operational contract:
- `epyc12` is the single managed Beads SQL service host.
- `macmini` is a control-pane host only (no local Beads SQL service).
- `homedesktop-wsl` and `epyc6` are spokes only.

Fail-fast contract (no silent fallback):
- There is no supported SQLite fallback for active fleet operation.
- If you see `sqlite3: unable to open database file` or `unknown command "dolt"`, stop immediately.
- Treat this as runtime misconfiguration (usually wrong `bd` binary/env), not as missing local `.beads` init.
- Do not run `bd init --prefix`, `bd --db`, or `bd sync --no-daemon` as recovery for fleet mode.
- Required runtime pins:
  - `BD_BIN=$HOME/.local/bin/bd`
  - `BEADS_DIR=$HOME/bd/.beads`
  - `BEADS_DOLT_SERVER_HOST=100.107.173.83`
  - `BEADS_DOLT_SERVER_PORT=3307`

## 1) Preflight (Required Before Dispatch)

Run on the host where dispatch will run:

```bash
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307

beads-dolt dolt test --json
beads-dolt status --json
```

Linux hosts must pass:

```bash
if [[ "$(hostname)" == "epyc12" ]]; then
  systemctl --user is-active beads-dolt.service
fi
```

macOS host (macmini) does not run Beads SQL; confirm local service is disabled:

```bash
launchctl print gui/$(id -u)/com.starsend.beads-dolt >/dev/null 2>&1 || true
```

Set/verify fleet connection settings for all hosts:

```bash
export BEADS_DOLT_SERVER_HOST="${BEADS_DOLT_SERVER_HOST:-100.107.173.83}"
export BEADS_DOLT_SERVER_PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
if [[ -z "${BEADS_DOLT_SERVER_HOST}" ]]; then
  echo "❌ BEADS_DOLT_SERVER_HOST is required for remote Beads mode"
  exit 1
fi

echo "fleet target: ${BEADS_DOLT_SERVER_HOST}:${BEADS_DOLT_SERVER_PORT}"
```

Spoke hosts must resolve `BEADS_DOLT_SERVER_HOST` to the epyc12 Tailscale IP.
All hosts should have `BEADS_DOLT_SERVER_HOST=100.107.173.83` in profile for consistency.

Connectivity check:

```bash
if command -v nc >/dev/null 2>&1; then
  nc -z "$BEADS_DOLT_SERVER_HOST" "$BEADS_DOLT_SERVER_PORT"
else
  : < /dev/tcp/"$BEADS_DOLT_SERVER_HOST"/"$BEADS_DOLT_SERVER_PORT"
fi
```

Expected result:
- `beads-dolt dolt test --json` shows `"connection_ok": true`
- `beads-dolt status --json` returns non-zero `summary.total_issues`
- service is active/running on `epyc12`

If preflight fails with SQLite/legacy signatures:

```bash
export PATH="$HOME/.local/bin:$PATH"
export BD_BIN="$HOME/.local/bin/bd"
export BEADS_DIR="$HOME/bd/.beads"
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
hash -r
~/.agent/skills/health/bd-doctor/check.sh
```

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
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307

beads-dolt dolt test --json
beads-dolt ready --limit 5 --json
```

Fleet checks from macmini:

```bash
export EPYC12_BEADS_HOST="100.107.173.83"
if [[ -z "$EPYC12_BEADS_HOST" ]]; then
  echo "❌ EPYC12_BEADS_HOST or BEADS_DOLT_SERVER_HOST must be set"
  exit 1
fi

ssh epyc12 "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c '.summary'"
ssh homedesktop-wsl "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c '.summary'"
ssh epyc6 "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c '.summary'"
```

## 5) Incident Triage

### A) `connection_ok: false`

1. Verify service state (systemd/launchd)
2. Check network from spoke:

```bash
grep -q "BEADS_DOLT_SERVER_HOST" ~/.zshrc ~/.bashrc
nc -z "$BEADS_DOLT_SERVER_HOST" "$BEADS_DOLT_SERVER_PORT"
```

3. Restart service:

Linux:
```bash
if [[ "$(hostname)" == "epyc12" ]]; then
  systemctl --user restart beads-dolt.service
fi
```

macOS:
```bash
if launchctl print gui/$(id -u)/com.starsend.beads-dolt >/dev/null 2>&1; then
  echo "Unexpected Beads launchd service found on macOS control pane; disable it and let host stay read-only for Beads control."
  launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt
fi
```

### B) `database ... is locked`

- Ensure no extra `dolt sql-server` instances are running for `~/bd/.beads/dolt`
- Stop unmanaged process on the host, then restart managed service

```bash
if [[ "$(hostname)" == "epyc12" ]]; then
  lsof -nP -iTCP@100.107.173.83:3307 -sTCP:LISTEN
else
  # On spokes, clear any unmanaged local listener so there is only one canonical source
  pkill -f "dolt sql-server -H 127.0.0.1 -P 3307" || true
fi
```

### C) Divergent host summaries

- Verify all hosts use same server target
  - Hub: `epyc12`
  - Spokes: `BEADS_DOLT_SERVER_HOST` resolves to epyc12 Tailscale IP
- Compare `beads-dolt status --json | jq -c '.summary'` output

```bash
ssh epyc12 "ss -ltnp | grep ':3307' || true"
ssh homedesktop-wsl "ss -ltnp | grep ':3307' || true"
ssh epyc6 "ss -ltnp | grep ':3307' || true"
```

Expected:

- `epyc12`: listener on `100.107.173.83:3307`
- `homedesktop-wsl`: no listener on `127.0.0.1:3307`
- `epyc6`: no listener on `127.0.0.1:3307`

## 6) Recovery: Corrupt/Unusable Dolt Data

1. Stop service
2. Move bad data aside
3. Restore from latest `dolt.pre-sync-*` backup or known-good snapshot
4. Start service and validate

Linux example:

```bash
systemctl --user stop beads-dolt.service
cd ~/bd/.beads
mv dolt dolt.bad.$(date +%Y%m%d%H%M%S)
# restore copied snapshot into ./dolt
systemctl --user start beads-dolt.service
beads-dolt dolt test --json && beads-dolt status --json
```

## 7) Fleet Sync (Canonical: Hub-Spoke Dolt SQL)

There is no per-host local Git/Dolt pull-push sync in active operation.

```text
Hub:    epyc12
Spokes: macmini, homedesktop-wsl, epyc6
Data:   epyc12:/home/$USER/bd/.beads/dolt
```

### Deployment Contract

- Hub runs `dolt sql-server --data-dir ~/bd/.beads/dolt --host 100.107.173.83 --port 3307`
- Spokes connect via `BEADS_DOLT_SERVER_HOST=100.107.173.83`
- `BEADS_DOLT_SERVER_PORT` is fixed to `3307`
- `bd` commands run against the SQL endpoint from all hosts

### Rollout Wave (Canonical)

Run this when promoting hub-spoke mode:

1. Validate hub server target:

```bash
ssh epyc12 "ss -ltnp | grep ':3307' || true"
```

2. Enforce client env on all hosts:

```bash
for host in epyc12 homedesktop-wsl epyc6; do
  ssh $host "grep -q '^export BEADS_DOLT_SERVER_HOST=100.107.173.83' ~/.zshrc ~/.bashrc || true"
done
grep -q '^export BEADS_DOLT_SERVER_HOST=100.107.173.83' ~/.zshrc ~/.bashrc || true
```

3. Ensure spokes are not running local listeners:

```bash
for host in homedesktop-wsl epyc6; do
  ssh $host "ss -ltnp | grep ':3307' || true"
done
```

4. Validate end-to-end status from each host:

```bash
cd ~/bd
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
cd ~/bd
beads-dolt dolt test --json
beads-dolt status --json | jq -c .summary
ssh epyc12 "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c .summary"
ssh homedesktop-wsl "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c .summary"
ssh epyc6 "~/.agent/skills/scripts/beads-dolt dolt test --json; ~/.agent/skills/scripts/beads-dolt status --json | jq -c .summary"
```

### Recovery (Host Divergence)

```bash
# 1) validate hub is the source of truth
ssh epyc12 '~/.agent/skills/scripts/beads-dolt dolt test --json && ~/.agent/skills/scripts/beads-dolt status --json'
# 2) validate spoke target points to hub
ssh homedesktop-wsl 'grep -q "BEADS_DOLT_SERVER_HOST" ~/.zshrc ~/.bashrc'
# 3) re-run dispatch preflight on each host
```

### Hard-Fail Conditions

- Hub service down on epyc12
- spoke target host is not set or not reachable
- network path to epyc12 fails
- more than one local listener on hub DB port
- listener command does not match `dolt sql-server --data-dir ~/bd/.beads/dolt`

## 8) Operator Rules

- Do not run mutating `bd` commands from non-`~/bd` repos.
- Do not launch unmanaged Dolt servers during active waves.
- Keep one managed service per host and validate before dispatch.
- Treat `beads-dolt status --json` + `beads-dolt dolt test --json` as source of truth.
- Do not use local-file or Git-based Beads sync as primary fleet transport.

## 9) ID Reconciliation (Canonical Contract)

Legacy handoff text and PR notes may reference non-canonical IDs that do not exist in the current
Beads database. Use the canonical IDs below for all coordination, dispatch, and closure checks.

| Legacy alias (non-canonical) | Canonical Beads ID | Meaning |
|---|---|---|
| `bd-eigu` | `bd-dnhf` | Fleet Sync V2 epic |
| `bd-3m51` | `bd-6m88` | Rollback drill task |
| `bd-rvyc` | `bd-ke5a` | Legacy path deprecation task |
| `bd-rr7f`, `bd-t4pz`, `bd-8hxm` | `bd-dnhf` (epic context) | Treat as external aliases only |

Provenance:
- PR: <https://github.com/stars-end/agent-skills/pull/269>
- Beads reconciliation task: `bd-wh4m`
- See: `docs/BEADS_ID_RECONCILIATION_2026-03-02.md`
