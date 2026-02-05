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

- **macmini**: Only host that performs `bd-sync-safe`. Only host that posts Slack heartbeats (configured in job scripts).
- **linux**: Uses standard crontab.
