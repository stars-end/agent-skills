# Tech-Lead DX + Sync Playbook (2-day hardening target)

This playbook describes the **control plane** workflow for directing 3–4 agents across canonical VMs.

## Core invariants (P0)

1. **Canonical skills mount**
   - `~/.agent/skills -> ~/agent-skills` on every VM.

2. **Canonical clones stay boring**
   - `~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, `~/llm-common` stay **clean** and on **`master`**.
   - All real work happens in worktrees (`/tmp/agents/<beads>/<repo>`) created by `worktree-setup.sh`.

3. **Dispatch is self-sufficient**
   - Before remote worktrees are created, the target VM should have:
     - fresh `~/agent-skills`
     - `~/bin/worktree-setup.sh`, `~/bin/dx-dispatch`, `~/bin/fleet-dispatch` installed

## Tech-lead commands

### Fleet readiness (dashboard)

```bash
dx-fleet-status
```

Shows per-VM:
- agent-skills HEAD
- `dx-status` output (canonical clone discipline + MCP/tooling checks)
- `dx-toolchain check` output (tool version drift + missing binaries)

### Toolchain consistency (local or fleet-wide)

```bash
dx-toolchain check
dx-toolchain ensure

dx-toolchain check --all
dx-toolchain ensure --all
```

Notes:
- `ensure` is best-effort and idempotent.
- `mise` is the preferred way to standardize `gh` and `railway` versions.

### Dispatch

```bash
dx-dispatch epyc6 "Do X" --repo affordabot --beads bd-123
```

Dispatch uses `lib/fleet` worktree setup (isolated branch/workdir) and is resilient to duplicates (idempotency).

## Two-day sprint scope (recommended)

### Day 1 (P0): correctness
- Ensure `dx-hydrate` installs `ru` and `~/bin/*` wrappers.
- Ensure remote dispatch refreshes `agent-skills` and `~/bin` tools before worktree creation.
- Fix pre-flight scripts to avoid platform-specific flags and to use canonical VM targets.

### Day 2 (P1): consistency and visibility
- Pin versions (at least `railway`, `gh`) across VMs (via `mise use -g ...`).
- Add a single “fleet status” command and make it the default tech-lead ritual before dispatching.

