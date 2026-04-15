---
status: active
owner: dx-architecture
last_verified_commit: bed553a7b838847b158a726afbf2ab3df1434e04
last_verified_at: 2026-04-15T16:24:00Z
stale_if_paths:
  - core/**
  - extended/**
  - dispatch/**
  - health/**
  - infra/**
  - railway/**
  - scripts/publish-baseline.zsh
  - scripts/compile_agent_context.sh
  - templates/**
---

# Brownfield Map

This map is the first-stop orientation for `agent-skills` brownfield work.

## System Purpose

`agent-skills` is a canonical workflow and operations toolkit for coding agents.
The repo ships:

- skill definitions and templates (`core/`, `extended/`, `health/`, `infra/`,
  `dispatch/`, `railway/`, `safety/`)
- operational scripts (`scripts/`)
- policy/runbook docs (`docs/`)
- generated distribution artifacts (`dist/`)

## Primary Runtime Boundaries

1. Skills define human-readable task routing and execution contracts.
2. Scripts implement executable DX plumbing and checks.
3. Baseline generation compiles global and repo routing context into `AGENTS.md`
   and publish artifacts.
4. Templates provide prompt/review contract skeletons used by orchestration
   tooling.

## Brownfield Entry Points

For changes that touch architecture or workflow behavior, read in this order:

1. `AGENTS.local.md` (if present) or `AGENTS.md`
2. `docs/architecture/DATA_AND_STORAGE.md`
3. `docs/architecture/WORKFLOWS_AND_PATTERNS.md`
4. relevant `SKILL.md` files in the affected namespace
5. source verification using `llm-tldr`

## Current High-Risk Zones

- baseline generation and AGENTS compilation scripts
- review/orchestration templates under `templates/dx-review`
- routing contracts for `llm-tldr`, Serena, and Beads runtime assumptions
- scripts that enforce cross-repo policy (`dx-*` checks, dispatch helpers)
- model-lane policy across `dx-loop`, `dx-review`, and `dx-runner`; agents
  should see `dx-loop` as the batch/loop surface, `dx-review` as review-only,
  and `dx-runner` as the provider substrate

## AGENTS Routing Integration Note

Expected link target for AGENTS routing:

- `docs/architecture/BROWNFIELD_MAP.md`

This file should be linked from AGENTS routing text in a centralized baseline
regeneration pass, not by ad hoc local edits.
