---
status: active
owner: dx-architecture
last_verified_commit: e90ac84583a457cc2b3580fee522fb2a047c10b7
last_verified_at: 2026-04-15T21:20:00Z
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

## Memory Surface Policy

- Repo-owned architecture docs are canonical brownfield maps.
- Beads KV/structured memory are pointer and decision surfaces.
- Skills are workflow guidance only.
- `llm-tldr` verifies source; Serena edits symbols.

## What This Repo Does Not Own

- Product runtime databases for application repos
- central infrastructure service state beyond runbook contracts
- raw analysis datasets from downstream product repos

## Pilot Scope Notes

For this pilot, "storage" is intentionally lightweight:

- map where knowledge is stored
- define stale-if ownership
- avoid introducing new storage backends or memory wrappers

