---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: acda9791b30c2533550101bcc180d3def3bae86c
last_verified_at: 2026-05-05T01:25:00Z
stale_if_paths:
  - core/**
  - extended/**
  - dispatch/**
  - health/**
  - infra/**
  - railway/**
  - configs/semantic-index/**
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
5. Repo-memory refresh tooling audits architecture maps and opens narrow
   doc-only PRs when those maps fall behind mapped source changes.
6. Optional warmed semantic search is scoped by
   `configs/semantic-index/repositories.json`; active cache surfaces include
   `agent-skills`, `prime-radiant-ai`, `affordabot`, `llm-common`, and
   `bd-symphony`.

## Current Orchestration Boundary

1. `dx-loop` owns the default agent-facing orchestration workflow for chained
   Beads work, implement/review loops, PR-aware follow-up, and autonomous
   "continue until reviewed or blocked" sessions.
2. `dx-runner` owns provider execution, preflight, status, reports, and failure
   taxonomy. Higher-level orchestrators call it rather than duplicating provider
   semantics.
3. `dx-batch` remains a legacy compatibility and internal batch substrate. It
   is still shipped, but new agent-facing guidance should route to `dx-loop`
   first unless a task is explicitly maintaining batch internals.
4. `dx-wave` is an operator/compatibility wrapper over the legacy batch
   substrate, not the default agent path.

## Brownfield Entry Points

For changes that touch architecture or workflow behavior, read in this order:

1. `AGENTS.local.md` (if present) or `AGENTS.md`
2. `docs/architecture/DATA_AND_STORAGE.md`
3. `docs/architecture/WORKFLOWS_AND_PATTERNS.md`
4. relevant `SKILL.md` files in the affected namespace
5. source verification using `rg` + direct file reads (optionally `scripts/semantic-search query` when status is `ready`)

## Railway Skill Notes

- `railway/affordabot-topology/SKILL.md` is the canonical non-secret topology
  reference for Affordabot dev Railway context. It captures project,
  environment, service ids, public dev domains, `searxng-private`, and safe
  cache-backed auth/link commands so agents do not block on rediscovery or use
  raw 1Password commands.
- `railway/prime-radiant-topology/SKILL.md` is the matching non-secret topology
  reference for Prime Radiant AI dev Railway context. It captures project,
  environment, service ids, screenshot-visible dev domains, Postgres/pgvector,
  MinIO, Windmill LSP, and safe cache-backed auth/link commands.

## Current High-Risk Zones

- baseline generation and AGENTS compilation scripts
- review/orchestration templates under `templates/dx-review`
- `dx-review` skill and wrapper policy: current review quorum is OpenCode-only:
  `opencode-go/kimi-k2.6` plus `opencode-go/deepseek-v4-pro`. cc-glm, Gemini,
  and Claude are not part of the default dx-review surface even though
  `dx-runner` may still expose those providers for other workflows.
- routing contracts for `rg`/semantic-search readiness, Serena, and Beads runtime assumptions
- Fleet Sync skill guidance is an active routing surface: it must describe
  semantic search as optional warmed hints via `scripts/semantic-search`, not
  as an MCP tool or legacy semantic prewarm path.
- scripts that enforce cross-repo policy (`dx-*` checks, dispatch helpers)
- stale "canonical dx-batch" wording in generated baselines, skill metadata,
  or wrapper help text; treat this as policy drift and route through the
  baseline source fragments rather than editing generated artifacts directly
- repo-memory automation (`dx-repo-memory-*`, systemd templates, and Codex
  prompts); keep this path conservative because it is allowed to create
  scheduled documentation PRs

## AGENTS Routing Integration Note

Expected link target for AGENTS routing:

- `docs/architecture/BROWNFIELD_MAP.md`

This file should be linked from AGENTS routing text in a centralized baseline
regeneration pass, not by ad hoc local edits.
