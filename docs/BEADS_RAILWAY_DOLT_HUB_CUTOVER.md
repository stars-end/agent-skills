# Beads Railway Dolt Hub Cutover

## Metadata
- Feature-Key: `bd-eigu`
- Epic: `bd-eigu` (`BEADS_RAILWAY_DOLT_HUB_CUTOVER`)
- Last updated: 2026-02-27
- Status: BLOCKED - Railway Dolt hub deployment failed

## Architecture Decision

### Original Plan
Deploy Railway-hosted Dolt SQL server as central hub for fleet sync.

### Blocker
Railway deployment failed:
1. Dockerfile `dolt init` fails in build environment
2. Dolt SQL server requires proper initialization sequence
3. Alternative S3-based Dolt remotes require DynamoDB (MinIO is S3-only)

### Implemented Solution
**SSH/rsync-based fleet sync** (removes MinIO middleman):
- Keep file:// remotes for local operations
- Use direct SSH/rsync for cross-host sync
- MinIO remains for app data only (not Beads sync)

## Final Architecture

```
┌─────────────────┐         ┌─────────────────┐
│    macmini      │◄───────►│     epyc12      │
│  file://remote  │  rsync  │  file://remote  │
│    (source)     │         │   (canonical)   │
└─────────────────┘         └─────────────────┘
        ▲                           │
        │                           │
        └───────────────────────────┘
              homedesktop-wsl
```

## Host-by-Host Configuration

### Source Host: epyc12 (canonical)
```bash
# Already configured with file:// remote
cd ~/bd/.beads/dolt/beads_bd
dolt remote -v
# fleet-cloud file:///home/fengning/bd/.beads/fleet-remote
```

### Target Hosts: macmini, homedesktop-wsl
```bash
# Ensure remote path matches host OS
cd ~/bd/.beads/dolt/beads_bd
dolt remote remove fleet-cloud
dolt remote add fleet-cloud "file:///$HOME/bd/.beads/fleet-remote"
```

## Sync Protocol

### On Source Host (after mutations)
```bash
cd ~/bd/.beads/dolt/beads_bd
dolt push fleet-cloud main

# Sync fleet-remote to all hosts
~/agent-skills/scripts/bd-fleet-sync.sh push
```

### On Target Hosts
```bash
# Pull latest fleet-remote
~/agent-skills/scripts/bd-fleet-sync.sh pull

# Update local Dolt
cd ~/bd/.beads/dolt/beads_bd
dolt pull fleet-cloud main --ff-only
```

## Failure Modes and Recovery

### Sync Failure
1. Check SSH connectivity: `ssh <host> 'echo ok'`
2. Verify rsync available: `which rsync`
3. Check disk space: `df -h ~/bd/.beads/fleet-remote`

### Divergence
1. Stop all mutations
2. Identify canonical state (epyc12)
3. Copy fleet-remote from canonical: `rsync -az epyc12:~/bd/.beads/fleet-remote/ ~/bd/.beads/fleet-remote/`
4. Re-run `dolt pull`

## Rollback Procedure

```bash
# Restore from backup
cd ~/bd/.beads
mv dolt "dolt.corrupted.$(date +%Y%m%d%H%M%S)"
tar -xzf ~/bd-backup-*.tgz

# Restart service
systemctl --user restart beads-dolt.service  # Linux
launchctl kickstart gui/$(id -u)/com.starsend.beads-dolt  # macOS

# Validate
cd ~/bd && bd dolt test --json && bd status --json
```

## Deprecated Paths (Do Not Use)

| Path | Status | Replacement |
|------|--------|-------------|
| `beads_sync.sh` (MinIO mc mirror) | DEPRECATED | `bd-fleet-sync.sh` |
| `minio_env.sh` | DEPRECATED | Not needed |
| `mc mirror` | DEPRECATED | `rsync` |
| MinIO bucket for live sync | DEPRECATED | SSH/rsync direct |

## Acceptance Checklist

- [ ] All hosts have file:// remote configured
- [ ] `bd-fleet-sync.sh push` succeeds from epyc12
- [ ] `bd-fleet-sync.sh pull` succeeds on macmini and homedesktop-wsl
- [ ] `dolt pull fleet-cloud main --ff-only` succeeds on all hosts
- [ ] Issue counts match across all hosts
- [ ] No references to MinIO live sync in runbook
- [ ] `bd-doctor/fix.sh` updated to use rsync sync

## Evidence Fields

| Check | Command | Expected |
|-------|---------|----------|
| Health | `bd dolt test --json` | `connection_ok: true` |
| Consistency | `bd status --json | jq '.summary.total_issues'` | Same on all hosts |
| Canary | Create/close issue visible on all hosts | Cross-host visibility |
| Drift | `grep -r 'mc mirror\|minio_env\|beads_sync.sh' docs/` | No matches |
