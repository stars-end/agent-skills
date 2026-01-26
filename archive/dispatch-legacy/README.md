# Archived Dispatch Scripts

These scripts were consolidated into `scripts/dx-dispatch.py` as part of
the DX Consolidation epic (agent-skills-scu).

## Migration

| Old Script | New Command |
|------------|-------------|
| `jules-dispatch.py <issue>` | `dx-dispatch --jules --issue <issue>` |
| `fleet-dispatch.py dispatch <args>` | `dx-dispatch <vm> <task> [options]` |
| `fleet-dispatch.py status --session <id>` | `dx-dispatch --status <vm>` |
| `fleet-dispatch.py wait --session <id>` | `dx-dispatch --wait <vm> <task>` |
| `fleet-dispatch.py finalize-pr --session <id> --beads <id>` | `dx-dispatch --finalize-pr <session> --beads <id>` |
| `fleet-dispatch.py abort --session <id>` | `dx-dispatch --abort <session>` |
| `nightly_dispatch.py` | Functionality moved to cron/scheduler |

## Date Archived
2026-01-26
