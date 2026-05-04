---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: e783d9f0543065576081b531db15bda01e07d026
last_verified_at: 2026-05-04T14:45:00Z
stale_if_paths:
  - docs/**
  - scripts/**
  - configs/semantic-index/**
  - templates/**
  - core/beads-memory/**
  - docs/llm-tldr-removal-inventory-bd-9n1t2.33.md
  - extended/serena/**
---

# Data And Storage

This repo is mostly workflow code and docs, but it still has multiple data
surfaces. This file records their ownership boundaries.

## Canonical Data Surfaces

1. Repository files
   - source of truth for skills, scripts, templates, and docs
   - versioned by git; reviewable in PRs
   - handoff runbooks and delegated prompts under `docs/runbook/` and
     `docs/prompts/` are portable context surfaces, not runtime state
   - non-secret product topology can live in targeted skills, such as the
     Affordabot and Prime Radiant AI Railway dev topology skills; credentials
     and tokens remain external runtime state behind cache-backed auth helpers
2. Beads runtime state
   - active runtime path: `~/.beads-runtime/.beads`
   - durable records live in shared Dolt server backend configured by runtime
3. External tool state (not committed)
   - runtime caches are operational state, not canonical repo memory
   - `ccc` / CocoIndex Code semantic index state lives under
     `~/.cache/agent-semantic-indexes/<repo-name>/` when the optional
     semantic-hints lane is enabled
   - owner: semantic index refresh workflow (`scripts/semantic-index-refresh`)
   - contents: non-canonical `repo/`, repo-scoped `coco-global/`,
     `state.json`, `refresh.log`, and `refresh.lock`
   - ccc project DB/settings are expected under
     `repo/.cocoindex_code/` for current ccc versions; `coco-global/` is the
     repo-scoped `COCOINDEX_CODE_DIR` daemon/global state
   - ordinary `scripts/semantic-search status/query` calls are read-only over
     this warmed state; init/index/refresh remains infra-owned
   - rollback: disable scheduler, then remove or rename
     `~/.cache/agent-semantic-indexes`
4. Orchestration runtime state (not committed)
   - `dx-loop` runtime artifacts live outside the repo and are operational
     coordination state
   - `dx-runner` reports/logs live outside the repo and are provider execution
     evidence, not canonical product memory
   - `dx-review` summary and reviewer artifacts live under `/tmp/dx-review`
     and `/tmp/dx-runner`; default review execution is configured by
     `configs/dx-review/default.yaml`, and these runtime artifacts are
     disposable review evidence while the durable contract is the repo-reviewed
     wrapper, skill, config, and template files
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
- `rg` + direct reads verify source; Serena edits symbols.
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
