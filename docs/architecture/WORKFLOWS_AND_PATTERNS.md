---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 456268c093c0ef8af369f9bdcc68faad485ef146
last_verified_at: 2026-05-05T14:08:00Z
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
- canonical fleet repos are `agent-skills`, `prime-radiant-ai`, `affordabot`,
  `llm-common`, and `bd-symphony`
- canonical branch handling is repo-aware: existing stars-end repos track
  `master`, while `bd-symphony` tracks `main`
- canonical fetch/sync/evacuation/worktree cleanup scripts must use
  `scripts/lib/canonical-git-remotes.sh` for branch and origin decisions rather
  than assuming `origin/master`
- routine canonical hook installation writes only untracked `.git/hooks/*`;
  updating tracked `.githooks/pre-commit` or `.githooks/commit-msg` requires
  explicit `scripts/install-canonical-precommit.sh --update-versioned` or
  `DX_UPDATE_VERSIONED_GITHOOKS=1` so bootstrap cannot dirty every canonical
  repo by default
- `scripts/dx-verify-clean.sh` is allowed one narrow self-heal: if a canonical
  clone is on its expected branch and the only dirty paths are generated
  `.githooks/commit-msg` or `.githooks/pre-commit`, it restores those files
  from HEAD and rechecks. Real source dirt, mixed hook+source dirt, off-branch
  repos, semantic artifacts, and strict stash checks still block.

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
  `agent-skills`, `affordabot`, `prime-radiant-ai`, `llm-common`, and
  `bd-symphony`.
- The epyc12 systemd timer is the primary automation surface; macmini is a
  Tailscale SSH fallback for the same scripts and prompt.
- Timer installation is a deployment step after the script is present in the
  canonical checkout; PR branches should ship the service/timer files without
  enabling them.

## Core Pattern: Codex Session Health Cron

- `dx-codex-session-repair.sh` is the host-local backup-first session JSONL
  scanner/repair wrapper. It delegates to `dx-codex-session-repair.py` and
  `lib/codex_session_repair.py`.
- Installed daily cron entries must call the tracked wrapper from the canonical
  checkout through `dx-job-wrapper.sh`; cron installation without the tracked
  script present is invalid because canonical sync can remove unmerged files.
- Repair mode skips recently modified sessions by default, writes a JSON
  report, and creates backups before in-place edits.
- `dx-codex-weekly-health.sh` is read-only fleet health summarization over
  Codex version, app-server age, stale browser processes, and the latest
  session-repair report. `dx-codex-weekly-health-cron.sh` sends that summary
  through the deterministic Slack alert transport.
- These scripts are operational guardrails for Codex Desktop/CLI health; they
  do not replace Beads, repo-memory maps, or product test suites.

## Pilot Adoption Checklist

- map docs exist and are linked by AGENTS routing policy
- stale-if coverage exists for map docs
- brownfield tasks route through map docs first
- review prompts check repo-memory compliance
