# Beads Fleet Sync: GitHub Dolt Remote (DoltHub-Native)

## Metadata
- Feature-Key: `bd-eigu`
- Epic: `bd-eigu`
- Last updated: 2026-02-27
- Status: COMPLETE

## Architecture

Fleet sync uses GitHub-hosted Dolt remotes for cross-host synchronization.

```
macmini ────┐
            ├──► GitHub: stars-end/bd-dolt.git
epyc12 ─────┤     (refs/dolt/data)
            │
homedesktop-wsl
```

## Why GitHub Dolt Remote (This IS DoltHub-Native)

This approach uses Dolt's native git remote support, which is a documented DoltHub pattern:

1. **Dolt git remote support** - Dolt v1.81.8+ supports git remotes natively
2. **No DoltHub SaaS dependency** - GitHub-hosted Dolt data works without DoltHub.com
3. **Non-interactive auth** - SSH keys work without browser login prompts
4. **Private repo in our org** - stars-end/bd-dolt.git under our control
5. **DoltHub compatible** - Can migrate to DoltHub SaaS later if needed

## Why Not Other Approaches

| Approach | Why Not Used |
|----------|--------------|
| DoltHub SaaS | Requires interactive browser login |
| Railway Dolt Hub | RemotesAPI port not accessible externally |
| MinIO S3 | Dolt aws:// requires DynamoDB for locking |
| SSH/rsync | Not Dolt-native, adds sync lag |

## Remote Details

| Property | Value |
|----------|-------|
| Remote name | `origin` |
| URL | `git@github.com:stars-end/bd-dolt.git` |
| Transport | SSH (git protocol) |
| Auth | SSH keys (non-interactive) |
| Data location | `refs/dolt/data` |

## Operational Commands

### Daily Operations
```bash
# Pull latest before starting work
cd ~/bd/.beads/dolt/beads_bd
dolt pull origin main --ff-only

# Push after mutations
dolt push origin main
```

### Preflight Check
```bash
cd ~/bd/.beads/dolt/beads_bd
dolt pull origin main --ff-only
bd dolt test --json
```

## Host Configuration

All hosts configured with:
```bash
cd ~/bd/.beads/dolt/beads_bd
dolt remote add origin "git@github.com:stars-end/bd-dolt.git"
dolt config --local --add user.email "fengning@stars-end.ai"
dolt config --local --add user.name "fengning"
```

## Deprecated Paths

| Method | Status | Notes |
|--------|--------|-------|
| MinIO mc mirror | DEPRECATED | beads_sync.sh removed |
| SSH/rsync sync | DEPRECATED | bd-fleet-sync.sh removed |
| file:// remotes | DEPRECATED | fleet-remote removed |
