# Beads DX Tooling Quick Reference

## Overview

The DX scripts provide automated handling for the **Centralized Beads Database Pattern**, including safety bypass persistence, fleet checks, and health diagnostics.

## DX Scripts

### Core Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `dx-hydrate.sh` | Auto-persists centralized database safety settings | Bootstrapping new environments |
| `dx-check.sh` | Auto-exports safety bypasses during bootstrap | Pre-flight checks |
| `dx-doctor.sh` | Verifies centralized database health | Diagnostics |
| `dx-status.sh` | Shows database and variable configuration | Status checks |
| `dx-ensure-bins.sh` | Symlinks tools to `~/bin/` | Setup |
| `ensure-shell-path.sh` | Ensures background jobs have same configuration | Cron job setup |

### Beads Runtime Focus

| Tool | Location | Purpose |
|------|----------|---------|
| `bd` | `~/bd/.` | Native canonical DB operations |
| `bd-doctor.sh` | `~/agent-skills/health/bd-doctor` | Health diagnostics |

## Environment Configuration

### Safety Bypass (Required for Cross-Repo Operations)

```bash
# Already configured in ~/.zshrc and ~/.zshenv
export BEADS_IGNORE_REPO_MISMATCH=1
```

### Centralized Database Pattern (Hub-Spoke)

```bash
# Hub
export BEADS_EPYC12_TAILSCALE_IP=<epyc12_tailscale_ip>
export BEADS_DOLT_SERVER_HOST="$BEADS_EPYC12_TAILSCALE_IP"
export BEADS_DOLT_SERVER_PORT=3307

# Spokes and hub connect through this endpoint using Dolt SQL
cd ~/bd && bd dolt test --json
```

## Usage Examples

### Daily Workflow

```bash
# Check database status
dx-status.sh

# Verify health
dx-doctor.sh

# Validate Beads endpoint from the current host
cd ~/bd && bd dolt test --json && bd status --json
```

### Manual Large Import

```bash
# Use structured `bd` APIs for targeted imports/migrations
bd export -o /tmp/epic-snapshot.jsonl
bd import -i /tmp/epic-snapshot.jsonl
```

### Environment Bootstrap

```bash
# Required for fleet mode
export BEADS_EPYC12_TAILSCALE_IP=<epyc12_tailscale_ip>
export BEADS_DOLT_SERVER_HOST="$BEADS_EPYC12_TAILSCALE_IP"
export BEADS_DOLT_SERVER_PORT=3307

# Ensure all safety settings are exported
dx-check.sh

# Ensure symlinks are in place
dx-ensure-bins.sh
```

## Background Jobs

The `ensure-shell-path.sh` script ensures that background cron jobs have the same safety configurations as interactive sessions:

```bash
# Crontab example - safety bypass is automatically available
# No dedicated Beads sync cron in canonical mode.
# Use periodic fleet checks from your host operations tooling.
*/10 * * * * bash -lc 'cd ~/agent-skills && dx-status.sh >/tmp/dx-status.log 2>&1 || true'
```

## Resolution History

| Date | PR/Issue | Change |
|------|----------|--------|
| 2025-02-09 | stars-end/agent-skills#147 | DX tooling enhancements for centralized database |
| 2025-02-09 | steveyeggie/beads#1629 | Upstream issue for auto-batching in core |
| 2025-02-09 | bd-prxo, bd-uezd | Beads issues for this work |

## Troubleshooting

### Large Import Hangs

**Status**: RESOLVED via DX tooling

**Solutions**:
1. Use `dx-hydrate.sh` for automated hydration
2. Use `bd` import/export for controlled migrations
3. See `~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md`

### Repository Mismatch Error

**Symptom**: "Repository fingerprint mismatch"

**Solution**:
```bash
# Verify safety bypass is set
echo $BEADS_IGNORE_REPO_MISMATCH

# Should output: 1
# If not, add to ~/.zshrc and ~/.zshenv:
export BEADS_IGNORE_REPO_MISMATCH=1
```

### Symlinks Missing

### Legacy Tooling (Optional)

**Solution**:
```bash
# Legacy wrappers are deprecated and should be retired for canonical Beads operations.
# Keep them only if a non-canonical repo still requires one-off JSONL migrations.

# For canonical mode, verify Beads SQL health instead:
cd ~/bd && bd dolt test --json && bd status --json

# Verify modern setup
dx-check.sh
```

## See Also

- `~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md` - Large import guidance
- `~/agent-skills/health/bd-doctor/SKILL.md` - Beads health checks
- `~/agent-skills/core/beads-workflow/SKILL.md` - Beads workflow guide
- `~/bd/` - Centralized database directory
