# Fleet Sync V2.1 Implementation Spec

Status: Draft for implementation handoff (architecture not finalized)
Date: 2026-03-04
Epic: bd-d8f4
Primary Directive: Low continued founder load
Secondary Directive: Massively improve agent performance and scale

## 1. Problem Statement

The fleet has 4 VMs x 4 agents (16 agents), 5 repos, and 4-5 IDE runtimes.
Current bottleneck is repeated founder intervention caused by:
- no persistent agent memory
- semantically weak context gathering
- repeated multi-VM mistakes
- runtime/config drift across IDEs and hosts

Tools (CASS, Context+, Serena, llm-tldr) are mandatory for performance.
The architecture decision is delivery model, not tool selection.

## 2. Existing Stack (Assumed Stable)

- epyc12: centralized Dolt hub for canonical Beads governance DB
- Railway: dev/prod app runtime (Postgres + pgvector)
- `~/agent-skills`: skills distribution + AGENTS baseline recompilation
- OP CLI service accounts + Railway vars: dev/deploy secrets model
- `#dx-alerts`: deterministic alert surface via Agent Coordination app
- OpenClaw Slack gateway: reasoning overlay for ambiguous/red conditions

## 3. Architectural Decision (Current Hypothesis)

### 3.1 Keep
- Local-first execution for CASS/Context+/Serena/llm-tldr per VM
- Centralized small shared state on epyc12 Dolt only when needed
- Existing skills/baseline lane mechanics for V2.1

### 3.2 Reject
- Mandatory centralized MCP gateway execution (SSE/proxy as hard dependency)

### 3.3 Explicitly unresolved
- Whether lanes A/B/C fully merge to one substrate in V2.2

## 4. Distribution Model

Current lanes:
- Lane A: skills artifacts (`dx-agents-skills-install.sh`)
- Lane B: AGENTS/baseline artifacts (`publish-baseline.zsh` and sync)
- Lane C: MCP tool/runtime config distribution (new)

V2.1 decision:
- Keep A and B implementation as-is
- Add C via manifest-driven rendering/install
- Unify operations via one operator interface (`dx-fleet *`)

## 5. Required Artifacts

### 5.1 Manifests
- `configs/fleet-sync.manifest.yaml`
  - fleet topology, service caps, policy constraints
- `configs/mcp-tools.yaml`
  - tool versions, install commands, health commands, IDE targets

### 5.2 Scripts
- `scripts/dx-fleet-install.sh`
  - installs/renders/enables full Fleet Sync stack for a VM
  - idempotent
  - supports `--json` and `--uninstall`
- `scripts/dx-fleet-check.sh`
  - verifies convergence (versions, config hashes, tool health, auth)
  - supports strict JSON output
- `scripts/dx-fleet-repair.sh`
  - enforces manifest state and repairs drift deterministically
- `scripts/dx-mcp-tools-sync.sh`
  - low-level MCP tool convergence engine and health state emitter

### 5.3 Docs
- this spec (`docs/FLEET_SYNC_SPEC.md`)
- optional Dolt schema (`docs/FLEET_SYNC_DOLT_SCHEMA.sql`)
- runbook updates (deployment, rollback, VM rebuild)

## 6. Script Contracts (Implementation-Ready)

### 6.1 `dx-fleet-install.sh`
Must:
- validate OP + Railway auth preconditions
- invoke MCP sync with manifest pinning
- render all IDE configs from templates (no manual edits)
- output per-IDE config hash summary
- return non-zero on any required convergence failure

### 6.2 `dx-fleet-check.sh`
Must produce machine-readable output for audit ingestion:
- tool version matches manifest
- per-IDE config hash matches rendered baseline
- tool health status (`last_ok`, `last_fail`, error)
- Dolt sync freshness marker for shared-state features
- auth readiness markers (OP token loaded, Railway auth context)

### 6.3 `dx-fleet-repair.sh`
Must:
- re-render drifted configs
- re-pin/reinstall drifted tool versions
- refresh auth material using OP source-of-truth path
- preserve last-known-good behavior on partial failures

