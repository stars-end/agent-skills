# Beads DX Tooling Quick Reference

> [!NOTE]
> This is the current quick reference for Beads tooling. Canonical topology and host rollout are defined in
> [`docs/BEADS_COORDINATION_WRAPPER_RUNBOOK.md`](docs/BEADS_COORDINATION_WRAPPER_RUNBOOK.md).

## Overview

The DX scripts provide automated handling for the canonical Beads coordination pattern: `bdx` routes coordination commands to epyc12 over Tailscale SSH.

**Note on Data Formats**:
- **Dolt (Canonical)**: The primary, high-concurrency database engine is Dolt server mode on epyc12. Use `bdx` for agent coordination commands.
- **JSONL (Compatibility Only)**: `issues.jsonl` is maintained for legacy compatibility and bulk imports/exports. Do not use JSONL as the primary data store for active fleet operations.

## DX Scripts

### Core Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `dx-check.sh` | Primary DX health command (`dx-status` + optional auto-fix via `dx-hydrate`) | Day-to-day preflight |
| `dx-status.sh` | Read-only environment diagnostics | Triage and visibility |
| `dx-hydrate.sh` | Bootstrap/repair host setup and links (calls `dx-ensure-bins`) | One-time setup or explicit repair |
| `dx-ensure-bins.sh` | Re-link `~/bin` command shims | Rare manual repair only |
| `dx-doctor.sh` | Advanced coordinator/MCP diagnostics | Optional deep-dive, not default Beads flow |
| `ensure-shell-path.sh` | Ensures background jobs have same configuration | Cron job setup |

### Beads Runtime Focus

| Tool | Location | Purpose |
|------|----------|---------|
| `bdx` | `~/agent-skills/scripts/bdx` | Canonical Beads coordination wrapper for agents |
| `beads-dolt` | `~/agent-skills/scripts/beads-dolt` | Backend diagnostics (service/runtime health) |
| `bd` | `~/.beads-runtime/.beads` | Local diagnostics/bootstrap/path-sensitive operations |
| `bd-doctor.sh` | `~/agent-skills/health/bd-doctor` | Health diagnostics |

## Environment Configuration

### Safety Bypass (Required for Cross-Repo Operations)

```bash
# Already configured in ~/.zshrc and ~/.zshenv
export BEADS_IGNORE_REPO_MISMATCH=1
```

### Canonical Coordination Pattern (Hub-Spoke)

```bash
# Agent coordination commands (all hosts)
bdx dolt test --json
bdx show <known-beads-id> --json

# Backend-only diagnostics
beads-dolt dolt test --json
beads-dolt status --json
```

### Fail-Fast Signatures (Dolt-Only Contract)

If you see either of these, stop and fix runtime environment first:
- `sqlite3: unable to open database file`
- `unknown command "dolt" for "bd"`

These indicate wrong binary/runtime, not a valid fallback path.

```bash
export PATH="$HOME/.local/bin:$PATH"
export BD_BIN="$HOME/.local/bin/bd"
export BEADS_DIR="$HOME/.beads-runtime/.beads"
hash -r
~/.agent/skills/health/bd-doctor/check.sh
```

## Usage Examples

### Daily Workflow

```bash
# Primary entrypoint (checks + offers auto-fix)
dx-check.sh

# Validate Beads coordination path from the current host
bdx dolt test --json && bdx show <known-beads-id> --json
```

### Manual Large Import

```bash
# Active path is Dolt SQL (`bd dolt test` + `bd status`).
# Use JSONL import/export only in legacy/compatibility recovery workflows.
export ALLOW_BEADS_LEGACY_SOURCE=1
export ALLOW_BEADS_LEGACY_IMPORT=1
export BEADS_JSONL_COMPAT=1
bd export -o /tmp/epic-snapshot.jsonl
bd import -i /tmp/epic-snapshot.jsonl
```

### Environment Bootstrap (agent-facing)

```bash
# Required for fleet mode
export BEADS_DIR="${BEADS_DIR:-$HOME/.beads-runtime/.beads}"

# Ensure all safety settings are exported
dx-check.sh

# `dx-ensure-bins.sh` is normally invoked by `dx-hydrate.sh`
```

## Background Jobs

The `ensure-shell-path.sh` script ensures that background cron jobs have the same safety configurations as interactive sessions:

```bash
# Crontab example - safety bypass is automatically available
# Beads connectivity alert job is installed only on the hub.
# State-change alerting is sent via dx-job-wrapper -> Agent Coordination transport -> Slack (#railway-dev-alerts by default).
*/10 * * * * DX_ALERTS_CHANNEL_ID=${DX_ALERTS_CHANNEL_ID:-C0AEC54RZ6V} \
  /Users/fengning/agent-skills/scripts/dx-job-wrapper.sh beads-health -- \
  /Users/fengning/agent-skills/scripts/dx-beads-health-alert.sh >> ~/logs/dx/beads-health-alert.log 2>&1
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

**Solution (explicit compatibility):**
```bash
# Legacy wrappers are deprecated and should not be used in active canonical Beads operations.
# Keep them only for explicit one-off compatibility work in non-canonical contexts.

# For canonical mode, verify Beads coordination health instead:
bdx dolt test --json && bdx show <known-beads-id> --json

# Verify modern setup
dx-check.sh
```

### Command Naming

- There is no separate `dx-health` command.
- Use `dx-check` as the standard operator entrypoint.

## See Also

- `~/agent-skills/docs/BEADS_LARGE_IMPORT_WORKAROUND.md` - Large import guidance
- `~/agent-skills/docs/BEADS_COORDINATION_WRAPPER_RUNBOOK.md` - Canonical `bdx` coordination contract
- `~/agent-skills/health/bd-doctor/SKILL.md` - Beads health checks
- `~/agent-skills/core/beads-workflow/SKILL.md` - Beads workflow guide
- `~/.beads-runtime/.beads` - Active centralized runtime directory
- `~/beads/` - Beads CLI source/build checkout (not runtime)
- `~/bd/` - Legacy/rollback mirror only
