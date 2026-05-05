---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 4083dafd480091af5b83019e6b00cb95ffe614ed
last_verified_at: 2026-05-05T23:45:07Z
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

## Core Pattern: Goal-Seeking Eval Loops

- `extended/goal-seeking-eval-loop/` is for bounded optimization campaigns, not
  ordinary implementation waves.
- A campaign must define the fixed eval set, eval version/hash, scalar score,
  score dimensions, hard gates, final acceptance criteria, mutable/frozen
  surfaces, max cycles, subagent budget, artifact root, and keep/discard rule
  before the first mutation.
- Each cycle must produce a scored delta, keep/discard decision, post-mortem,
  and next-cycle plan. Activity without a measured delta is not progress.
- The skill may dispatch Codex subagents or route through `dx-loop`/`dx-runner`,
  but provider execution, Beads/worktree governance, commits, and PR mechanics
  remain owned by the existing DX surfaces.
- The helper scripts under `extended/goal-seeking-eval-loop/scripts/` are local
  utilities for artifact initialization and deterministic score aggregation;
  they are not a separate service or durable state store.
- The Affordabot reference in `resources/affordabot.md` is an example of the
  pattern: real structured/unstructured evidence is not accepted as a data moat
  proof until it reaches the canonical economic-analysis and admin/HITL path.

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
- `dx-codex-session-repair-cron-install.sh` owns per-host nightly install
  schedules for macmini, epyc12, and epyc6. `dx-codex-weekly-health-cron-install.sh`
  owns weekly health digest installation for macmini and epyc12.
- Repair mode skips recently modified sessions by default, writes a JSON
  report, and creates backups before in-place edits.
- `dx-codex-weekly-health.sh` is read-only fleet health summarization over
  Codex version, app-server age, stale browser processes, and the latest
  session-repair report. `dx-codex-weekly-health-cron.sh` sends that summary
  through the deterministic Slack alert transport.
- These scripts are operational guardrails for Codex Desktop/CLI health; they
  do not replace Beads, repo-memory maps, or product test suites.

## Core Pattern: Deterministic Slack Follow-Ups

- `slack-coordination` is optional, but when agents schedule operational
  follow-ups they should use the deterministic Agent Coordination helpers from
  `scripts/lib/dx-slack-alerts.sh`, not ad hoc Slack clients.
- The default operational destination is `#fleet-events`, currently resolved as
  channel ID `C0A8YU9JW06`; literal channel names can fail in some workspaces,
  so scripts should prefer `agent_coordination_default_channel` or a known ID.
- Cron/systemd follow-up jobs must be non-interactive and cache-only. Use
  `DX_AUTH_CACHE_ONLY=1`, a due-only/idempotent state file, log redirection,
  and the `agent_coordination_transport_ready` readiness check before posting.

## Pilot Adoption Checklist

- map docs exist and are linked by AGENTS routing policy
- stale-if coverage exists for map docs
- brownfield tasks route through map docs first
- review prompts check repo-memory compliance
