# Beads Fleet Hub-Spoke Implementation

**Status:** Active (bd-va5h)
**Epic:** bd-va5h
**Last Updated:** 2026-03-03

## Architecture Overview

### Hub-Spoke Model

```
                    ┌─────────────────┐
                    │     epyc12      │
                    │   (HUB ONLY)    │
                    │                 │
                    │  Dolt SQL Server│
                    │ 100.107.173.83  │
                    │     :3307       │
                    └────────┬────────┘
                             │
              Tailscale VPN  │
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
   ┌─────────┐         ┌─────────┐         ┌─────────┐
   │ macmini │         │ epyc6   │         │homedesk │
   │ (SPOKE) │         │ (SPOKE) │         │  (SPOKE)│
   │         │         │         │         │         │
   │ Remote  │         │ Remote  │         │ Remote  │
   │ Client  │         │ Client  │         │ Client  │
   └─────────┘         └─────────┘         └─────────┘
```

### Key Properties

1. **Single Writer**: Only epyc12 runs a Dolt SQL server
2. **Tailscale-Only Access**: Service binds to Tailscale IP (100.107.173.83), not localhost
3. **No Distributed Sync**: Removed dolt push/pull loops between hosts
4. **Spokes are Read-Only Clients**: Connect via BEADS_DOLT_SERVER_HOST/PORT

## Hub Configuration (epyc12)

### Service File

Location: `~/.config/systemd/user/beads-dolt.service`

```ini
[Unit]
Description=Beads Dolt SQL Server (Hub Mode - Tailscale)
After=default.target
Documentation=https://github.com/stars-end/agent-skills/blob/master/docs/BEADS_FLEET_HUB_SPOKE_IMPLEMENTATION.md

[Service]
Type=simple
WorkingDirectory=%h/bd
ExecStart=%h/.local/bin/dolt sql-server --data-dir %h/bd/.beads/dolt --host 100.107.173.83 --port 3307
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
```

### Environment Variables

```bash
# Add to ~/.zshrc or ~/.bashrc
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
```

### Management Commands

```bash
# Check service status
systemctl --user status beads-dolt.service

# Restart service
systemctl --user restart beads-dolt.service

# View logs
journalctl --user -u beads-dolt.service -f

# Verify listening
ss -tlnp | grep 3307
```

## Spoke Configuration

### Environment Variables

Each spoke host must set:

```bash
# Add to ~/.zshrc or ~/.bashrc on ALL spoke hosts
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
```

### Spoke Hosts

| Host | Tailscale IP | Role | Local Dolt Service |
|------|-------------|------|-------------------|
| epyc12 | 100.107.173.83 | **HUB** | Active (writer) |
| macmini | 100.122.141.5 | SPOKE | Stopped (read-only) |
| homedesktop-wsl | 100.109.231.123 | SPOKE | Stopped (read-only) |
| epyc6 | 100.95.207.22 | SPOKE + STANDBY | Stopped (read-only) |

## Backup Strategy

### Hourly Snapshots (epyc12 → MinIO)

**Script:** `/tmp/agents/bd-va5h/agent-skills/scripts/beads-backup-hourly.sh`

Runs every hour on epyc12:
1. Creates Dolt schema dump
2. Uploads to MinIO (`beads-minio` alias)
3. Retains 7 days of hourly backups

### Daily Restore Verification (epyc6)

**Script:** `/tmp/agents/bd-va5h/agent-skills/scripts/beads-restore-verify.sh`

Runs daily on epyc6:
1. Downloads latest backup from MinIO
2. Restores to temporary location
3. Validates data integrity
4. Reports success/failure

### RPO/RTO

| Metric | Target | Actual |
|--------|--------|--------|
| RPO (Recovery Point Objective) | < 1 hour | 1 hour (hourly snapshots) |
| RTO (Recovery Time Objective) | < 15 minutes | ~5 minutes (restore script) |

## Failover Procedure

### Promote epyc6 (Standby) to Hub

1. **Stop writes on epyc12:**
   ```bash
   ssh epyc12 'systemctl --user stop beads-dolt.service'
   ```

2. **Copy latest data to epyc6:**
   ```bash
   ssh epyc12 'tar -C ~/bd/.beads/dolt -cf - .' | \
     ssh fengning@epyc6 'tar -C ~/bd/.beads/dolt -xf -'
   ```

3. **Start Dolt on epyc6 with hub config:**
   ```bash
   ssh fengning@epyc6 'systemctl --user start beads-dolt.service'
   ```

4. **Update spoke environment:**
   ```bash
   # On ALL spokes (macmini, homedesktop-wsl)
   export BEADS_DOLT_SERVER_HOST=100.95.207.22  # epyc6's Tailscale IP
   ```

5. **Verify connectivity:**
   ```bash
   bd dolt test --json
   bd status --json
   ```

### Failback to epyc12

1. Sync data back from epyc6 to epyc12
2. Update BEADS_DOLT_SERVER_HOST on all spokes to 100.107.173.83
3. Restart services

## Monitoring & Alerting

### Health Checks

```bash
# From any host
bd dolt test --json  # Should return connection_ok: true
bd status --json     # Should return total_issues count
```

### SLOs

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Connection latency | < 150ms | > 200ms |
| Connection success rate | > 99.9% | < 99% |
| Backup success rate | 100% | < 100% |

### Alerting Signals

1. `bd dolt test --json` returns `connection_ok: false`
2. Latency exceeds 200ms consistently
3. Hourly backup job fails
4. Daily restore verification fails

## Deprecated Paths (DO NOT USE)

The following patterns are **deprecated** in hub-spoke mode:

- ❌ `dolt push origin main` from spokes
- ❌ `dolt pull origin main --ff-only` on spokes
- ❌ Local Dolt server running on spokes
- ❌ JSONL file-based sync (`~/.beads/beads_sync.sh`)
- ❌ MinIO `file://` mirror as primary sync

## Migration Checklist

- [x] Phase 0: Validate Tailscale connectivity (bd-va5h.1)
- [x] Phase 0: Harden epyc12 Dolt service for hub mode (bd-va5h.2)
- [ ] Phase 0: Implement hourly backup + daily restore (bd-va5h.3)
- [ ] Phase 1: Freeze distributed sync writers (bd-va5h.4)
- [ ] Phase 1: Converge canonical head and repoint spokes (bd-va5h.5)
- [ ] Phase 1: Execute multi-host canary (bd-va5h.6)
- [ ] Phase 2: Stabilization SLO monitoring (bd-va5h.7)
- [ ] Phase 2: Standby failover drill (bd-va5h.8)
- [ ] Phase 3: Architecture decision gate (bd-va5h.9)

## References

- Runbook: `docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md`
- Fleet hosts: `configs/fleet_hosts.yaml`
- Beads workflow: `~/.agents/skills/beads-workflow/SKILL.md`
