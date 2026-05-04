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

- use warmed `scripts/semantic-search` only as optional semantic hints when
  status is `ready`; if it returns `missing`, `indexing`, or `stale`, use `rg`
  and direct reads
- do not index from the live query path; scheduled `scripts/semantic-index-refresh`
  and its `scripts/dx-ccc-refresh` alias own ccc index updates under
  `~/.cache/agent-semantic-indexes/`
- use bounded helper tools only when they are available and useful; do not
  require legacy semantic prewarm paths for normal repo discovery
- use Serena for symbol-aware edits where symbol safety matters
- use patch/diff edits for non-symbolic changes

## Core Pattern: Canonical Semantic Indexes

- ccc semantic indexes are warmed from non-canonical cache clones, not from
  per-PR worktrees.
- worktree queries resolve back to the allowlisted canonical repo name and use
  the warmed canonical HEAD as the semantic baseline.
- the approved cache layout is
  `~/.cache/agent-semantic-indexes/<repo-name>/{repo,coco-global,state.json,refresh.log,refresh.lock}`.
- agent status is metadata-only and agent query uses a bounded direct read of
  the warmed ccc SQLite index; ordinary agents must not call raw `ccc status`,
  `ccc search`, or `ccc index`.
- worktree setup does not launch semantic prewarm jobs. Hourly canonical
  refresh is installed by `scripts/dx-spoke-cron-install.sh` through
  `scripts/semantic-index-cron.sh`.
- `extended/wooyun-legacy/` was removed because the generated reference corpus
  made `agent-skills` semantic indexing operationally impractical and was not
  part of the active default skill workflow.

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
`dx-review` itself is a thin dispatcher over `dx-runner`: it reads reviewer
`id/provider/model` rows from `configs/dx-review/default.yaml` and passes each
configured lane through `dx-runner --provider <provider> --model <model>`.
The default YAML currently contains only OpenCode Kimi K2.6 and DeepSeek V4 Pro;
cc-glm, Gemini, and Claude are intentionally not part of the default quorum.

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
