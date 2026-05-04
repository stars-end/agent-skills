# Codex Session Repair Nightly Automation

## Summary

Install a backup-first nightly repair job on `macmini`, `homedesktop-wsl`, `epyc12`, and `epyc6` that scans `~/.codex/sessions` for oversized JSONL artifacts, rewrites only the pathological payloads that break Codex resume/load, and records a machine-readable report.

## Problem

We have now seen the same failure family on both local and remote Codex sessions:

- huge embedded `data:image` payloads
- `image_url` content items that become invalid or too large
- giant line-oriented payloads inside session JSONL
- Codex Desktop/UI or remote `codex app-server` failing to resume a thread

The failures are durable because the broken payload stays inside the session transcript. Restarting the app-server can help transiently, but the real fix is repairing the stored JSONL without destroying the rest of the thread.

## Goals

- Back up any candidate session before mutation.
- Detect risky Codex session files automatically.
- Repair only the oversized payloads that are known to break resume.
- Skip “hot” sessions so the nightly job does not fight active work.
- Produce a report artifact per run.
- Install the nightly job only on `macmini`, `homedesktop-wsl`, `epyc12`, and `epyc6`.

## Non-Goals

- Auto-restarting Codex app-server nightly.
- Repairing every large session indiscriminately.
- Uploading or centralizing sensitive session contents.
- Modifying `homedesktop-wsl`.

## Active Contract

- The repair tool defaults to scan-only.
- Nightly cron runs with `--repair`.
- A file is a candidate if it has one or more of:
  - `image_url` content items
  - `data:image` payloads
  - lines larger than 1 MB
  - overall file size larger than 100 MB
- Files modified in the last 12 hours are skipped.
- Every repaired file gets a sibling backup in `~/.codex/session-repair-backups/`.
- Backups older than 30 days are pruned.

## Design

### Core library

`lib/codex_session_repair.py`

- Scans `rollout-*.jsonl` files
- Computes per-file risk stats
- Repairs only candidate files
- Recursively sanitizes JSON values
- Writes a JSON report

### Repair transforms

1. `image_url` item replacement
   - replace the whole image content item with a short text placeholder
2. `data:image` payload replacement
   - replace base64 blobs with a text placeholder
3. oversized string collapse
   - if a string remains larger than 500 KB after image replacement, replace it with a compact text placeholder naming the field path and original length
4. parse-failure fallback
   - if a risky line cannot be parsed and still exceeds the collapse threshold, replace the line with a compact recovery event

### Shell wrapper

`scripts/dx-codex-session-repair.sh`

- standard PATH setup
- stable state/report paths
- report path under `~/.dx-state/codex-session-repair/last.json`

### Cron installer

`scripts/dx-codex-session-repair-cron-install.sh`

- idempotent crontab mutation
- host-specific schedule
- uses `dx-job-wrapper` for locking, logs, and Slack state transition alerts

### Fleet installer

`scripts/dx-codex-session-repair-fleet-install.sh`

- installs the tool on:
  - `macmini`
  - `homedesktop-wsl`
  - `epyc12`
  - `epyc6`
- runs the host-local cron installer remotely

## Schedule

- `macmini`: `12 3 * * *`
- `homedesktop-wsl`: `57 3 * * *`
- `epyc12`: `27 3 * * *`
- `epyc6`: `42 3 * * *`

The jobs are staggered to avoid synchronized file/CPU spikes.

## Validation

- `python3 -m pytest tests/test_codex_session_repair.py`
- `bash -n` on all new shell scripts
- local dry run:
  - `scripts/dx-codex-session-repair.sh --json`
- local repair on a controlled fixture:
  - `scripts/dx-codex-session-repair.sh --repair --recent-hours 0 --path <fixture>`
- remote install verification:
  - script exists
  - cron marker exists
  - report path exists after first run

## Risks

- false positives on benign large transcripts
- collapsing payloads that were technically valid but not useful
- direct deployment to remote `~/agent-skills` before merge if we need immediate protection

## Rollback

- remove the cron marker
- restore any repaired file from `~/.codex/session-repair-backups/...`
- delete the installed script files if needed

## Recommended First Task

`bd-29ut0.1` is first because the safety contract determines:

- which files may be touched
- how backups are laid out
- what the nightly job is allowed to do automatically

The implementation and fleet rollout depend on that contract.
