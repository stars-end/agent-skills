# Fleet Sync V2.1 Runbook

## Scope

- Fleet Sync installation and convergence for CASS, Context+, Serena, and llm-tldr
- IDE MCP manifest rendering for:
  - `codex-cli`
  - `claude-code`
  - `antigravity`
  - `opencode`
- Daily and weekly deterministic health surfacing

## Post-Deploy Gate Checklist

Run this immediately after any Fleet Sync rollout step:

- [ ] `scripts/dx-fleet-install.sh --apply --json --manifest configs/fleet-sync.manifest.yaml --mcp-manifest configs/mcp-tools.yaml`
- [ ] `scripts/dx-fleet-check.sh --json --manifest configs/fleet-sync.manifest.yaml --mcp-manifest configs/mcp-tools.yaml`
- [ ] `scripts/dx-mcp-tools-sync.sh --check --json --manifest configs/mcp-tools.yaml`
- [ ] If any gate fails: `scripts/dx-fleet-repair.sh --json --manifest configs/fleet-sync.manifest.yaml --mcp-manifest configs/mcp-tools.yaml`, then re-run `dx-fleet-check.sh --json`.
- [ ] `scripts/dx-audit.sh --json` contains a parseable `fleet_sync` object with current host counts.
- [ ] Confirm `configs/fleet-sync.manifest.yaml` and `configs/mcp-tools.yaml` are unchanged from the approved release hash unless explicitly versioned.

## Daily Runtime Fast-Feedback Path

- Run `scripts/dx-fleet-daily-check.sh` once per day from cron on the host driving operations.
- This check is red-only and non-destructive (`dx-fleet-check.sh --red-only` under the hood).
- On failure, it posts a deterministic alert to `#dx-alerts` via `agent_coordination_send_message` only (no inference layer).

## Weekly Governance Path

- `scripts/dx-audit-cron.sh` remains the weekly governance wrapper and must continue to call `scripts/dx-audit.sh --slack`.
- `dx-audit` JSON output should include:
  - `fleet_sync.passed_checks`
  - `fleet_sync.hosts_*` counters
  - `fleet_sync.skill_stubs_missing`

## Baseline Capture Scaffolding

Use this file for gate baselines:

- PR reject rate: `~/.dx-state/fleet-sync/metrics/pr_reject_rate.jsonl`
  - Append one row per deploy/review cycle with `deploy_epoch`, `pr_number`, `reject_count`.
- Multi-VM bug recurrence notes: `~/.dx-state/fleet-sync/metrics/bug_recurrence.jsonl`
  - Append one row per recurring issue with `title`, `beads`, `vm_count`, `notes`.

Suggested command examples:

```bash
mkdir -p ~/.dx-state/fleet-sync/metrics
jq -cn --arg ts "$(date -u +%s)" '{deploy_epoch:($ts|tonumber), pr_number:0, reject_count:0}' \
  >> ~/.dx-state/fleet-sync/metrics/pr_reject_rate.jsonl
```

## Rollback (Break-Glass)

- Break-glass uninstall: `scripts/dx-fleet-install.sh --uninstall --json`
- Verify recovery with `scripts/dx-fleet-check.sh --json --manifest configs/fleet-sync.manifest.yaml --mcp-manifest configs/mcp-tools.yaml`.
- If uninstall is confirmed green, proceed to manual IDE bootstrap as needed by the active on-call runbook.

## Rollback Gate

- If post-deploy `gate_a` (quality trend) or `gate_b` (recurrence trend) regress for two consecutive reviews, pause rollout and open a follow-up issue for scope reduction or manual triage.
