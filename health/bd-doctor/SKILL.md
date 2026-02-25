---
name: bd-doctor
description: Diagnose and repair Beads reliability issues in canonical Dolt server mode (`~/bd`) across hosts.
tags: [health, beads, dolt, reliability, fleet]
allowed-tools:
  - Bash(bd:*)
  - Bash(git:*)
  - Bash(systemctl:*)
  - Bash(launchctl:*)
  - Bash(ssh:*)
  - Read
---

# bd-doctor

## Purpose

Health check and deterministic recovery for Beads in centralized Dolt mode.

This skill assumes:
- canonical Beads repo: `~/bd`
- backend: Dolt server mode
- multi-host operation (macmini/epyc12/epyc6/homedesktop-wsl)

## When To Use

- `bd` commands fail with connection/lock errors
- dispatch preflight fails at Beads gate
- host summaries diverge (`bd status --json` mismatch)
- agent reports stalled/blocked Beads operations

## Quick Check

Run from `~/bd`:

```bash
bd dolt test --json
bd status --json
bd ready --limit 5 --json
```

Service checks:

Linux:
```bash
systemctl --user is-active beads-dolt.service
```

macOS:
```bash
launchctl print gui/$(id -u)/com.starsend.beads-dolt
```

## Recovery Playbooks

### 1) Dolt server unreachable

1. Restart managed service

Linux:
```bash
systemctl --user restart beads-dolt.service
```

macOS:
```bash
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt
```

2. Re-validate:

```bash
bd dolt test --json
bd status --json
```

### 2) Lock contention (`database ... is locked by another dolt process`)

- Ensure one Dolt server process per host for `~/bd/.beads/dolt`
- Stop unmanaged process and restart managed service

Linux logs:
```bash
journalctl --user -u beads-dolt.service -n 100 --no-pager
```

macOS logs:
```bash
tail -n 100 ~/bd/.beads/dolt-launchd.err.log
```

### 3) Host divergence (different totals across VMs)

1. Choose source host (default `epyc12`)
2. Stop source + target services
3. Copy source `~/bd/.beads/dolt` to target
4. Restart services
5. Compare summaries on all hosts

### 4) Bad/corrupt data dir

```bash
# Linux example
systemctl --user stop beads-dolt.service
cd ~/bd/.beads
mv dolt dolt.bad.$(date +%Y%m%d%H%M%S)
# restore known-good snapshot into ./dolt
systemctl --user start beads-dolt.service
cd ~/bd && bd dolt test --json && bd status --json
```

## Fleet Verification (from macmini)

```bash
ssh epyc12 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
ssh homedesktop-wsl 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
ssh feng@epyc6 'cd ~/bd; bd dolt test --json; bd status --json | jq -c ".summary"'
```

## Guardrails

- Do not run mutating `bd` operations from non-`~/bd` repos.
- Do not run ad hoc `dolt sql-server` during active waves.
- Prefer managed services (`systemd --user` or `launchd`) for uptime.
- Use `bd dolt test --json` + `bd status --json` as source of truth.
