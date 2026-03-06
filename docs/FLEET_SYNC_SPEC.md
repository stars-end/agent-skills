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

## 12) Fail-Closed MCP Semantics (V2.2)

### Overall Truth Model

The `overall` status is computed from BOTH tool rows AND file rows:

```json
{
  "overall": "green|yellow|red",
  "summary": {
    "tools_pass": N,
    "tools_warn": N,
    "tools_fail": N,
    "files_pass": N,
    "files_warn": N,
    "files_fail": N,
    "pass": N,
    "warn": N,
    "fail": N
  }
}
```

**Critical rule**: If `tools_fail > 0` → `overall = "red"` (no exceptions).

### Runtime Error Fail-Closed

On Python runtime errors, `dx-mcp-tools-sync.sh`:

1. **Removes stale cache fallback**: No fallback to cached JSON
2. **Emits synthetic red JSON**:
   ```json
   {
     "overall": "red",
     "reason_code": "mcp_tools_sync_runtime_error",
     "next_action": "Check Python environment, PyYAML availability, and manifest validation",
     "details": "runtime error - fail-closed"
   }
   ```
3. **Exits non-zero**: Returns exit code 1

### Strict Freshness Enforcement

Both local and remote snapshots must satisfy freshness threshold:

- **Local**: `generated_at_epoch` vs current time
- **Remote**: `generated_at_epoch` vs current time + transport latency
- **Threshold**: `audit.thresholds.tool_stale_hours` (default: 6 hours)

**Reason codes**:
- `local_snapshot_stale`: Local snapshot age > threshold
- `remote_snapshot_stale`: Remote snapshot age > threshold  
- `remote_snapshot_missing`: Cannot fetch remote snapshot

### Fleet-Wide Converge Command

`dx-fleet converge [--apply|--check|--repair] [--json]`:

- Runs `dx-mcp-tools-sync.sh` on all canonical VMs
- Returns non-zero if any host is red
- Includes host-level summary with reason codes

Example:
```bash
dx-fleet converge --check --json | jq '.'
# {
#   "overall": "green|yellow|red",
#   "hosts_checked": 4,
#   "hosts_passed": 4,
#   "hosts_failed": 0,
#   "results": [...]
# }
```

## 13) Out of Scope

Fleet Sync does not introduce centralized execution, SSE gateways, or runtime multiplexers.
