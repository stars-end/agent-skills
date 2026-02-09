# Beads DX Tooling Quick Reference

## Overview

The DX scripts provide automated handling for the **Centralized Beads Database Pattern**, including chunked imports for large JSONL files, safety bypass persistence, and health diagnostics.

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

### Symlinked Tools

| Tool | Location | Purpose |
|------|----------|---------|
| `bd-sync-safe` | `~/bin/bd-sync-safe` → `~/bd/bd-sync-safe.sh` | Deterministic syncs |
| `bd-import-safe` | `~/bin/bd-import-safe` → `~/bd/bd-import-safe.sh` | Manual chunked imports |

## Environment Configuration

### Safety Bypass (Required for Cross-Repo Operations)

```bash
# Already configured in ~/.zshrc and ~/.zshenv
export BEADS_IGNORE_REPO_MISMATCH=1
```

### Centralized Database Pattern

```bash
# Location
~/bd/.beads/          # Centralized beads database
~/bd/.beads/beads.db  # SQLite database (1,136 issues)
~/bd/.beads/issues.jsonl

# Git remote
stars-end/bd          # Remote repository
```

## Usage Examples

### Daily Workflow

```bash
# Check database status
dx-status.sh

# Verify health
dx-doctor.sh

# Sync safely (atomic with git operations)
bd-sync-safe
```

### Manual Large Import

```bash
# Use the wrapper for manual chunked imports
bd-import-safe ~/bd/.beads/issues.jsonl

# Custom batch size
bd-import-safe issues.jsonl --batch-size 100
```

### Environment Bootstrap

```bash
# Ensure all safety settings are exported
dx-check.sh

# Ensure symlinks are in place
dx-ensure-bins.sh
```

## Background Jobs

The `ensure-shell-path.sh` script ensures that background cron jobs have the same safety configurations as interactive sessions:

```bash
# Crontab example - safety bypass is automatically available
0 0 * * * bd-sync-safe
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
2. Use `bd-import-safe` for manual chunked imports
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

**Symptom**: `bd-sync-safe: command not found`

**Solution**:
```bash
# Run the bins setup script
dx-ensure-bins.sh

# Verify symlinks
ls -la ~/bin/bd-*
```

## See Also

- `~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md` - Large import guidance
- `~/agent-skills/health/bd-doctor/SKILL.md` - Beads health checks
- `~/agent-skills/core/beads-workflow/SKILL.md` - Beads workflow guide
- `~/bd/` - Centralized database directory
