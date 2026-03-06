# DX V8.6 Rescue Loop Runbook

## Purpose
Stop repeated `rescue-*` branch storms without hiding real canonical violations.

## What Changed in V8.6
- `scripts/canonical-evacuate-active.sh`
  - Evacuates only for `dirty` or `diverged` states.
  - Does not evacuate `off_trunk + clean + ahead=0`.
  - Classifies `branch_locked_by_worktree` when `git checkout master` is blocked by an active worktree.
  - Uses tmux attached-pane path signal as the primary active-work hint.
  - Returns non-zero when evacuation fails so `dx-job-wrapper` can surface real failures.
- `scripts/dx-audit.sh`
  - Reports rescue events by lookback window (timestamp parsed from rescue branch suffix).
- `scripts/queue-hygiene-enforcer.sh`
  - Disables auto-merge for any open PR with auto-merge enabled.
- `scripts/dx-alerts-digest.sh`
  - Uses true last-24h window parsing.
  - Counts evacuations by repo (field-correct parsing).

## Verification Checklist
1. Confirm script versions on target host:
   - `grep -n "V8.6" ~/agent-skills/scripts/canonical-evacuate-active.sh`
   - `grep -n "V8.6" ~/agent-skills/scripts/queue-hygiene-enforcer.sh`
2. Dry-run queue policy:
   - `DX_CONTROLLER=1 ~/agent-skills/scripts/queue-hygiene-enforcer.sh --dry-run --verbose`
3. Audit output semantics:
   - `~/agent-skills/scripts/dx-audit.sh --json | jq '.summary'`
   - Confirm `rescue_branches_lookback` is present.
4. Check enforcer logs:
   - `tail -80 ~/logs/dx/canonical-evacuate.log`
   - Confirm no repeated 15-minute dirty evacuations for `off_trunk + clean` state.

## V8.6 Schedule Contract (All Canonical VMs)
- `canonical-evacuate-active`:
  - `*/15 5-16 * * * TZ=America/Los_Angeles ...`
  - `0 17 * * * TZ=America/Los_Angeles ...`
- `canonical-sync`: `5 3 * * * ...`
- `worktree-push`: `15 3 * * * ...`
- `worktree-gc`: `0 * * * * ...`
- `queue-hygiene-enforcer`: `0 */4 * * * DX_CONTROLLER=${DX_CONTROLLER:-0} ...`

Only the controller host (`DX_CONTROLLER=1`) performs enforcer actions.

## If Rescue Storm Persists
1. Identify state:
   - `jq '.["agent-skills"]' ~/.dx-state/dirty-incidents.json`
2. Check master lock owner:
   - `git -C ~/agent-skills checkout master` (expect lock path in error if blocked)
   - `tmux list-panes -a -F '#{session_attached} #{pane_current_path}' | rg '<locked-worktree-path>'`
3. Resolve:
   - If active work is legitimate, keep worktree attached and do nothing.
   - If stale, close stale sessions and run:
     - `git -C ~/agent-skills checkout master`
     - `git -C ~/agent-skills reset --hard origin/master && git -C ~/agent-skills clean -fdq`

## If Action Needed: Founder Briefing Pipeline Only
Use these exact steps to diagnose founder-briefing failures:

1. Source check:
   - `~/agent-skills/scripts/dx-founder-daily.sh --json | jq '.founder_pipeline'`
2. Verify transport auth:
   - `~/agent-skills/scripts/founder-briefing-cron.sh --dry-run`
3. Inspect root-cause lines:
   - `tail -n 140 ~/logs/founder-briefing.log`
4. Check recovery log record:
   - `grep "script=founder-briefing" "$HOME/.dx-state/recovery-commands.log"`

If source is `jsonl`/`legacy` (missing Dolt SQL): run once with explicit fallback
and continue by re-running once:
   - `ALLOW_BEADS_LEGACY_SOURCE=1 ~/agent-skills/scripts/founder-briefing-cron.sh --dry-run`
   - `~/agent-skills/scripts/founder-briefing-cron.sh`

Expected no-fail fix:
- `~/agent-skills/scripts/dx-audit.sh --json | jq '.summary.founder_pipeline'`

## Policy Guardrails
- Canonical repos are read-mostly.
- Work must happen in `/tmp/agents/...` worktrees.
- Auto-merge must remain disabled.
