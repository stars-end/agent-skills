---
name: dx-cron
description: |
  Monitor and manage dx-* system cron jobs and their logs. 
  MUST BE USED when user asks "is the cron running", "show me cron logs", or "status of dx jobs".
tags: [health, auth, audit, cron, monitoring]
allowed-tools:
  - Bash(crontab:*)
  - Bash(tail:*)
  - Bash(stat:*)
  - Read
---

# DX Cron Skill

Visibility and management for the "Boring Tech" System Cron infrastructure (<2s per check).

## Purpose
Bridges the observability gap after switching from native OpenClaw cron to System Cron. Ensures the V8 engine is firing on all cylinders.

## When to Use This Skill
- "Show me what's in crontab"
- "Are the 3am jobs working?"
- "Check dx-daily logs"
- "Is the heartbeat alert script active?"

## Workflow

### 1. Observability: `dx-cron list`
View all `dx-*` and `ru sync` jobs currently scheduled.
```bash
crontab -l | grep -E "dx-|ru sync|founder-briefing|heartbeat|audit"
```

### 2. Monitoring: `dx-cron doctor`
Verify scripts exist and check last run status from logs.
```bash
# Check script status
for f in ~/agent-skills/scripts/dx-*.sh; do [ -x "$f" ] && echo "✅ $f" || echo "❌ $f (check bits)"; done

# Check last run times of logs
ls -lhrt ~/logs/*.log ~/logs/dx/*.log | tail -5

# Verify service-account auth using canonical host alias resolution
~/agent-skills/scripts/dx-load-railway-auth.sh -- op whoami \
  >/dev/null 2>&1 && echo "✅ OP service account valid" || echo "❌ OP service account invalid"

# Verify canonical repos use SSH remotes for non-interactive rescue pushes
for r in agent-skills prime-radiant-ai affordabot llm-common; do
  git -C ~/"$r" remote get-url origin 2>/dev/null || true
done
```

### 3. Debugging: `dx-cron tail <job>`
Tails the last 20 lines of a specific log.
- **Triage**: `tail -n 20 ~/logs/founder-briefing.log`
- **Heartbeat**: `tail -n 20 ~/logs/dx-heartbeat.log`
- **V8 Sync**: `tail -n 20 ~/logs/dx/canonical-sync.log`

## Integration Points
### With System Cron
- Parses `crontab -l` results.
- Relies on Standard Out/Error redirection to `~/logs/`.

### With Development Workflow
- High-priority briefings run at 6am.
- Infrastructure resets run at 3am.

## What This Skill Does ✅
- Rapidly scans crontab for DX-related processes.
- Surfaces log file staleness (did it run recently?).
- Provides shortcuts for log inspection.
- Highlights canonical cleanup preconditions:
  - canonical repo origins should be `git@github.com:stars-end/<repo>.git`
  - cron cleanup logs should not be polluted by mise trust/shim errors

## Examples
- `dx cron list`
- `tail -f ~/logs/founder-briefing.log`

---
**Last Updated:** 2026-02-17
**Skill Type:** Health/Audit
**Typical Duration:** <2s
