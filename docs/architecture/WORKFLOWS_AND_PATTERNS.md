---
status: active
owner: dx-architecture
last_verified_commit: f94ee66824c6754c6619aeced3ffc4ce92e34b9c
last_verified_at: 2026-04-15T16:21:14Z
stale_if_paths:
  - core/**
  - extended/**
  - dispatch/**
  - health/**
  - infra/**
  - scripts/**
  - templates/**
---

# Workflows And Patterns

This file captures recurring workflow patterns in `agent-skills` so agents do
not rediscover them from scratch.

## Core Pattern: Workspace-First Changes

- canonical clones are read-mostly
- mutating work happens in worktrees under `/tmp/agents/<beads-id>/<repo>`
- avoid direct canonical writes

## Core Pattern: Skill As Workflow, Not Memory Store

- skills define activation and execution behavior
- repo architecture truth belongs in repo docs
- Beads stores pointers/decisions, not full architecture maps

## Core Pattern: Verify Before Edit

- use `llm-tldr` for semantic and static verification on current source
- use Serena for symbol-aware edits where symbol safety matters
- use patch/diff edits for non-symbolic changes

## Core Pattern: Orchestration Surface Hierarchy

- `dx-loop` is the default agent-facing surface for chained Beads work,
  implement/review baton flows, PR-aware follow-up, and "keep going until
  reviewed or blocked" work.
- `dx-runner` is the lower-level provider runner. Use it directly for
  provider preflight, diagnostics, and one-off governed provider execution.
- `dx-batch` is a legacy compatibility and internal substrate. It remains
  installed for existing operators and wrappers, but agents should not choose
  it first for new orchestration work.
- `dx-wave` is a compatibility/operator entrypoint over the legacy batch
  substrate, not the preferred agent entrypoint.

## Core Pattern: Review Contracts

Templates under `templates/dx-review/` define expected reviewer behavior.
Architecture review should evaluate:

- ownership boundary clarity
- contract stability
- dependency direction
- operational ergonomics
- complexity budget
- repo-memory compliance for brownfield work

## Pilot Adoption Checklist

- map docs exist and are linked by AGENTS routing policy
- stale-if coverage exists for map docs
- brownfield tasks route through map docs first
- review prompts check repo-memory compliance
