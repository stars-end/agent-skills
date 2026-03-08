# Fleet Sync Specification (v2.3)

## 1) Architecture Contract

Fleet Sync is local-first execution with small shared governance state.

Non-negotiable constraints:

- one command family: `dx-fleet check|repair|audit`
- no centralized MCP gateway
- no parallel audit framework
- single manifest source: `configs/fleet-sync.manifest.yaml`
- canonical state root: `~/.dx-state/fleet/` (legacy read fallback only)
- deterministic Slack path via Agent Coordination (`#fleet-events`)

## 2) Canonical Surfaces

### Canonical VMs

- `macmini`
- `homedesktop-wsl`
- `epyc6`
- `epyc12`

### Canonical IDE lanes

- `antigravity` -> `~/.gemini/antigravity/mcp_config.json`
- `claude-code` -> `~/.claude.json`
- `codex-cli` -> `~/.codex/config.toml`
- `opencode` -> `~/.opencode/config.json`
- `gemini-cli` -> `~/.gemini/antigravity/mcp_config.json` (+ `~/.gemini/GEMINI.md` rail)

Source of truth for IDE paths/artifacts is `scripts/canonical-targets.sh`.

## 3) Command Surface

- `dx-fleet check --mode daily|weekly [--json]`
- `dx-fleet repair [--json]`
- `dx-fleet audit --daily|--weekly [--json]`

Wrapper: `scripts/dx-fleet.sh` (thin dispatch only).

Engine scripts:

- `scripts/dx-fleet-check.sh`
- `scripts/dx-fleet-repair.sh`
- `scripts/dx-audit.sh`
- `scripts/dx-mcp-tools-sync.sh`

## 4) Convergent Sync Contract

`dx-mcp-tools-sync.sh` modes:

- `--check`: detect drift only
- `--apply`: converge tool installation and IDE MCP config rendering
- `--repair`: force converge + verify

Convergence sources:

- tools + versions + health checks from `configs/mcp-tools.yaml`
- canonical IDE paths/artifacts from `scripts/canonical-targets.sh`
- template bootstrap from `config-templates/fleet-sync-*`

Convergence outputs:

- `~/.dx-state/fleet/mcp-tools-sync.json`
- per-file hash, per-tool version, per-tool health, reason codes

## 5) Daily vs Weekly Split

### Daily (runtime, fast)

- `beads_dolt`
- `tool_mcp_health`
- `required_service_health`
- `op_auth_readiness`
- `alerts_transport_readiness`

### Weekly (governance/config)

- `canonical_repo_hygiene`
- `skills_symlink_integrity`
- `global_constraints_rails`
- `ide_config_presence_and_drift`
- `cron_health`
- `service_cap_and_forbidden_components`
- `deployment_stack_readiness`
- `railway_auth_context`
- `gh_deploy_readiness`

Both daily and weekly run cross-VM fanout against all canonical hosts.

## 6) Snapshot Freshness and Remote Safety

Remote host payloads are rejected when stale beyond threshold:

- threshold source: `audit.thresholds.tool_stale_hours` in `configs/fleet-sync.manifest.yaml`
- reason codes:
  - `remote_snapshot_missing`
  - `remote_snapshot_stale`
  - `remote_snapshot_unparseable`

Stale/missing remote payloads fail host checks deterministically.

## 7) Audit JSON Contract

Both `dx-fleet audit --daily --json` and `--weekly --json` must include:

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

`summary` includes severity counts and host counts.

## 8) State Layout

Canonical write root:

- `~/.dx-state/fleet/`

Required artifacts:

- `tool-health.json`
- `tool-health.lines`
- `mcp-tools-sync.json`
- `audit/daily/latest.json`
- `audit/daily/history/YYYY-MM-DD.json`
- `audit/weekly/latest.json`
- `audit/weekly/history/YYYY-WW.json`

Legacy read fallback roots:

- `~/.dx-state/fleet-sync/`
- `~/.dx-state/fleet_sync/`

## 9) Cron Entrypoints

Single canonical cron wrapper:

- `scripts/dx-audit-cron.sh --daily`
- `scripts/dx-audit-cron.sh --weekly`

`dx-fleet-daily-check.sh` is compatibility-only and proxies to daily cron wrapper.

## 10) Gemini Enforcement

`gemini-cli` is canonical and staged by manifest policy:

- grace: `audit.gemini_enforcement.grace_days`
- enforce: `audit.gemini_enforcement.enforce_after`

Required lane artifacts:

- `~/.gemini/GEMINI.md`
- `~/.gemini/antigravity/mcp_config.json`
- `~/.gemini/gemini` or `~/.gemini/gemini-cli` (or command on PATH)

## 11) Slack and Determinism

Daily and weekly emit one deterministic message each to `#fleet-events` through Agent Coordination.

Transport failure semantics:

- preserve underlying audit status if audit failed
- return non-zero when transport fails after a green audit

## 12) Platform Status Contract

Fleet Sync has two operational states:

### Full Fleet Sync GO
All enabled MCP tools are healthy and operational:
- `tool_mcp_health` check passes with all enabled tools green
- MCP tool-value lane provides full context/retrieval capabilities
- Daily and weekly audits pass

### Ops-Platform Only GO
Ops infrastructure is healthy but MCP tool-value lane is partial:
- `tool_mcp_health` may show failures for disabled tools (acceptable)
- Core ops checks pass: `beads_dolt`, `required_service_health`, `op_auth_readiness`, `alerts_transport_readiness`
- IDE surfaces are present and configured
- MCP tools that are explicitly disabled in `configs/mcp-tools.yaml` are exempt from health checks

**Current State (as of 2026-03-08): GO: ops-platform only (partial MCP tool-value lane)**

Enabled MCP tools:
- `llm-tldr` (1.5.2) - Context slicing for codebases
- `contextplus` (1.0.7) - Semantic intelligence for engineering

Disabled MCP tools (with rationale in manifest):
- `cass-memory` (no npm package published, requires building from source)
- `serena` (PyPI package provides no executable entrypoint)

**Fleet Status:**
- All 4 canonical hosts: green
- Daily audit: 20/20 checks pass
- Weekly audit: 36/36 checks pass
- MCP tools: 2/2 enabled tools healthy
- IDE surfaces: 5 IDEs x 4 hosts = 20 configs aligned

To transition to "full Fleet Sync GO":
1. Publish cass-memory to npm or build from GitHub
2. Find alternative for serena or await package fix
3. Update `configs/mcp-tools.yaml` to enable them
4. Verify all enabled tools pass health checks
5. Re-run `dx-mcp-tools-sync.sh --check --json` to confirm green

## 13) Out of Scope

Fleet Sync does not introduce centralized execution, SSE gateways, or runtime multiplexers.
