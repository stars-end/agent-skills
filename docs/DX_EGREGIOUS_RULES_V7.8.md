# DX Egregious Rules V7.8

This document defines the conditions that trigger an egregious escalation to the founder, along with detection and remediation playbooks.

## Condition 1: Canonical Dirty or Stash
Any canonical clone (~/agent-skills, ~/prime-radiant-ai, ~/affordabot, ~/llm-common) has uncommitted changes or git stashes.

- **Detection**: `dx-fleet-check.sh` (canonical check)
- **Expected Output**: `✅ canonical repos clean`
- **1-Command Remediation**: `dx-sweeper --apply` (creates rescue PRs and resets canonical)
- **Stop Condition**: If `dx-sweeper` fails to push rescue branch.

## Condition 2: Recent Rescue PRs
Any rescue PR (label `wip/rescue`) created or updated in the last 24h.

- **Detection**: `dx-pr-gate.sh` (or `gh pr list --label wip/rescue`)
- **Expected Output**: (empty list)
- **1-Command Remediation**: Merge the rescue PR or cherry-pick into a feature worktree.
- **Stop Condition**: Merge conflict that requires human decision.

## Condition 3: Missed Schedule Window
Any required scheduled job (ru, canonical-sync, auto-checkpoint, etc.) has not run successfully in its defined window.

- **Detection**: `dx-compliance-evidence.sh` (checks `.last_ok` age)
- **Expected Output**: All jobs show `ok` status with recent timestamps.
- **1-Command Remediation**: `dx-schedule-install.sh --apply` (re-installs/re-loads jobs)
- **Stop Condition**: Job fails repeatedly with same exit code in logs.

## Condition 4: Beads Sync Drift
`~/bd` repo is dirty or behind origin for >24h.

- **Detection**: `cd ~/bd && git status -sb`
- **Expected Output**: `## master...origin/master` (clean)
- **1-Command Remediation**: `bd-sync-safe.sh`
- **Stop Condition**: Database prefix/ID mismatch or merge conflict in `.beads/`.

## Condition 5: Stranded Worktrees
No-upstream worktrees persisting in `/tmp/agents` for >24h without an active session lock.

- **Detection**: `dx-worktree-gc --dry-run`
- **Expected Output**: No "ARCHIVE" or "STRANDED" candidates.
- **1-Command Remediation**: `dx-worktree-gc --apply`
- **Stop Condition**: Worktree is dirty but has no upstream branch.

## Condition 6: Heartbeat Missing
Watchdog detects that `dx-pulse` or `dx-daily` has stopped reporting.

- **Detection**: `clawdbot cron list --json` (check enabled/running status)
- **Expected Output**: All pulse/daily jobs enabled.
- **1-Command Remediation**: `dx-schedule-install.sh --apply --host macmini`
- **Stop Condition**: macmini is unreachable or disk is full.