### 6.4 `dx-fleet-install.sh --uninstall`
Must:
- remove Fleet Sync-managed tool/runtime entries
- restore config backups (or minimal known-safe baseline)
- leave normal agent coding flows functional without Fleet Sync tools

## 7. Secrets and Auth Contract

Source:
- `op://dev/Agent-Secrets-Production/*` for dev/control secrets

Sink:
- Railway variables for deploy/runtime

Rules:
- OP -> Railway is one-way source/sink contract
- no plaintext secrets in manifests/templates
- for system services (e.g., optional LiteLLM), use systemd-creds style injection

## 8. Shared-State Contract (Optional Phase)

Dolt shared-state must stay small and governance-safe.
Allowed tables (if enabled):
- `mcp_tool_manifest`
- `tool_health`
- `memory_digest` (sanitized summaries only)

Not allowed by default:
- raw transcripts
- raw session logs
- embedding vectors/blobs

Memory policy:
- opt-in sharing only
- repo scope boundary required
- TTL retention required
- redaction for token-like strings required pre-write

## 9. Deployment Model (Big-Bang With Automated Verification)

Founder operating model requirement: no long-lived partial-state rollout.

### 9.1 Build (worktree)
Agent builds artifacts and validates locally.

### 9.2 Validate (single VM)
Agent runs install + check and proves green on one VM.

### 9.3 Deploy (single session, all 4 VMs)
Agent executes fleet-wide install in one session, with approved SSH/fleet-deploy commands.

### 9.4 Verify (automated)
`dx-audit` posts deterministic status to `#dx-alerts`.
OpenClaw reasoning triggers only for red/ambiguous states.

### 9.5 Fix
If red, dispatch agent to run `dx-fleet-repair.sh` on failing VMs and re-check.

### 9.6 Rollback
Fleet-wide `--uninstall` path must recover to pre-Fleet-Sync operating mode.

## 10. dx-audit Integration Requirements

Weekly governance checks in `dx-audit` must include:
1. Fleet spec and manifest presence
2. skill stub presence
3. local-first declaration check
4. required service cap check on epyc12
5. forbidden gateway service check
6. tool version drift by VM
7. per-IDE config drift by VM
8. tool health stale/fail (`>24h`) by VM
9. Dolt sync freshness stale (`>60m`) by VM
10. report coverage across all canonical VMs

Recommended runtime safety extension:
- add daily red-only `dx-fleet-check` alert path (fast feedback)

## 11. Failure Scenarios and Expected Behavior

- MCP auth breaks:
  - local stdio tools continue; external provider routes may fail
  - detected by audit/check; repaired via OP-driven rehydrate

- Version drift across VMs:
  - detected as manifest mismatch
  - repaired by re-pin/reinstall via repair script

- IDE config drift:
  - detected via hash mismatch
  - repaired by render/replace from manifest templates

- VM wipe (e.g., epyc6 reinstall):
  - one command bootstrap (`dx-fleet-install.sh`) restores tooling/config

- epyc12 Dolt outage:
  - local tools continue; cross-learning pauses
  - same failure envelope as existing Beads/Dolt operations

## 12. Performance Gates (Must be measurable)

Capture baseline before deployment:
- PR reject rate
- multi-VM repeated-bug recurrence

Post-deploy gates:
- Gate A (quality): PR reject trend decreases
- Gate B (cross-learning): repeated multi-VM bug loops decrease
- Gate C (ops burden): founder Fleet Sync overhead <= 30 min/week
- Gate D (reliability): one VM failure does not degrade other 12 agents

If gates regress materially for 2 consecutive weeks, trigger rollback/scope reduction.

## 13. Acceptance Criteria

1. Spec reflects local-first execution and optional centralized small state.
2. Fleet Sync scripts and manifests are concrete enough for direct agent implementation.
3. Big-bang deploy + verify + repair + rollback model is explicit.
4. Weekly `dx-audit` integration covers drift/health/auth/service-cap checks.
5. Epic/subtasks encode dependencies and completion gates clearly.
