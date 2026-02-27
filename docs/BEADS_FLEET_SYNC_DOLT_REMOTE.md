# Beads Fleet Sync: GitHub Dolt Remote

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

## Why GitHub (not DoltHub SaaS)
1. **No interactive browser login** - SSH keys work non-interactively
2. **Existing credentials** - Already have SSH configured
3. **Private repo in our org** - Controlled access
4. **Dolt native** - No middleman sync layers

## Remote Details

| Property | Value |
|----------|-------|
| Remote name | `origin` |
| URL | `git@github.com:stars-end/bd-dolt.git` |
| Transport | SSH |
| Auth | SSH keys |

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

## Deprecated Paths

| Method | Status |
|--------|--------|
| MinIO mc mirror | DEPRECATED |
| SSH/rsync sync | DEPRECATED |
| file:// remotes | DEPRECATED |
