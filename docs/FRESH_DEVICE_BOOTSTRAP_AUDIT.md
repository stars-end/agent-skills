# Fresh Device Bootstrap Audit and Deprecation Map

Feature-Key: `bd-0oal8.1`
Scope: stale fresh-device/bootstrap surfaces only (no behavioral script changes)

## Decision Categories

- `canonical`: keep as active contract surface.
- `compatibility shim`: keep callable for now, but only as a delegating wrapper.
- `deprecate loudly`: keep present but fail/exit with explicit migration guidance.
- `candidate delete after HITL`: removable once explicit human approval lands.
- `needs strategic HITL decision`: architecture/policy choice, not a docs-only change.

## Active Contract (Current Truth)

- Worktree-first mutating workflow: `/tmp/agents/<beads-id>/<repo>` and macOS-resolved `/private/tmp/agents/<beads-id>/<repo>`.
- Beads runtime truth: `~/.beads-runtime/.beads`.
- Beads coordination command surface: `bdx` (transport/safety wrapper) to hub host `epyc12`.
- `~/beads` is Beads source/build checkout; `~/bd` is legacy/rollback state only.
- MCP routing contract: `llm-tldr` for semantic/static analysis, `serena` for symbol-aware edits.
- `llm-tldr` locality rule: analysis runs on the host that can read the path; do not send Mac-local worktree paths to an `epyc12`-hosted process unless mirrored.
- Auth topology: `epyc12` is OP cache refresh source; spokes sync cache artifacts.
- macOS GUI `op` (`op signin`, `op whoami`) is human bootstrap/recovery only.
- Host scheduling: cron/systemd by role; legacy `io.agentskills.ru` LaunchAgent must stay disabled.
- Remote access priority: Tailscale SSH.

## Required Scope Classification

| Surface | Category | Why | Follow-up action |
|---|---|---|---|
| `scripts/bootstrap-agent.sh` | compatibility shim | Legacy one-liner that chains `dx-hydrate` + `dx-check`; already marked deprecated in header. | Retain as thin delegate to future role-aware bootstrap entrypoint. |
| `scripts/dx-hydrate.sh` | needs strategic HITL decision | Too broad (bins, cron, aliases, services, launchd policy, optional stacks) and currently acts as control-plane installer. | Split into role-aware primitives before hard deprecation. |
| `scripts/pre-flight-all.sh` | deprecate loudly | V4.2.1 wording and VM assumptions; not aligned to V8.6 role-aware contract. | Convert to explicit deprecation wrapper that points to canonical checks. |
| `scripts/pre-flight-1password.sh` | candidate delete after HITL | Legacy direct `op whoami` checks across hosts; conflicts with cache/service-account-first agent contract. | Replace with `dx-bootstrap-auth.sh --json` + `dx-op-auth-status.sh --json` flow. |
| `scripts/pre-flight-gh-cli.sh` | candidate delete after HITL | Legacy direct remote host loop for GH login; not part of fresh-device P0 bootstrap. | Move to optional diagnostics or remove after approval. |
| `scripts/pre-flight-ides.sh` | candidate delete after HITL | Legacy IDE inventory script (`V4.2.1` label), weak coupling to current MCP hydration model. | Replace with `dx-check` + `mcp-doctor` role-specific checks. |
| `scripts/pre-flight-network.sh` | compatibility shim | Simple connectivity probe still useful, but not canonical bootstrap gate. | Keep as optional helper, no longer primary setup entrypoint. |
| `scripts/pre-flight-railway.sh` | canonical | Uses canonical railway requirements checker in non-interactive mode. | Keep; reference from role-aware bootstrap smoke stage. |
| `scripts/pre-flight-ssh-keys.sh` | compatibility shim | Delegates to deprecated-for-canonical `ssh-key-doctor`; useful for non-Tailscale targets only. | Keep as non-canonical helper and update message text if needed later. |
| `scripts/pre-flight-ssh-path.sh` | candidate delete after HITL | Legacy PATH checks around SSH key workflows and `~/.agent/skills`. | Replace with `ensure-shell-path.sh` + `dx-check` checks. |
| `scripts/dx-check.sh` | canonical | Current integrated preflight for `bdx`, Beads runtime defaults, MCP visibility, launchd policy hygiene, and role checks. | Keep as primary verification surface. |
| `scripts/dx-ensure-bins.sh` | canonical | Idempotent link installer for current tool surfaces including `bdx`. | Keep. |
| `scripts/dx-spoke-cron-install.sh` | canonical | Role-aware spoke cron install including OP cache sync from `epyc12`. | Keep. |
| `scripts/dx-sync-op-caches.sh` | canonical | Spoke cache sync path from central source. | Keep. |
| `scripts/dx-refresh-op-caches.sh` | canonical | Hub refresh path; expected on `epyc12` only. | Keep. |
| `scripts/migrate-to-external-beads.sh` | deprecate loudly | Historical migration script for old external-beads flow; no longer active topology. | Convert to hard-exit notice with runbook pointer in cleanup wave. |
| `scripts/rollout-external-beads-all-vms.sh` | deprecate loudly | Historical orchestrator for deprecated migration. | Convert to hard-exit notice with runbook pointer in cleanup wave. |
| `scripts/setup-env-from-1password.sh` | deprecate loudly | Already marked historical/deprecated and based on old monolithic flow. | Keep only with explicit no-op/deprecation guidance. |
| `scripts/setup-env-opencode.sh` | needs strategic HITL decision | Still uses live `op` lookups and interactive assumptions; conflicts with strict cache/service-account-first automation goals. | Decide if this remains human-only or is replaced by cache-backed generation path. |
| `scripts/setup-env-slack-coordinator.sh` | needs strategic HITL decision | Same as above. | Same decision as opencode env script. |
| `scripts/setup-git-hooks.sh` | candidate delete after HITL | Push hook writes legacy `bd sync` behavior and V5 assumptions. Not aligned with current Beads/runtime contract. | Remove or replace after explicit approval. |
| `scripts/setup-slack-mcp.sh` | compatibility shim | Useful optional helper, but V4.2.1 framing and broad IDE mutation are stale. | Keep as optional helper, refresh docs later. |
| `scripts/install-ru.sh` | canonical | Minimal, idempotent tool installer for `ru`, no secrets. | Keep. |
| `infra/vm-bootstrap/SKILL.md` | canonical (Linux adapter) | Explicitly Linux-only and points to this audit for cross-host contract. | Keep as Linux adapter under unified bootstrap contract. |
| `infra/fleet-sync/SKILL.md` | canonical | Current MCP convergence/source-of-truth skill, including llm-tldr containment details. | Keep. |
| `health/mcp-doctor/SKILL.md` | needs strategic HITL decision | Still documents `context-plus` launcher contract in active skill text, conflicting with removed/tombstoned context-plus policy. | Decide whether to fully remove context-plus references from active doctor contract now. |
| `health/bd-doctor/SKILL.md` | canonical | Current Beads diagnosis contract: `bdx`, `~/.beads-runtime/.beads`, epyc12 hub, readiness caveats. | Keep. |
| `health/dx-cron/SKILL.md` | canonical | Current cron/log observability surface with canonical cleanup expectations. | Keep. |
| `core/op-secrets-quickref/SKILL.md` | canonical | Current auth mode matrix reflects GUI-human vs cache/service-account agent paths and epyc12 hub refresh rule. | Keep. |
| `extended/worktree-workflow/SKILL.md` | canonical | Current workspace-first contract and canonical repo protection. | Keep. |
| `docs/runbook/fleet-sync/` | needs strategic HITL decision | Historical evidence/docs still include `context-plus` references; some are historical records, some appear in active matrices. | Decide historical archive policy vs active runbook cleanup boundary. |

