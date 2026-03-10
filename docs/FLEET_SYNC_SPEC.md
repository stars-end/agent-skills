# Fleet Sync Specification (v2.4)

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
- `skills_plane_alignment`
- `ide_bootstrap_alignment`
- `global_constraints_rails`
- `ide_config_presence_and_drift`
- `cron_health`
- `service_cap_and_forbidden_components`
- `deployment_stack_readiness`
- `railway_auth_context`
- `gh_deploy_readiness`

#### Skills-Plane Health Checks (Weekly)

The weekly audit includes two skills-related checks for fleet governance:

**`skills_plane_alignment`**

Verifies the shared skills plane (`~/.agent/skills`) is properly installed on each canonical host:
- Skills plane exists
- Symlink points at canonical `agent-skills` (or is a git checkout)
- `AGENTS.md` present in skills plane
- Baseline artifact (`dist/universal-baseline.md`) exists
- Core skill directories present (`core/`, `extended/`, `health/`, `infra/`, `railway/`)

This check is weekly because:
- Skills plane installation changes infrequently
- Misalignment indicates systemic issues requiring manual intervention
- Daily checks would be noisy for what is fundamentally an install-time concern

**`ide_bootstrap_alignment`**

Verifies IDE bootstrap/config rails point at the shared skills plane:
- `~/.claude/CLAUDE.md` exists and references AGENTS.md
- `~/.gemini/GEMINI.md` exists and references AGENTS.md
- `~/.opencode/config.json` references AGENTS.md

This check is weekly because:
- IDE configuration is typically set up once per host
- Missing files may indicate IDE not installed (acceptable)
- Bootstrap drift requires manual intervention

For local skills-plane diagnosis (on a single VM), use `skills-doctor`:
```bash
~/.agent/skills/health/skills-doctor/check.sh
~/.agent/skills/health/skills-doctor/check.sh --json
```

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

## 12) Tool Classes

Each tool in `configs/mcp-tools.yaml` has an `integration_mode` field:

### MCP Tools (`integration_mode: mcp`)
- Rendered into IDE MCP configs
- Require `target_ides` and `mcp` config blocks
- Must pass Layer 4 client visibility checks

### CLI Tools (`integration_mode: cli`)
- Standalone CLI binaries
- NOT rendered to IDE configs
- Only require Layer 1 host runtime health
- Do NOT need to appear in `codex mcp list` or similar

### Current Tool Roster (V2.2)

| Tool | Mode | Status | Notes |
|------|------|--------|-------|
| `llm-tldr` | mcp | Enabled | Static analysis context slicing |
| `cass-memory` | cli | Enabled | CLI-native, no IDE rendering |
| `context-plus` | mcp | Enabled | Package: `contextplus@latest` |
| `serena` | mcp | Enabled | Install from GitHub (PyPI collision) |

## 13) Platform Status Contract

Fleet Sync has two operational states:

### Full Fleet Sync GO
All enabled tools are healthy and operational:
- `tool_mcp_health` check passes with all enabled tools green
- MCP tools visible in IDE clients
- CLI tools passing health checks
- Daily and weekly audits pass

### Ops-Platform Only GO
Ops infrastructure is healthy but tool-value lane is partial:
- Core ops checks pass: `beads_dolt`, `required_service_health`, `op_auth_readiness`, `alerts_transport_readiness`
- Tools that are explicitly disabled in `configs/mcp-tools.yaml` are exempt from health checks

**Current State (as of 2026-03-10): FULL_GO**

All four tools are enabled and pass Layer 1-4 checks:
- `llm-tldr` (mcp): Static analysis context slicing
- `cass-memory` (cli): CLI-native episodic memory
- `context-plus` (mcp): Structural context analysis
- `serena` (mcp): AI assistant memory

**Known Limitations (documented in evidence/layer4.txt):**
- Claude Code: All MCP tools visible and connected ✓
- Codex CLI: All MCP tools visible and connected ✓ (using `mcp_servers` TOML format)
- OpenCode: All MCP tools visible and connected ✓ (using `mcp` JSONC format)
- Gemini CLI: All MCP tools visible and connected ✓ (using `~/.gemini/settings.json`)

Full GO is achieved. All four primary clients show MCP tool visibility for Layer 4 (Codex verified on macmini, optional on Linux).
## 14) Out of Scope

Fleet Sync does not introduce centralized execution, SSE gateways, or runtime multiplexers.
