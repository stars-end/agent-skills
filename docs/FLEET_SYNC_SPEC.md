# Fleet Sync Specification (v2.2)

## Command Family

Fleet Sync health is surfaced through one command family:

- `dx-fleet check [--json]`
- `dx-fleet repair [--simulate]`
- `dx-fleet audit --daily|--weekly [--json]`

`dx-fleet` in this release is thin orchestration that delegates to:

- `scripts/dx-fleet-check.sh`
- `scripts/dx-fleet-repair.sh`
- `scripts/dx-audit.sh`

## State Layout

Canonical write root:

- `~/.dx-state/fleet/`

Artifacts:

- `tool-health.json`
- `tool-health.lines`
- `audit/daily/latest.json`
- `audit/daily/history/YYYY-MM-DD.json`
- `audit/weekly/latest.json`
- `audit/weekly/history/YYYY-WW.json`

Read-fallback roots (migration compatibility):

- `~/.dx-state/fleet-sync/`
- `~/.dx-state/fleet_sync/`

## Audit Contract

`dx-fleet audit --daily` is lean runtime-focused.

`dx-fleet audit --weekly` is governance/config/compliance.

Both modes emit stable JSON keys:

- `mode`
- `generated_at`
- `generated_at_epoch`
- `fleet_status`
- `summary`
- `hosts`
- `checks`
- `repair_hints`
- `reason_codes`
- `state_paths`

## Check IDs (Manifest-Backed)

Default check IDs in `configs/fleet-sync.manifest.yaml`:

- Daily:
  - `beads_dolt`
  - `tool_mcp_health`
  - `required_service_health`
  - `op_auth_readiness`
  - `alerts_transport_readiness`

- Weekly:
  - `canonical_repo_hygiene`
  - `skills_symlink_integrity`
  - `global_constraints_rails`
  - `ide_config_presence_and_drift`
  - `cron_health`
  - `service_cap_and_forbidden_components`
  - `trailer_compliance`
  - `deployment_stack_readiness`
  - `railway_auth_context`
  - `gh_deploy_readiness`

Required on-demand (not daily):

- `deployment_stack_readiness`
- `railway_auth_context`
- `gh_deploy_readiness`

## Manifest Extensions (Required)

`configs/fleet-sync.manifest.yaml` includes:

- `audit.coordinator_host`
- `audit.schedule.daily`
- `audit.schedule.weekly`
- `audit.daily_checks[]`
- `audit.weekly_checks[]`
- `audit.thresholds`
- `audit.slack`
- `audit.gemini_enforcement`

Unknown keys must be ignored.

## Gemini Canonical IDEs

`gemini-cli` is part of canonical IDE set.

Artifacts:

- `~/.gemini/GEMINI.md`
- `~/.gemini/gemini`
- `~/.gemini/antigravity/mcp_config.json` (canonical profile path)

Enforcement:

- Week 1 / grace: missing lane is yellow.
- After grace: missing lane is red in weekly governance checks.
