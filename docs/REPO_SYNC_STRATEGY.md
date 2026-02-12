# Repository Sync Strategy (V8.3.1)

## Overview

Automated synchronization keeps repos fresh across canonical VMs while respecting active agent work. V8.3.1 introduces a **fetch-only daytime model** that never blocks on dirty repos.

## Implementation Status

✅ **Implemented**: 2026-02-12 (V8.3.1)

- Fetch-only daytime sync (never blocks on dirty)
- Reconcile-if-clean every 2h
- 48h stale auto-evacuation
- Dirty incident tracking
- Cross-agent guardrails

## Sync Model (V8.3.1)

### Daytime: Fetch-Only

Fetch-only sync updates remote refs without touching working tree:

```bash
# Never fails on dirty repos
git fetch origin master --quiet
```

| Repo | Cadence | Method |
|------|---------|--------|
| `~/bd` | 20 min | fetch-only |
| Code canonicals | 30 min staggered | fetch-only |

### Reconcile: Pull-If-Clean

Every 2h, reconcile attempts to pull clean repos:

```bash
# Only pulls if working tree is clean
git pull --ff-only origin master
```

If dirty: skip and update dirty incident tracker.

### Nightly: Hygiene

- 48h stale dirty auto-evacuation
- Rescue branch creation
- Recovery command logging

## Dirty Incident Tracking

All dirty canonicals are tracked in `~/.dx-state/dirty-incidents.json`:

```json
{
  "prime-radiant-ai": {
    "first_seen": "2026-02-12T08:00:00Z",
    "last_seen": "2026-02-12T10:00:00Z",
    "age_hours": 2,
    "diffstat": "2 files changed, 10 insertions(+)"
  }
}
```

At 48h stale, auto-evacuation creates rescue branch and resets canonical.

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `canonical-fetch.sh` | Fetch-only sync | `canonical-fetch.sh [repo\|all]` |
| `canonical-dirty-tracker.sh` | Track dirty incidents | `canonical-dirty-tracker.sh check` |
| `canonical-reconcile.sh` | Pull-if-clean | `canonical-reconcile.sh` |
| `dx-alerts-digest.sh` | Hourly digest | `dx-alerts-digest.sh` |
| `heartbeat-parser.sh` | Parse HEARTBEAT.md | `heartbeat-parser.sh check` |

## Safety

### Previous Policy (V8.0)
- **Never** uses `--autostash` (risk of losing uncommitted work)
- Daily rescue via canonical-sync-v8.sh

### Current Policy (V8.3.1)
- **Fetch-only** during daytime (never conflicts)
- **Reconcile** every 2h if clean (skip if dirty)
- **Auto-track** dirty incidents with age
- **48h stale** auto-evacuate with recovery command
- **No manual triage** required by default

## Cross-Agent Guardrails

### Installed Hooks

| Tool | Hook | Status |
|------|------|--------|
| Claude Code | SessionStart | ✅ `~/.claude/hooks/SessionStart/dx-bootstrap.sh` |
| Codex CLI | config.toml | ✅ `[session].on_start` |
| Antigravity | N/A | ⚠️ TODO - manual step |
| OpenCode | N/A | ⚠️ TODO - manual step |

### Verification

```bash
~/agent-skills/scripts/cross-agent-verify.sh
```

## Logs

### Location

- Fetch log: `~/logs/dx/fetch.log`
- Reconcile log: `~/logs/dx/reconcile.log`
- Digest log: `~/logs/dx/digest-history.log`
- Recovery log: `~/.dx-state/recovery-commands.log`

### Check Sync Status

```bash
# Recent fetch activity
tail -20 ~/logs/dx/fetch.log

# Recent reconcile activity
tail -20 ~/logs/dx/reconcile.log

# Dirty incidents
cat ~/.dx-state/dirty-incidents.json

# Recovery commands
cat ~/.dx-state/recovery-commands.log
```

## Troubleshooting

### Repo Behind Origin

Fetch updates refs but not working tree. To update working tree:

```bash
# Check if behind
git status

# Pull if clean
git pull --ff-only origin master

# Or wait for reconcile job (every 2h)
```

### 48h Stale Auto-Evacuation

If a repo has been dirty for 48+ hours:

1. Rescue branch created: `rescue-<host>-<repo>-<timestamp>`
2. Canonical reset to clean master
3. Recovery command logged

To recover:

```bash
# Check recovery log
cat ~/.dx-state/recovery-commands.log

# Clone rescue branch
gh repo clone stars-end/<repo> -- --branch rescue-<ref>
```

### Manual Sync

```bash
# Fetch-only (never fails)
~/agent-skills/scripts/canonical-fetch.sh all

# Reconcile (skips dirty)
~/agent-skills/scripts/canonical-reconcile.sh

# Check dirty status
~/agent-skills/scripts/canonical-dirty-tracker.sh report
```

## Cron Configuration

All sync jobs use `dx-job-wrapper.sh` for consistent logging:

```bash
# ~/bd - fetch every 20 min
*/20 * * * * dx-job-wrapper.sh fetch-bd -- canonical-fetch.sh bd

# Code canonicals - fetch every 30 min staggered
5,35 * * * * dx-job-wrapper.sh fetch-agent-skills -- canonical-fetch.sh agent-skills
10,40 * * * * dx-job-wrapper.sh fetch-prime -- canonical-fetch.sh prime-radiant-ai

# Reconcile every 2h
0 */2 * * * dx-job-wrapper.sh reconcile -- canonical-reconcile.sh

# Digest hourly
0 * * * * dx-job-wrapper.sh digest -- dx-alerts-digest.sh

# Nightly hygiene (existing)
5 3 * * * dx-job-wrapper.sh canonical-sync -- canonical-sync-v8.sh
```

## Verification

After implementation, verify:

```bash
# 1. Scripts exist
ls ~/agent-skills/scripts/canonical-*.sh

# 2. Fetch works
~/agent-skills/scripts/canonical-fetch.sh all

# 3. Reconcile works
~/agent-skills/scripts/canonical-reconcile.sh

# 4. Dirty tracking works
~/agent-skills/scripts/canonical-dirty-tracker.sh report

# 5. Cross-agent guardrails
~/agent-skills/scripts/cross-agent-verify.sh
```

## Related Documentation

- [ENV_SOURCES_CONTRACT.md](ENV_SOURCES_CONTRACT.md) - Environment sources
- [AGENTS.md](../AGENTS.md) - Agent workflow rules
- [canonical-sync-v8.sh](../scripts/canonical-sync-v8.sh) - Nightly hygiene

---

**Last Updated:** 2026-02-12
**Version:** V8.3.1
**Epic:** bd-og6s
EOF
