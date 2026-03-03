# Prime Radiant Agent Runbook: Beads + Dolt Fleet Mode

## Scope

This is the operating contract for agents working in `~/prime-radiant-ai` with centralized Beads on `~/bd`.

- Canonical Beads repo: `~/bd` (`git@github.com:stars-end/bd.git`)
- Canonical backend: Dolt server mode
- Canonical hosts: `macmini`, `epyc12`, `epyc6`, `homedesktop-wsl`
- **Architecture:** Hub-Spoke (epyc12 = hub, others = spokes)

## 0) Hub-Spoke Architecture (bd-va5h)

### Model

| Host | Role | Dolt Server | Connection Target |
|------|------|-------------|-------------------|
| epyc12 | HUB | Active (writer) | localhost |
| macmini | SPOKE | Stopped | epyc12:3307 |
| homedesktop-wsl | SPOKE | Stopped | epyc12:3307 |
| epyc6 | SPOKE + STANDBY | Stopped | epyc12:3307 |

### Environment Variables

All hosts must have:
```bash
export BEADS_DOLT_SERVER_HOST=100.107.173.83  # epyc12 Tailscale IP
export BEADS_DOLT_SERVER_PORT=3307
```

### Reference

See `docs/BEADS_FLEET_HUB_SPOKE_IMPLEMENTATION.md` for full architecture details.

## 1) Preflight (Required Before Dispatch)

Run on the host where dispatch will run:

```bash
cd ~/bd
bd dolt test --json
bd status --json
```

**Hub (epyc12) must also pass:**
```bash
systemctl --user is-active beads-dolt.service
# Listener should be on 100.107.173.83:3307
ss -tlnp | grep 3307
```

**Spokes (macmini, homedesktop-wsl, epyc6):**
- Do NOT run local Dolt servers
- Must connect to hub via BEADS_DOLT_SERVER_HOST

Expected result:
- `bd dolt test --json` shows `"connection_ok": true`
- `bd status --json` returns non-zero `summary.total_issues`
- Hub has active listener on `100.107.173.83:3307`

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

Hub health from epyc12:
```bash
systemctl --user status beads-dolt.service
bd status --json | jq -c ".summary"
```

Spoke connectivity check from macmini:
```bash
# All spokes should connect to hub
ssh homedesktop-wsl 'bd dolt test --json'
ssh fengning@epyc6 'bd dolt test --json'
```

## 5) Incident Triage

### A) `connection_ok: false`

**On Hub (epyc12):**
1. Verify service: `systemctl --user status beads-dolt.service`
2. Check logs: `journalctl --user -u beads-dolt.service -n 80 --no-pager`
3. Verify Tailscale: `tailscale status`
4. Restart: `systemctl --user restart beads-dolt.service`

**On Spokes:**
1. Verify hub is reachable: `tailscale ping epyc12`
2. Check env vars: `echo $BEADS_DOLT_SERVER_HOST`
3. Verify hub service is running on epyc12

### B) Lock contention (`database ... is locked by another dolt process`)

- Only the hub should run Dolt server
- Spokes should NOT have local Dolt servers running
- Check: `ss -tlnp | grep 3307` (should only show on epyc12)

### C) Divergent behavior across hosts

In hub-spoke mode, all hosts see the SAME data (single source of truth).
If hosts see different data:
1. Check which host is acting as hub
2. Verify all spokes connect to the correct hub
3. Failover to epyc6 if hub is corrupted

## 6) Recovery: Corrupt/Unusable Dolt Data

### Hub Recovery (epyc12)

1. Stop hub service
2. Restore from MinIO backup (hourly snapshots)
3. Or copy from epyc6 standby

```bash
# On epyc12
systemctl --user stop beads-dolt.service
cd ~/bd/.beads
mv dolt "dolt.corrupted.$(date +%Y%m%d%H%M%S)"

# Restore from MinIO (requires mc client configured)
# mc cp beads-minio/beads-backups/latest/dolt_data.tar.gz .
# tar -xzf dolt_data.tar.gz -C ~/bd/.beads/dolt

systemctl --user start beads-dolt.service
cd ~/bd && bd dolt test --json && bd status --json
```

### Failover to epyc6 (Standby)

See `docs/BEADS_FLEET_HUB_SPOKE_IMPLEMENTATION.md` for detailed failover procedure.

## 7) Backup Strategy

### Hourly Snapshots (epyc12 → MinIO)

- Script: `scripts/beads-backup-hourly.sh`
- Schedule: Hourly via cron on epyc12
- Retention: 7 days

### Daily Verification (epyc6)

- Script: `scripts/beads-restore-verify.sh`
- Schedule: Daily via cron on epyc6
- Validates: Backup integrity and restore procedure

### RPO/RTO

| Metric | Target |
|--------|--------|
| RPO | < 1 hour |
| RTO | < 15 minutes |

## 8) Operator Rules

- Do not run mutating `bd` commands from non-`~/bd` repos.
- Do not launch Dolt servers on spoke hosts.
- Keep hub service (epyc12) healthy and monitored.
- Treat `bd status --json` + `bd dolt test --json` as the source of truth.
- **No dolt push/pull between hosts** - use hub-spoke model.

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

## 10) Deprecated Paths (DO NOT USE)

The following patterns are **deprecated** in hub-spoke mode:

- ❌ `dolt push origin main` from spokes
- ❌ `dolt pull origin main --ff-only` on spokes
- ❌ Local Dolt server running on spokes
- ❌ JSONL file-based sync (`~/.beads/beads_sync.sh`)
- ❌ MinIO `file://` mirror as primary sync
- ❌ Any "active-active" distributed sync pattern
