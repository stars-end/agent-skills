# Fresh Device Bootstrap Audit and Deprecation Map

Feature-Key: `bd-0oal8.2`
Scope: fresh-device/bootstrap cleanup + role-aware entrypoint rollout

## Supersession Note

The previous semantic fallback contract from `bd-0oal8.2` has been superseded.
Current routing uses `rg` and direct reads first, with `scripts/semantic-search`
as an optional warmed semantic hint lane only when status is `ready`. Query and
worktree-creation paths must not trigger semantic indexing.

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
- MCP routing contract: `serena` for symbol-aware edits; semantic hints are optional through `scripts/semantic-search` when status is `ready`.
- Semantic locality rule: warmed indexes are canonical-repo scoped; worktree query paths must not trigger indexing.
- Auth topology: `epyc12` is OP cache refresh source; spokes sync cache artifacts.
- macOS GUI `op` (`op signin`, `op whoami`) is human bootstrap/recovery only.
- Host scheduling: cron/systemd by role; legacy `io.agentskills.ru` LaunchAgent must stay disabled.
- Remote access priority: Tailscale SSH.

## Required Scope Classification

| Surface | Category | Why | Follow-up action |
|---|---|---|---|
| `scripts/dx-bootstrap-device.sh` | canonical | Role-aware fresh-device bootstrap entrypoint for `macos-client`, `linux-spoke`, and `hub-controller`; delegates to existing primitives conservatively. | Keep as conceptual entrypoint for fresh-device setup/check. |
| `scripts/bootstrap-agent.sh` | compatibility shim | Legacy one-liner now delegates directly to `dx-bootstrap-device.sh`. | Keep as thin shim until old prompts are retired. |
| `scripts/dx-hydrate.sh` | compatibility shim | Still broad and legacy, but no longer the conceptual fresh-device entrypoint. | Keep for legacy/install-repair flows only; do not teach as primary setup path. |
| `scripts/pre-flight-all.sh` | deprecate loudly | V4.2.1 wording and VM assumptions; not aligned to V8.6 role-aware contract. | Convert to explicit deprecation wrapper that points to canonical checks. |
| `scripts/pre-flight-1password.sh` | deprecate loudly | Deprecated wrapper now hard-exits and points to agent-safe auth commands. | Remove after one migration cycle. |
| `scripts/pre-flight-gh-cli.sh` | deprecate loudly | Deprecated wrapper now hard-exits and points to canonical checks. | Remove after one migration cycle. |
| `scripts/pre-flight-ides.sh` | deprecate loudly | Deprecated wrapper now hard-exits and points to `dx-check` + `mcp-doctor`. | Remove after one migration cycle. |
| `scripts/pre-flight-network.sh` | compatibility shim | Simple connectivity probe still useful, but not canonical bootstrap gate. | Keep as optional helper, no longer primary setup entrypoint. |
| `scripts/pre-flight-railway.sh` | canonical | Uses canonical railway requirements checker in non-interactive mode. | Keep; reference from role-aware bootstrap smoke stage. |
| `scripts/pre-flight-ssh-keys.sh` | compatibility shim | Delegates to deprecated-for-canonical `ssh-key-doctor`; useful for non-Tailscale targets only. | Keep as non-canonical helper and update message text if needed later. |
| `scripts/pre-flight-ssh-path.sh` | deprecate loudly | Deprecated wrapper now hard-exits and points to `ensure-shell-path.sh` + `dx-check`. | Remove after one migration cycle. |
| `scripts/dx-check.sh` | canonical | Current integrated preflight for `bdx`, Beads runtime defaults, MCP visibility, launchd policy hygiene, and role checks. | Keep as primary verification surface. |
| `scripts/dx-ensure-bins.sh` | canonical | Idempotent link installer for current tool surfaces including `bdx`. | Keep. |
| `scripts/dx-spoke-cron-install.sh` | canonical | Role-aware spoke cron install including OP cache sync from `epyc12`. | Keep. |
| `scripts/dx-sync-op-caches.sh` | canonical | Spoke cache sync path from central source. | Keep. |
| `scripts/dx-refresh-op-caches.sh` | canonical | Hub refresh path; expected on `epyc12` only. | Keep. |
| `scripts/migrate-to-external-beads.sh` | deprecate loudly | Historical migration script for old external-beads flow; no longer active topology. | Convert to hard-exit notice with runbook pointer in cleanup wave. |
| `scripts/rollout-external-beads-all-vms.sh` | deprecate loudly | Historical orchestrator for deprecated migration. | Convert to hard-exit notice with runbook pointer in cleanup wave. |
| `scripts/setup-env-from-1password.sh` | deprecate loudly | Already marked historical/deprecated and based on old monolithic flow. | Keep only with explicit no-op/deprecation guidance. |
| `scripts/setup-env-opencode.sh` | compatibility shim | Marked human-only with TTY guard; blocked for agent/cron use. | Keep as human bootstrap helper; do not route agents here. |
| `scripts/setup-env-slack-coordinator.sh` | compatibility shim | Marked human-only with TTY guard; blocked for agent/cron use. | Keep as human bootstrap helper; do not route agents here. |
| `scripts/setup-git-hooks.sh` | compatibility shim | Hard-deprecated legacy hook installer; now delegates to `dx-git-hooks-bootstrap.sh`. | Keep wrapper for compatibility, no legacy `bd sync` behavior remains. |
| `scripts/setup-slack-mcp.sh` | compatibility shim | Useful optional helper, but V4.2.1 framing and broad IDE mutation are stale. | Keep as optional helper, refresh docs later. |
| `scripts/install-ru.sh` | canonical | Minimal, idempotent tool installer for `ru`, no secrets. | Keep. |
| `infra/vm-bootstrap/SKILL.md` | canonical (Linux adapter) | Explicitly Linux-only and points to this audit for cross-host contract. | Keep as Linux adapter under unified bootstrap contract. |
| `infra/fleet-sync/SKILL.md` | canonical | Current MCP convergence/source-of-truth skill, including optional semantic-search routing details. | Keep. |
| `health/mcp-doctor/SKILL.md` | canonical | Active skill + checker validate the current MCP roster and no longer teach `context-plus` launcher contracts. | Keep. |
| `health/bd-doctor/SKILL.md` | canonical | Current Beads diagnosis contract: `bdx`, `~/.beads-runtime/.beads`, epyc12 hub, readiness caveats. | Keep. |
| `health/dx-cron/SKILL.md` | canonical | Current cron/log observability surface with canonical cleanup expectations. | Keep. |
| `core/op-secrets-quickref/SKILL.md` | canonical | Current auth mode matrix reflects GUI-human vs cache/service-account agent paths and epyc12 hub refresh rule. | Keep. |
| `extended/worktree-workflow/SKILL.md` | canonical | Current workspace-first contract and canonical repo protection. | Keep. |
| `docs/runbook/fleet-sync/` | needs strategic HITL decision | Historical evidence/docs still include `context-plus` references; some are historical records, some appear in active matrices. | Decide historical archive policy vs active runbook cleanup boundary. |

