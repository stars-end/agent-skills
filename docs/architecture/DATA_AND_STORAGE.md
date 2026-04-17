---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 7dd26996c0336790a68338bddddf73d090437341
last_verified_at: 2026-04-17T05:48:13Z
stale_if_paths:
  - docs/**
  - scripts/**
  - templates/**
  - core/beads-memory/**
  - extended/llm-tldr/**
  - extended/serena/**
---

# Data And Storage

This repo is mostly workflow code and docs, but it still has multiple data
surfaces. This file records their ownership boundaries.

## Canonical Data Surfaces

1. Repository files
   - source of truth for skills, scripts, templates, and docs
   - versioned by git; reviewable in PRs
2. Beads runtime state
   - active runtime path: `~/.beads-runtime/.beads`
   - durable records live in shared Dolt server backend configured by runtime
3. External tool state (not committed)
   - e.g., `llm-tldr` contained state under external cache locations
   - runtime caches are operational state, not canonical repo memory
4. Orchestration runtime state (not committed)
   - `dx-loop` runtime artifacts live outside the repo and are operational
     coordination state
   - `dx-runner` reports/logs live outside the repo and are provider execution
     evidence, not canonical product memory
   - `dx-review` summary and reviewer artifacts live under `/tmp/dx-review`
     and `/tmp/dx-runner`; they are disposable review evidence, while the
     durable contract is the repo-reviewed wrapper, skill, and template files
   - `dx-batch`/`dx-wave` artifacts are legacy compatibility or operator
     substrate state and should not be treated as the default agent workflow
     record
5. Repo-memory refresh state (not committed)
   - `dx-repo-memory-refresh` and `dx-repo-memory-refresh-all` store run
     reports and generated worktrees under the configured state root,
     defaulting to `~/.dx-state/repo-memory`
   - scheduled runs create Git branches and draft PRs for reviewable doc
     changes; runtime logs and lock files are operational evidence, not
     canonical memory

## Memory Surface Policy

- Repo-owned architecture docs are canonical brownfield maps.
- Beads KV/structured memory are pointer and decision surfaces.
- Skills are workflow guidance only.
- `llm-tldr` verifies source; Serena edits symbols.
- Scheduled Codex refreshes may update repo-owned map docs, but the accepted
  memory surface remains git-reviewed Markdown rather than a separate agent
  memory database.

## What This Repo Does Not Own

- Product runtime databases for application repos
- central infrastructure service state beyond runbook contracts
- raw analysis datasets from downstream product repos

## Pilot Scope Notes

For this pilot, "storage" is intentionally lightweight:

- map where knowledge is stored
- define stale-if ownership
- avoid introducing new storage backends or memory wrappers
