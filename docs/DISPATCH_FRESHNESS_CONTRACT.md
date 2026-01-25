# Dispatch Freshness Contract

This document defines the **freshness guarantee** for multi-VM dispatch (`dx-dispatch`) without sacrificing the primary requirement: **never lose work**.

## Goals

- Never lose work when agents forget to commit.
- Keep canonical clones in `~/<repo>` fast-forwardable (clean on trunk) for `ru sync`.
- Make `dx-dispatch` operate on fresh code by default (best-effort, bounded time).

## Canonical model

- Canonical clones live at `~/<repo>` (e.g. `~/affordabot`).
- Canonical clones should stay on trunk (`master`) and clean for automation.
- Workspaces for concurrent/remote agents should live in worktrees (e.g. `/tmp/agents/...`) and are intentionally excluded from `ru sync`.

## Contract (what `dx-dispatch` must do)

Before dispatching work for a target repo:

1) **Auto-checkpoint (best-effort)**
   - If `auto-checkpoint` is available, run it on:
     - `~/agent-skills` (high churn control plane)
     - `~/<target repo>` (if present)
   - Auto-checkpoint commits changes on a WIP branch and restores the repo back to trunk so automation can proceed.

2) **ru sync (best-effort)**
   - Run `ru sync` for:
     - `agent-skills`
     - the `--repo` argument (if provided)
   - If `ru` is missing or times out, continue dispatch (do not block forever) but surface a warning.

3) **Report degradation**
   - If freshness steps fail, `dx-dispatch` should:
     - continue dispatch (bounded, best-effort)
     - annotate the local output (and Slack audit if enabled) with the freshness state

## Non-goals (for now)

- Do not build global locks across VMs in Phase 2/3.
- Do not enforce token freshness (gh/railway/op auth) as hard errors.
- Do not require worktrees for the 80% workflow.

