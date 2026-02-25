---
name: beads-dolt-fleet
description: Fleet-level Beads Dolt operations for canonical hosts (verify, converge, and recover shared `~/bd` state).
tags: [health, beads, dolt, fleet, vm]
allowed-tools:
  - Bash(ssh:*)
  - Bash(bd:*)
  - Bash(systemctl:*)
  - Bash(launchctl:*)
  - Bash(tar:*)
  - Bash(jq:*)
  - Read
---

# beads-dolt-fleet

## Purpose

Operate Beads as a cross-host system, not a single-host CLI.

Use this skill for:
- fleet-wide Dolt health checks
- service rollout validation
- host state convergence from a chosen source host

## Canonical Hosts

- `macmini`
- `epyc12`
- `epyc6`
- `homedesktop-wsl`

## Fast Fleet Check

Run from macmini:

```bash
cd ~/bd && bd dolt test --json && bd status --json | jq -c '.summary'
ssh epyc12 'cd ~/bd && bd dolt test --json && bd status --json | jq -c ".summary"'
ssh homedesktop-wsl 'cd ~/bd && bd dolt test --json && bd status --json | jq -c ".summary"'
ssh feng@epyc6 'cd ~/bd && bd dolt test --json && bd status --json | jq -c ".summary"'
```

If summaries differ, converge from source host (`epyc12` by default).

## Converge From Source Host

1. Stop Beads service on source and targets
2. Backup target `~/bd/.beads/dolt`
3. Copy source `dolt` directory to targets
4. Restart services
5. Verify identical summaries

Use this transfer pattern:

```bash
ssh epyc12 'cd ~/bd/.beads && tar -cf - dolt' | ssh homedesktop-wsl 'cd ~/bd/.beads && tar -xf -'
ssh epyc12 'cd ~/bd/.beads && tar -cf - dolt' | ssh feng@epyc6 'cd ~/bd/.beads && tar -xf -'
```

## Service Controls

Linux:

```bash
systemctl --user restart beads-dolt.service
systemctl --user is-active beads-dolt.service
```

macOS:

```bash
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt
launchctl print gui/$(id -u)/com.starsend.beads-dolt
```

## Safety Rules

- Stop source service before snapshotting to avoid partial/corrupt copies.
- Always keep timestamped `dolt.pre-sync-*` backups before replacement.
- Never run two Dolt servers against the same data-dir on one host.