## Stale Reference Inventory (Observed)

The following stale themes are still present and should be handled in later cleanup tasks:

- `context-plus` appears in active-adjacent docs under `docs/runbook/fleet-sync/` and in `health/mcp-doctor/SKILL.md`.
- V4.2.1 labels remain in `pre-flight-*` and `setup-slack-mcp.sh`.
- Historical Beads migration scripts (`migrate-to-external-beads.sh`, `rollout-external-beads-all-vms.sh`) still look executable despite top-of-file warnings.
- `bd sync` still exists in `scripts/setup-git-hooks.sh` and conflicts with current central Dolt runtime contract.
- Legacy mounts (`~/.agent/skills`) remain as compatibility behavior in `dx-hydrate.sh`.

## llm-tldr Bounded Fallback Requirement

### Current finding on this Mac

- GNU `timeout` is now installed at `/Users/fning/.local/bin/timeout`.
- A bounded semantic fallback smoke with `tldr-daemon-fallback.sh` still timed out at 25s.
- This is acceptable only if failure is bounded and the workflow falls back cleanly to direct source inspection; hanging indefinitely is not acceptable.

### Required bootstrap checks going forward

Every fresh-device bootstrap smoke must assert:

1. `timeout` is available (`timeout --version` should succeed).
2. `llm-tldr` fallback calls are wrapped in bounded timeout.
3. On timeout, scripts return a clear reason and proceed to documented fallback path (for example targeted `rg`/direct reads), rather than hanging.
4. MCP locality rule is explicit: host-local path analyzed on same host unless mirrored.

## Smoke Coverage Requirements (macOS + Linux)

Fresh-device acceptance must include both a macOS client and one Linux spoke:

- macOS client smoke:
  - `bdx dolt test --json`
  - `bdx show <known-id> --json`
  - runtime MCP visibility for `llm-tldr` and `serena`
  - bounded `llm-tldr` fallback smoke with timeout behavior recorded
  - `dx-bootstrap-auth.sh --json` returns `agent_ready_cache` or `agent_ready_service_account`
  - verify no `io.agentskills.ru` LaunchAgent active

- Linux spoke smoke:
  - same Beads checks (`bdx dolt test` + targeted `bdx show`)
  - OP cache sync path from `epyc12` validated
  - cron entries align with spoke profile (`dx-spoke-cron-install.sh`)
  - bounded `llm-tldr` fallback smoke behavior validated

## Strategic HITL Decisions Required Before Cleanup Wave

1. `dx-hydrate.sh` decomposition strategy:
   - one role-aware bootstrap entrypoint vs multiple host-role scripts.
2. Active handling for `context-plus` historical traces:
   - keep in evidence-only files vs remove from active runbook/skill contracts.
3. Fate of legacy pre-flight suite:
   - retain as compatibility wrappers vs delete after migration to `dx-check` + role-specific smoke.
4. `setup-env-*` live `op` behavior:
   - keep as human-only utilities or convert to cache/service-account-aware generation.
5. `setup-git-hooks.sh`:
   - remove (preferred) or rewrite against current Beads contract.

## Guardrail for This Subtask

This audit intentionally does not delete scripts, change cron behavior, or alter auth/runtime behavior.
It is a decision-prep map for the follow-on cleanup tasks in `bd-0oal8`.
