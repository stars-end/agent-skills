# Beads Large Import Workaround

## Problem

When importing large JSONL files (1000+ issues) in Direct Mode (`--no-daemon`), the `bd import` command hangs indefinitely during dependency graph construction. This is a **transaction scaling issue** where a single SQLite transaction with thousands of issues causes unbounded write-wait.

## Status

**✅ RESOLVED** - The immediate issue was resolved via [stars-end/agent-skills#147](https://github.com/stars-end/agent-skills/pull/147) (2025-02-09). The centralized `~/bd` database is now hydrated with 1,136 issues.

This document remains as **operational guidance** for future large imports and as a reference for the upstream enhancement request.

## Symptoms

- `bd import -i issues.jsonl --no-daemon` hangs for 5+ minutes
- `--verbose` shows successful JSONL parsing but never completes
- `--force` and `--no-git-history` flags don't resolve the hang
- Process eventually times out or must be killed

## Root Cause

**The "Quiet Zone" Hang:**

1. Import successfully parses JSONL file
2. Reads issues into memory
3. Logs dependency warnings (e.g., "issue bd-xyz.2 not found")
4. **Enters silent period** during dependency graph construction
5. Prepares massive single transaction
6. Never completes before timeout

With 1,200+ issues in a single transaction:
- **SQLite write contention**: Single transaction with thousands of INSERT/UPDATE operations
- **Dependency graph O(n²) scaling**: Cross-referencing dependencies becomes pathological at scale
- **No progress visibility**: The expensive graph construction phase has no logging

## Solutions

### Option 1: DX Tooling (Recommended for Automation)

The DX scripts handle this automatically:

```bash
# DX scripts manage chunked imports and safety settings
dx-hydrate.sh     # Auto-persists centralized database safety settings
dx-check.sh       # Auto-exports safety bypasses during bootstrap
dx-doctor.sh      # Verifies centralized database health
dx-status.sh      # Shows database and variable configuration
```

**Environment persistence** (already configured):
- `BEADS_IGNORE_REPO_MISMATCH=1` in `~/.zshrc` and `~/.zshenv`
- `ensure-shell-path.sh` ensures background jobs have same configuration
- `bd-sync-safe` symlinked to `~/bin/` for deterministic syncs

### Option 2: Manual Chunked Import

For manual large imports, use the wrapper script at `~/bd/bd-import-safe.sh`:

```bash
# Basic usage
~/bd/bd-import-safe.sh ~/bd/.beads/issues.jsonl

# With custom batch size
~/bd/bd-import-safe.sh issues.jsonl --batch-size 100

# With additional bd import flags
~/bd/bd-import-safe.sh issues.jsonl --no-daemon --verbose

# Set environment variables
export BD_IMPORT_BATCH_SIZE=150
export BD_IMPORT_ARGS="--no-daemon --force"
~/bd/bd-import-safe.sh issues.jsonl
```

**Note:** The wrapper script works in background job contexts due to `ensure-shell-path.sh` configuration.

### Option 3: Standard Import (Small Files)

For small imports (<500 issues), use standard `bd import`:

```bash
# Small imports work fine
bd import -i issues.jsonl --no-daemon
```

## Implementation Details

### How Chunked Import Works

1. Counts total lines in JSONL file
2. If within batch size (default: 200), imports directly
3. If larger, splits into batches of 200 issues
4. Imports each batch independently
5. Reports progress and summary statistics

### Wrapper Features

- Automatic chunking (configurable batch size)
- Progress tracking per batch
- Summary statistics (imported/updated, failed batches, duration)
- Graceful error handling
- Works with all `bd import` flags
- Compatible with background job environments

## Related Issues

- **Upstream Issue**: [steveyegge/beads#1629](https://github.com/steveyeggie/beads/issues/1629) - Request for auto-batching in core `bd import`
- **Resolution PR**: [stars-end/agent-skills#147](https://github.com/stars-end/agent-skills/pull/147) - DX tooling enhancements
- **Affected Documentation**:
  - `~/beads/docs/MULTI_REPO_HYDRATION.md` - Multi-repo aggregation
  - `~/beads/docs/ADVANCED.md` - Database redirects
  - `~/beads/docs/TROUBLESHOOTING.md` - Import issues

## When To Use Each Solution

| Scenario | Solution |
|----------|----------|
| **Daily workflow** | Use DX tooling (automatic) |
| **Manual re-hydration** | `bd-import-safe.sh` wrapper |
| **Database recovery** | `bd-import-safe.sh` wrapper |
| **Small imports (<500)** | Standard `bd import` |
| **CI/CD pipelines** | DX scripts with `ensure-shell-path.sh` |

## Environment Configuration

**Centralized Database Pattern** (already configured):
- Multiple repos aggregate to `~/bd/.beads`
- Direct Mode: `no-daemon: true` in config.yaml
- Safety bypass: `BEADS_IGNORE_REPO_MISMATCH=1` in `~/.zshrc` and `~/.zshenv`

**Background job support** (already configured):
- `ensure-shell-path.sh` ensures cron jobs have same safety configurations
- `dx-ensure-bins.sh` symlinks tools to `~/bin/`

## History

- **2025-02-09**: Issue discovered during WooYun Legacy skill setup
- **2025-02-09**: Root causes identified (Scale Contention, Safety Lockout, Zombie Process)
- **2025-02-09**: Chunked import wrapper created at `~/bd/bd-import-safe.sh`
- **2025-02-09**: DX tooling enhanced via PR #147 (dx-hydrate.sh, dx-check.sh, etc.)
- **2025-02-09**: Upstream issue filed (steveyeggie/beads#1629)
- **2025-02-09**: Database hydrated with 1,136 issues
- **2025-02-09**: Documentation added to agent-skills

## See Also

- `~/bd/bd-import-safe.sh` - Manual chunked import wrapper
- `~/bd/bd-sync-safe` - Deterministic sync script (symlinked to `~/bin/`)
- `~/agent-skills/docs/BEADS_DX_QUICK_REFERENCE.md` - DX tooling quick reference
- `~/agent-skills/health/bd-doctor/SKILL.md` - Beads health checks
- `~/agent-skills/core/beads-workflow/SKILL.md` - Beads workflow guide
- DX scripts: `dx-hydrate.sh`, `dx-check.sh`, `dx-doctor.sh`, `dx-status.sh`
