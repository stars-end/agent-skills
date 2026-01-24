# Repository Sync Strategy

## Overview

Automated synchronization keeps repos fresh across canonical VMs while respecting active agent work.

## Implementation Status

✅ **Implemented**: 2026-01-23

- Cron-based scheduled sync on all VMs
- Event-driven sync via dx-dispatch and start-feature
- Log rotation configured

## Scheduled Sync (cron)

| Schedule | Scope | Purpose |
|----------|-------|---------|
| Daily 12:00 UTC | All repos | Baseline freshness |
| Every 4 hours | agent-skills only | High-churn tooling |

### Stagger Times

To prevent thundering herd on GitHub API:

| VM | agent-skills sync time | All-repos sync time |
|----|------------------------|---------------------|
| homedesktop-wsl | :00 (every 4h) | 12:00 UTC daily |
| macmini | :05 (every 4h) | 12:00 UTC daily |
| epyc6 | :10 (every 4h) | 12:00 UTC daily |

## Event-Driven Sync

### dx-dispatch

When dispatching work to remote VMs:
- Syncs agent-skills first (highest churn)
- If `--repo` specified, syncs that repo too
- Non-blocking: warnings if sync fails (dirty tree is expected)

```bash
dx-dispatch epyc6 "Fix the bug" --repo prime-radiant-ai
# Internally runs:
#   ru sync agent-skills --non-interactive --quiet
#   ru sync prime-radiant-ai --non-interactive --quiet
```

### start-feature

When starting a new feature:
- Syncs current repo before creating feature branch
- Ensures agents start with latest code

```bash
feature-lifecycle/start.sh bd-123
# Internally runs:
#   ru sync <current-repo> --non-interactive --quiet
```

## Safety

### Dirty Tree Detection

ru automatically skips repos with uncommitted changes:
- Checks `git status --porcelain` before pulling
- Logs warning but continues with other repos
- **Never** uses `--autostash` (risk of losing uncommitted work)

### Atomic Locking

ru uses portable locking to prevent concurrent operations:
- `mkdir`-based atomic locks (works on all POSIX systems)
- Prevents multiple ru operations on same repo
- Lock files automatically cleaned up on exit

## Logs

### Location

- Linux/WSL: `~/logs/ru-sync.log`
- macOS: `~/logs/ru-sync.log`

### Check Sync Status

```bash
# View recent log entries
tail -50 ~/logs/ru-sync.log

# Check if cron ran today
grep "$(date +%Y-%m-%d)" ~/logs/ru-sync.log

# Count skips (dirty trees)
grep -i "skip\|dirty" ~/logs/ru-sync.log | wc -l
```

## Troubleshooting

### Sync Never Runs

```bash
# Check cron entries exist
crontab -l | grep -E "ru sync"

# Linux/WSL: Verify cron is running
sudo service cron status  # or: systemctl status cron

# WSL: Start cron if not running
sudo service cron start

# Verify ru in PATH
which ru
```

### Repo Always Skipped

```bash
# Check for uncommitted changes
cd ~/repo-name
git status

# If dirty, commit or stash changes
git add -A && git commit -m "WIP"

# Or verify it's safe to skip
# (repo may be intentionally dirty during active work)
```

### Manual Sync

```bash
# Sync all repos
ru sync

# Sync single repo
ru sync agent-skills

# Check what's behind (no changes)
ru status

# Verbose output
ru sync --verbose
```

### Permissions Issues

If cron can't write to log file:

```bash
# Ensure logs directory exists and is writable
mkdir -p ~/logs
chmod 755 ~/logs
touch ~/logs/ru-sync.log
chmod 644 ~/logs/ru-sync.log
```

## Configuration

### View Current Cron Entries

```bash
# epyc6
crontab -l | grep -E "ru sync"

# homedesktop-wsl
ssh fengning@homedesktop-wsl "crontab -l | grep -E 'ru sync'"

# macmini
ssh fengning@macmini "crontab -l | grep -E 'ru sync'"
```

### Modify Schedule

To change sync frequency, edit crontab:

```bash
crontab -e

# Example: Change to every 2 hours instead of 4
# Old: 10 */4 * * * ...
# New: 10 */2 * * * ...
```

## Verification

After implementation, verify on all VMs:

```bash
# 1. Cron entries exist
crontab -l | grep -E "ru sync"

# 2. Logs directory exists
ls -la ~/logs/ru-sync.log

# 3. ru binary accessible
which ru && ru --version

# 4. Manual sync test
ru sync --non-interactive --quiet && echo "PASS" || echo "SKIP (dirty tree expected)"

# 5. Dirty tree detection
cd ~/agent-skills && echo "# test" >> README.md
ru sync agent-skills --non-interactive 2>&1 | grep -i "skip\|dirty"
git checkout README.md  # Clean up
```

## Related Documentation

- [Canonical Targets Registry](CANONICAL_TARGETS.md) - VM and repo configuration
- [ru Documentation](https://github.com/Dicklesworthstone/repo_updater) - Full ru reference
- [multi-agent-dispatch](../multi-agent-dispatch/SKILL.md) - Dispatch sync integration
- [feature-lifecycle](../feature-lifecycle/SKILL.md) - Start feature sync integration

## Maintenance

### Monitoring

Check logs weekly:
```bash
grep -c "SKIP" ~/logs/ru-sync.log  # Count skips
grep -c "✓" ~/logs/ru-sync.log     # Count successes
```

### Updates

When adding new VMs:
1. Update [CANONICAL_TARGETS.md](CANONICAL_TARGETS.md)
2. Run cron setup on new VM
3. Configure log rotation
4. Verify with checklist above

---

**Last Updated:** 2026-01-23
**Epic:** agent-skills-0pf
# POC test Fri Jan 23 08:47:28 PM CET 2026
