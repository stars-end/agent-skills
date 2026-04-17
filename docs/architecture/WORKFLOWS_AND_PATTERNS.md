---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 7dd26996c0336790a68338bddddf73d090437341
last_verified_at: 2026-04-17T05:48:13Z
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
- `SKILL.md` files must keep YAML frontmatter at the top of file for loader
  compatibility
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
`dx-review` itself is a thin dispatcher: it runs the GLM lane through
`cc-glm-review`, falls back to `opencode-review` for that GLM lane when needed,
and runs Gemini as the second default review lane. Claude is intentionally not
part of the dx-review quorum; do not reintroduce Claude by editing tests or
generated baseline text without a new explicit policy change.

Architecture review should evaluate:

- ownership boundary clarity
- contract stability
- dependency direction
- operational ergonomics
- complexity budget
- repo-memory compliance for brownfield work

## Core Pattern: Scheduled Repo-Memory Refresh

- `dx-repo-memory-check` is the deterministic gate for map freshness.
- `dx-repo-memory-refresh` is the scheduled agent runner: audit first, invoke
  Codex only when action is needed, and restrict committed changes to
  `docs/architecture/`, `AGENTS.md`, and `AGENTS.local.md`.
- `dx-repo-memory-refresh-all` is the fleet wrapper for canonical repos:
  `agent-skills`, `affordabot`, `prime-radiant-ai`, and `llm-common`.
- The epyc12 systemd timer is the primary automation surface; macmini is a
  Tailscale SSH fallback for the same scripts and prompt.
- Timer installation is a deployment step after the script is present in the
  canonical checkout; PR branches should ship the service/timer files without
  enabling them.

## Pilot Adoption Checklist

- map docs exist and are linked by AGENTS routing policy
- stale-if coverage exists for map docs
- brownfield tasks route through map docs first
- review prompts check repo-memory compliance
