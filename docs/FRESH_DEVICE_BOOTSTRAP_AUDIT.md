# Fresh Device Bootstrap Audit

This document records the active setup contract and the stale bootstrap surfaces
that should be deprecated or converted to shims.

## Active Contract

- Worktrees: `/tmp/agents/<beads-id>/<repo>` and macOS-resolved
  `/private/tmp/agents/<beads-id>/<repo>`.
- Beads runtime: `~/.beads-runtime/.beads`, backed by the central `epyc12` Dolt
  SQL hub.
- Beads source checkout: `~/beads`; `~/bd` is legacy/rollback control-plane
  state only.
- MCP discovery: `llm-tldr` is the canonical analysis tool and `serena` is the
  canonical symbol-aware edit tool.
- `llm-tldr` path rule: use host-local contained MCP on the machine that owns
  the worktree. If compute must happen on `epyc12`, create or mirror the
  worktree there first.
- Remote access: prefer Tailscale SSH for canonical host work.
- 1Password auth:
  - macOS GUI-backed `op` is for human bootstrap/recovery only.
  - Human macOS shells may need `op signin` once after each device/1Password
    unlock before `op whoami` works.
  - agents, cron, and fleet scripts must use synced OP cache artifacts or a
    service-account credential.
  - `epyc12` is the unattended OP cache refresh hub; consumer hosts should be
    cache-only whenever possible.
- Schedules: cron/systemd by host role; no LaunchAgent `ru` policy on macOS.
- Canonical Git remotes: canonical repos on each host should use GitHub SSH
  origins (`git@github.com:stars-end/<repo>.git`) so non-interactive cleanup
  cron rescue pushes never block on HTTPS credential prompts.
- Shell startup: no health checks, MCP checks, browser dashboards, or service
  starts from `.zshrc`, `.zshenv`, `.bashrc`, or `.bash_profile`.

## Surfaces To Deprecate

| Surface | Current Problem | Forward Path |
|---------|-----------------|--------------|
| `scripts/bootstrap-agent.sh` | Calls `dx-hydrate.sh`, sources `.bashrc`, then runs `dx-check.sh`; this inherits stale bootstrap behavior and can trigger heavy checks on a fresh device. | Replace with a thin shim to a role-aware bootstrap entrypoint. |
| `scripts/dx-hydrate.sh` | Mixed installer, cron writer, shell RC editor, worktree directory creator, OpenCode service installer, and optional memory setup. It is too broad for fresh-device setup. | Split into small idempotent primitives: bin links, schedules, MCP render, auth cache, Beads runtime, shell PATH only. |
| `infra/vm-bootstrap/install.sh` | Linux-only and stale for Beads/auth; no macOS path despite fresh Mac devices being first-class. | Keep as Linux adapter under a shared bootstrap contract; add macOS adapter. |
| `infra/vm-bootstrap/verify.sh` | Verifies ambient tools but not the current Beads runtime, epyc12 Dolt health, central/local MCP path locality, or OP cache flow. | Extend as role-aware verifier and stop treating `bd --version` as enough. |
| `session-start-hooks/claude-code-dx-bootstrap.sh` | Performs `git pull` and runs `dx-check` on session start. This mutates repos and can spawn expensive checks before the agent has context. | Deprecate for a lightweight warning-only canonical-root guard. |
| `session-start-hooks/dx-bootstrap.sh` | Warning-only canonical-root guard; now includes `/private/tmp/agents` awareness but remains a legacy hook surface. | Keep only as a warning shim. |
| `scripts/dx-schedule-install.sh` | Already marked V7.8-only and references removed schedule directories. | Leave archived or convert to hard deprecation exit. |
| `scripts/migrate-to-external-beads.sh` | Historical external Beads DB migration path; superseded by epyc12 Dolt SQL hub runtime. | Archive or mark rollback-only. |
| `scripts/rollout-external-beads-all-vms.sh` | Historical rollout wrapper for the old Beads migration path. | Archive or mark rollback-only. |
| `scripts/bd-sync-safe.sh` | Legacy Git/JSONL sync wrapper; active Beads runtime is Dolt server mode. | Keep only as explicit legacy rollback tool; do not link as active bootstrap. |
| `docs/START_HERE.md` | Still advertises `bootstrap-agent.sh` and `dx-hydrate.sh` as normal fresh-device setup. | Replace with role-aware fresh-device instructions. |

## Next Script Shape

Create one role-aware entrypoint, then make stale surfaces call it or refuse
with a clear deprecation message:

```bash
scripts/dx-bootstrap.sh --role macos-client
scripts/dx-bootstrap.sh --role linux-spoke
scripts/dx-bootstrap.sh --role epyc12-hub
```

The entrypoint should run these phases explicitly:

1. `dx-link-bins`: install links into `~/.local/bin` or `~/bin`.
2. `dx-bootstrap-beads`: create `~/.beads-runtime/.beads` metadata/config and
   verify `bd dolt test --json`.
3. `dx-bootstrap-auth`: run `dx-bootstrap-auth.sh --json`; accept
   `agent_ready_cache` or `agent_ready_service_account`, otherwise sync OP
   cache artifacts from `epyc12` and re-check. `human_interactive_only` is
   acceptable only during Mac human bootstrap.
4. `dx-render-mcp`: render MCP configs appropriate for the host/client role.
5. `dx-install-schedules`: install only the schedules for the detected host
   role.
6. `dx-bootstrap-smoke`: prove `bd`, `op`, `railway`, `llm-tldr`, `serena`, and
   cron/systemd readiness without mutating repos.

## Fresh Device Acceptance Tests

- `bd dolt test --json` passes and `BEADS_DIR` is `~/.beads-runtime/.beads`.
- `codex mcp list` or runtime-equivalent visibility shows `llm-tldr` and
  `serena`.
- `llm-tldr` MCP is local-contained and tested against a host-local worktree.
- A Mac-local worktree analysis never routes through an `epyc12` MCP process
  unless the worktree is mirrored or mounted there.
- `dx-bootstrap-auth.sh --json` returns green with `agent_ready_cache` or
  `agent_ready_service_account` for agent work.
- macOS `op whoami` may be verified for human bootstrap, but no cron,
  LaunchAgent, shell startup, or agent bootstrap path depends on GUI unlock
  state or a prior `op signin`.
- Opening a new shell does not run `dx-status`, spawn MCP servers, or open a
  Serena dashboard.
- `crontab -l` or `systemctl --user list-timers` matches the host role.
- No setup path requires `~/bd` as the active Beads runtime.
