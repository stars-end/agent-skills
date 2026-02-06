# DX Fleet Schedules V7.8 (OS-as-Code)

This document defines the authoritative schedule matrix for the DX fleet.

## Matrix

| Job | Interval | macmini (launchd) | homedesktop-wsl (cron) | epyc6 (cron) |
|---|---|---|---|---|
| ru | 15m | ✅ | ✅ | ✅ |
| canonical-sync | Daily 3am | ✅ | ✅ | ✅ |
| auto-checkpoint | 30m | ✅ | ✅ | ✅ |
| dx-sweeper | Daily 2am | ✅ | ✅ | ✅ |
| dx-janitor | 1h | ✅ | ✅ | ✅ |
| dx-worktree-gc | Daily 4am | ✅ | ✅ | ✅ |
| dx-triage-cron | 2h | ✅ | ✅ | ✅ |
| dx-heartbeat-watchdog | 1h | ✅ | ❌ | ❌ |
| bd-sync-safe | 10m | ✅ | ❌ | ❌ |

## Commands

All jobs MUST be wrapped by `scripts/dx-job-wrapper.sh`.

Example:
`scripts/dx-job-wrapper.sh canonical-sync -- scripts/canonical-sync.sh`

## Host-Specific Notes

- **macmini**:
  - Runs the scheduled Beads durability job (`bd-sync-safe`) by default.
  - Hosts the Slack heartbeat jobs (Clawdbot cron) and the local heartbeat watchdog (if enabled).
- **homedesktop-wsl / epyc6 (linux)**:
  - Use standard `crontab`.
  - May run `bd-sync-safe` manually when needed; scheduled Beads sync is optional and can be enabled later.

Notes:
- Schedule definitions are OS-as-code templates and must be portable:
  - macOS: `__HOME__` placeholders expanded by `scripts/dx-schedule-install.sh`
  - Linux: `__HOME__` placeholders expanded by `scripts/dx-schedule-install.sh`
