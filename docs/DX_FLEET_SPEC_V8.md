# DX Fleet Spec V8: Radical Simplification

> Replaces: DX_FLEET_SPEC_V7.6.md
> Epic: bd-cuxy
> Date: 2026-02-06

## Architecture

```
┌─────────────────────────────────────────────┐
│                 CRON (macOS)                 │
│                                             │
│  3:05  canonical-sync-v8  (evacuate+reset)  │
│  3:15  worktree-push      (durability)      │
│  3:30  worktree-gc-v8     (cleanup)         │
│  */4h  queue-enforcer     (PR hygiene)      │
│                                             │
│  All wrapped by dx-job-wrapper              │
│  State tracked in ~/.dx-state/              │
└──────────────┬──────────────────────────────┘
               │ writes
               ▼
┌──────────────────────────┐
│  ~/.dx-state/            │
│  ├── HEARTBEAT.md        │◄── clawdbot reads (every 2h)
│  ├── *.last_ok           │
│  └── *.last_fail         │
└──────────────────────────┘
               │ reads
               ▼
┌──────────────────────────┐
│  Clawdbot (glm-4.7)     │
│  Read-only summarizer    │
│  Posts to Slack           │
│  #all-stars-end          │
└──────────────────────────┘
```

## Design Principles

1. **Cron does mechanical work.** Deterministic scripts, no LLM in the loop.
2. **Clawdbot reasons.** Reads HEARTBEAT.md, summarizes to Slack. Read-only.
3. **Founder decides.** No automated merges, no automated PR creation.
4. **Fail-safe defaults.** If push fails, don't reset. If alert fails, don't
   crash the job. If DX_CONTROLLER is unset, do nothing.

## Scripts

| Script | Purpose | Schedule | Beads |
|--------|---------|----------|-------|
| canonical-sync-v8.sh | Evacuate dirty canonicals, reset to master | 3:05 AM | bd-obyk |
| worktree-push.sh | Push unpushed worktree branches | 3:15 AM | bd-s7a3 |
| worktree-gc-v8.sh | Prune merged worktrees | 3:30 AM | bd-7jpo |
| queue-hygiene-enforcer.sh | PR queue hygiene (DX_CONTROLLER only) | */4h | bd-gdlr |
| dx-job-wrapper.sh | Wrap all above with state + Slack alerts | N/A | bd-suaw |

## Controller Pattern

Only one VM acts as the "controller" for write operations on GitHub:

In macmini crontab (at the top):

```
DX_CONTROLLER=1
```

The queue-hygiene-enforcer checks this variable and exits immediately if
not set to 1. This prevents duplicate actions across VMs.

## VM Rollout

| VM | Cron jobs | DX_CONTROLLER | Status |
|----|-----------|---------------|--------|
| macmini | All 4 + wrapper | 1 | Primary |
| epyc6 | sync + push + gc | 0 | Replica |
| homedesktop-wsl | sync + push + gc | 0 | Replica |

Replicas run sync/push/gc for their local canonicals but do NOT run the
enforcer (no DX_CONTROLLER).

## Crontab (macmini — canonical)

```cron
# V8 DX Automation (macmini)
DX_CONTROLLER=1

# V8: canonical-sync
5 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/dx-job-wrapper.sh canonical-sync -- \
  ~/agent-skills/scripts/canonical-sync-v8.sh >> ~/logs/dx/canonical-sync.log 2>&1

# V8: worktree-push
15 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/dx-job-wrapper.sh worktree-push -- \
  ~/agent-skills/scripts/worktree-push.sh >> ~/logs/dx/worktree-push.log 2>&1

# V8: worktree-gc
30 3 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/dx-job-wrapper.sh worktree-gc -- \
  ~/agent-skills/scripts/worktree-gc-v8.sh >> ~/logs/dx/worktree-gc.log 2>&1

# V8: queue-hygiene-enforcer (controller only)
0 */4 * * * /opt/homebrew/bin/bash ~/agent-skills/scripts/dx-job-wrapper.sh queue-enforcer -- \
  ~/agent-skills/scripts/queue-hygiene-enforcer.sh >> ~/logs/dx/queue-enforcer.log 2>&1
```

## Alerting

- **Slack webhook:** Set DX_SLACK_WEBHOOK in crontab env for dx-job-wrapper
  to post alerts on job state transitions (ok→fail, fail→ok).
- **Clawdbot:** Reads ~/.dx-state/HEARTBEAT.md every 2h via dx-pulse cron job.
  Posts 1-3 line summary to Slack #all-stars-end.
- **No alert fatigue:** Only transition alerts, not every-run alerts.

## Superseded Systems

The following V5-V7 components are removed in V8:
- All LaunchAgents (quarantined in ~/.v7-quarantine/)
- dx-sweeper.sh (merged into canonical-sync-v8)
- canonical-sync.sh (replaced by canonical-sync-v8)
- dx-triage / dx-triage-cron (removed)
- dx-janitor.sh (replaced by worktree-gc-v8)
- dx-wip-cleanup.sh (removed)
- dx-trailer-check.sh (removed)
- dx-workflow-check.sh (removed)
- dx-heartbeat-watchdog.sh (replaced by dx-job-wrapper + Slack)
- slack-coordinator (replaced by clawdbot)
- auto-checkpoint (removed — conflicts with canonical pre-commit hooks)

## Known Limitations

1. **macOS cron + sleep:** If the Mac is asleep at 3am, cron jobs won't run.
   This is a conscious trade-off — missed runs are acceptable since all
   scripts are idempotent and catch up on next wake.
2. **No real-time alerting:** Alerts happen on job transitions, not in
   real-time. A stuck PR won't alert until the next enforcer run (up to 4h).
3. **Single controller:** If macmini is down, no enforcer runs. This is
   acceptable for the current fleet size (<12 agents).
