# DX Fleet Spec V8: Radical Simplification

> Replaces: DX_FLEET_SPEC_V7.6.md
> Epic: bd-cuxy
> Implemented: 2026-02-07
> Status: **DEPLOYED** on macmini (burn-in started)

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
│  ├── HEARTBEAT.md        │◄── openclawd reads (every 2h)
│  ├── *.last_ok           │
│  └── *.last_fail         │
└──────────────────────────┘
               │ reads
               ▼
┌──────────────────────────┐
│  OpenClawd (glm-4.7)    │
│  Read-only summarizer    │
│  Posts to Slack           │
│  #all-stars-end          │
└──────────────────────────┘
```

## Design Principles

1. **Cron does mechanical work.** Deterministic scripts, no LLM in the loop.
2. **OpenClawd reasons.** Reads HEARTBEAT.md, summarizes to Slack. Read-only.
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
| epyc12 | sync + push + gc | 0 | Replica |
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
- **OpenClawd:** Reads ~/.dx-state/HEARTBEAT.md every 2h via dx-pulse cron job.
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
- slack-coordinator (replaced by openclawd)
- auto-checkpoint (removed — conflicts with canonical pre-commit hooks)

## Known Limitations

1. **macOS cron + sleep:** If the Mac is asleep at 3am, cron jobs won't run.
   This is a conscious trade-off — missed runs are acceptable since all
   scripts are idempotent and catch up on next wake.
2. **No real-time alerting:** Alerts happen on job transitions, not in
   real-time. A stuck PR won't alert until the next enforcer run (up to 4h).
3. **Single controller:** If macmini is down, no enforcer runs. This is
   acceptable for the current fleet size (<12 agents).

## Implementation Record

### Phase 0: Kill (executed 2026-02-07)

| Bead | Action | PR/Result |
|------|--------|-----------|
| bd-8x6l | Kill 8 DX LaunchAgents | Unloaded + quarantined to `~/.v7-quarantine/` |
| bd-ype9 | Clean duplicate crontab | Removed `dx-triage-cron`; V7 canonical-sync kept until V8 scripts ready |
| bd-d25k | Disable slack-coordinator | Process killed, plist quarantined |
| bd-x2ux | Delete dead scripts + update dx-hydrate | PR #120 merged |
| bd-v39u | Close 30+ pre-V8 DX beads | V7.9, V7.8, V5/V6 beads closed as superseded |

### Phase 1: Mechanical Scripts (implemented by Gemini 2.5 Flash, reviewed by Claude Code)

| Bead | Script | PR | Notes |
|------|--------|----|-------|
| bd-obyk | canonical-sync-v8.sh | #123 | Diff-based evacuation via `git status --porcelain`. Never resets unless push succeeds. |
| bd-7jpo | worktree-gc-v8.sh | #123, #124 (fix) | `--porcelain` parsing. Detached HEAD: prune only if `merge-base --is-ancestor`. Bug found: stdout corruption from emoji in return values — fixed in #124. |
| bd-s7a3 | worktree-push.sh | #123 | Push all unpushed worktree branches. No PR creation. `--prune` on fetch. |

### Phase 2: Enforcer (implemented by Gemini 2.5 Flash, reviewed by Claude Code)

| Bead | Script | PR | Notes |
|------|--------|----|-------|
| bd-gdlr | queue-hygiene-enforcer.sh | #123 | DX_CONTROLLER=1 guard. 4 rules: DIRTY→disable auto-merge, BEHIND>6h→update branch, empty rescue→delete, stuck>72h→disable. Bug found: stdout corruption (same pattern as gc) — fixed in review. |

### Phase 3: Alerting (implemented by Gemini 2.5 Flash, reviewed by Claude Code)

| Bead | Deliverable | PR | Notes |
|------|-------------|----|-------|
| bd-suaw | dx-job-wrapper.sh Slack alerts | #123 | Transition-only alerts (ok↔fail). `DX_SLACK_WEBHOOK` env var. `-m 5` timeout. |
| bd-2w7c | HEARTBEAT.md.template | #123 | Runtime at `~/.dx-state/HEARTBEAT.md`. Machine-readable for openclawd. |

### Phase 4: Rollout (executed by Claude Code directly)

| Bead | Action | Result |
|------|--------|--------|
| bd-lnn2 | AGENTS.md V8 rules + DX_FLEET_SPEC_V8.md + dx-hydrate V8 crontab install | PR #123 merged |
| bd-ipzs | macmini crontab installed + HEARTBEAT.md initialized | Deployed 2026-02-07 |
| bd-h3ky | Replicate to epyc6 | **Deferred** (P1, after burn-in) |
| bd-dwcb | Replicate to homedesktop-wsl | **Deferred** (P1, after burn-in) |

### Bugs Found During Implementation

1. **stdout corruption pattern** (P0, found in gc + enforcer): Functions that
   use `echo` for both logging and return values corrupt stdout when captured
   by `read`. Fix: redirect all log lines to `>&2`.
2. **`git diff --name-only HEAD` misses staged files** (P0, found in sync):
   Replaced with `git status --porcelain` parsing.
3. **`\n` literal in awk variables** (P1, found in heartbeat update): awk
   doesn't interpret `\n` in variables. Fix: `gsub(/\\n/, "\n", details)`.
4. **Gemini agent self-report inaccuracy**: Agent claimed headRefOid was added
   to enforcer query; it wasn't. Trust-but-verify reviews are essential.

### Beads Traceability

**Epic:** bd-cuxy (V8: Radical Simplification)

**All child beads (16 total, all CLOSED):**

| Phase | Bead | Title | Status |
|-------|------|-------|--------|
| 0 | bd-8x6l | Kill all DX LaunchAgents | CLOSED |
| 0 | bd-ype9 | Kill duplicate crontab | CLOSED |
| 0 | bd-d25k | Disable slack-coordinator | CLOSED |
| 0 | bd-x2ux | Delete dead scripts + update dx-hydrate | CLOSED |
| 0 | bd-v39u | Close pre-V8 DX beads | CLOSED |
| 1 | bd-obyk | canonical-sync-v8.sh | CLOSED |
| 1 | bd-7jpo | worktree-gc-v8.sh | CLOSED |
| 1 | bd-s7a3 | worktree-push.sh | CLOSED |
| 2 | bd-gdlr | queue-hygiene-enforcer.sh | CLOSED |
| 3 | bd-2w7c | HEARTBEAT.md template | CLOSED |
| 3 | bd-suaw | dx-job-wrapper Slack alerts | CLOSED |
| 4 | bd-ipzs | macmini deployment | CLOSED |
| 4 | bd-lnn2 | Agent discipline rules + fleet spec | CLOSED |
| 4 | bd-h3ky | Replicate to epyc6 | OPEN (deferred) |
| 4 | bd-dwcb | Replicate to homedesktop-wsl | OPEN (deferred) |

**Superseded epics (all CLOSED):**
- bd-fp85 (V7.9), bd-xpnr (V7.8), bd-gpac (DX Alerts), bd-dwql (V7.8 closeout)
- bd-fleet-v5-hardening.1 (V5/V6 fleet), bd-v5-* (V5 control plane)
