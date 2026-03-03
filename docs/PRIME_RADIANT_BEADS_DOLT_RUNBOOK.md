# Prime Radiant Agent Runbook: Beads + Dolt Fleet Mode

## Scope

This is the operating contract for agents working in `~/prime-radiant-ai` with centralized Beads on `~/bd`.

- Canonical Beads repo: `~/bd` (`git@github.com:stars-end/bd.git`)
- Canonical backend: Dolt SQL server mode
- Canonical fleet: `epyc12` hub, `macmini`, `homedesktop-wsl`, `epyc6` spokes

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

Set/verify fleet connection settings for all hosts:

```bash
export BEADS_DOLT_SERVER_PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
if [[ -z "${BEADS_DOLT_SERVER_HOST:-}" ]]; then
  if [[ "$(hostname)" == "epyc12" ]]; then
    export BEADS_DOLT_SERVER_HOST="127.0.0.1"
  elif [[ -n "${BEADS_EPYC12_TAILSCALE_IP:-}" ]]; then
    export BEADS_DOLT_SERVER_HOST="$BEADS_EPYC12_TAILSCALE_IP"
  else
    export BEADS_DOLT_SERVER_HOST="$(tailscale ip -4 2>/dev/null | awk 'NF{print $1; exit}')"
  fi
fi
if [[ -z "${BEADS_DOLT_SERVER_HOST:-}" ]]; then
  echo "❌ BEADS_DOLT_SERVER_HOST is not set and could not be auto-detected"
  exit 1
fi

echo "fleet target: ${BEADS_DOLT_SERVER_HOST}:${BEADS_DOLT_SERVER_PORT}"
```

Spoke hosts must resolve `BEADS_DOLT_SERVER_HOST` to the epyc12 Tailscale IP.
If host auto-detection is not stable on that host, set `BEADS_EPYC12_TAILSCALE_IP` in profile once.

Connectivity check:

```bash
if command -v nc >/dev/null 2>&1; then
  nc -z "$BEADS_DOLT_SERVER_HOST" "$BEADS_DOLT_SERVER_PORT"
else
  : < /dev/tcp/"$BEADS_DOLT_SERVER_HOST"/"$BEADS_DOLT_SERVER_PORT"
fi
```

Expected result:
- `bd dolt test --json` shows `"connection_ok": true`
- `bd status --json` returns non-zero `summary.total_issues`
- service is active/running on `epyc12`

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
export EPYC12_BEADS_HOST="${EPYC12_BEADS_HOST:-${BEADS_DOLT_SERVER_HOST}}"
if [[ -z "$EPYC12_BEADS_HOST" ]]; then
  echo "❌ EPYC12_BEADS_HOST or BEADS_DOLT_SERVER_HOST must be set"
  exit 1
fi

ssh epyc12 "cd ~/bd; export BEADS_DOLT_SERVER_HOST=127.0.0.1; export BEADS_DOLT_SERVER_PORT=3307; bd dolt test --json; bd status --json | jq -c '.summary'"
ssh homedesktop-wsl "cd ~/bd; export BEADS_DOLT_SERVER_HOST=${EPYC12_BEADS_HOST}; export BEADS_DOLT_SERVER_PORT=3307; bd dolt test --json; bd status --json | jq -c '.summary'"
ssh feng@epyc6 "cd ~/bd; export BEADS_DOLT_SERVER_HOST=${EPYC12_BEADS_HOST}; export BEADS_DOLT_SERVER_PORT=3307; bd dolt test --json; bd status --json | jq -c '.summary'"
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
systemctl --user restart beads-dolt.service
```

macOS:
```bash
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt
```

### B) `database ... is locked`

- Ensure no extra `dolt sql-server` instances are running for `~/bd/.beads/dolt`
- Stop unmanaged process on the host, then restart managed service

```bash
lsof -nP -iTCP@"${BEADS_DOLT_SERVER_HOST}:$BEADS_DOLT_SERVER_PORT" -sTCP:LISTEN
```

### C) Divergent host summaries

- Verify all hosts use same server target
  - Hub: `epyc12`
  - Spokes: `BEADS_DOLT_SERVER_HOST` resolves to epyc12 Tailscale IP
- Compare `bd status --json | jq -c '.summary'` output

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
cd ~/bd && bd dolt test --json && bd status --json
```

## 7) Fleet Sync (Canonical: Hub-Spoke Dolt SQL)

There is no per-host local Git/Dolt pull-push sync in active operation.

```text
Hub:    epyc12
Spokes: macmini, homedesktop-wsl, epyc6
Data:   epyc12:/home/$USER/bd/.beads/dolt
```

### Deployment Contract

- Hub runs `dolt sql-server --data-dir ~/bd/.beads/dolt`
- Spokes connect via `BEADS_DOLT_SERVER_HOST=<epyc12_tailscale_ip>`
- `BEADS_DOLT_SERVER_PORT` is shared across hosts (currently `3307`)
- `bd` commands run against the SQL endpoint from all hosts

### Recovery (Host Divergence)

```bash
# 1) validate hub is the source of truth
ssh epyc12 'cd ~/bd && bd dolt test --json && bd status --json'
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
- Treat `bd status --json` + `bd dolt test --json` as source of truth.
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