## Stale Reference Inventory (Observed)

The following stale themes are still present and should be handled in later cleanup tasks:

- `context-plus` remains only in tombstone/historical evidence docs; active doctor
  contracts and fleet-sync render templates no longer validate or install it.
- V4.2.1 labels remain in `pre-flight-*` and `setup-slack-mcp.sh`.
- Historical Beads migration scripts (`migrate-to-external-beads.sh`, `rollout-external-beads-all-vms.sh`) still look executable despite top-of-file warnings.
- `bd sync` remains only in historical docs and legacy sync helpers; it is no
  longer installed by `scripts/setup-git-hooks.sh`.
- Legacy mounts (`~/.agent/skills`) remain as compatibility behavior in `dx-hydrate.sh`.

## Semantic Hint Readiness Requirement

Every fresh-device bootstrap smoke must assert:

1. `scripts/semantic-search status` exits cleanly.
2. `scripts/semantic-search query` never starts indexing.
3. When status is not `ready`, agents get the documented fallback path:
   targeted `rg` and direct reads.

## Smoke Coverage Requirements (macOS + Linux)

Fresh-device acceptance must include both a macOS client and one Linux spoke:

- macOS client smoke:
  - `bdx dolt test --json`
  - `bdx show <known-id> --json`
  - runtime MCP visibility for `serena`
  - optional semantic-search status behavior recorded
  - `dx-bootstrap-auth.sh --json` returns `agent_ready_cache` or `agent_ready_service_account`
  - verify no `io.agentskills.ru` LaunchAgent active

- Linux spoke smoke:
  - same Beads checks (`bdx dolt test` + targeted `bdx show`)
  - OP cache sync path from `epyc12` validated
  - cron entries align with spoke profile (`dx-spoke-cron-install.sh`)
  - optional semantic-search status behavior validated

## Cleanup Wave Decisions Implemented

1. `dx-hydrate.sh` decomposition strategy:
   - one role-aware bootstrap entrypoint, `scripts/dx-bootstrap-device.sh`.
2. Active handling for `context-plus` historical traces:
   - keep in evidence-only/tombstone files; remove from active doctor and
     fleet-sync render contracts.
3. Fate of legacy pre-flight suite:
   - retain only precise compatibility helpers; hard-deprecate stale scripts.
4. `setup-env-*` live `op` behavior:
   - keep as human-only utilities; agent/cron paths use cache/service-account
     auth helpers.
5. `setup-git-hooks.sh`:
   - compatibility shim to `dx-git-hooks-bootstrap.sh`; no legacy `bd sync`
     hook behavior remains.

## Remaining Guardrail

This cleanup intentionally keeps compatibility shims instead of silently
deleting old entrypoints. Future deletion should be a separate, explicit
cleanup after one migration cycle.
