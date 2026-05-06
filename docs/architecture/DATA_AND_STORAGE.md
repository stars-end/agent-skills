---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 81dfd51cd9a7e6fbad925bdaf6bcbc197790a048
last_verified_at: 2026-05-06T13:08:00Z
stale_if_paths:
  - docs/**
  - scripts/**
  - configs/semantic-index/**
  - templates/**
  - core/beads-memory/**
  - extended/serena/**
---

# Data And Storage

This repo is mostly workflow code and docs, but it still has multiple data
surfaces. This file records their ownership boundaries.

## Canonical Data Surfaces

1. Repository files
   - source of truth for skills, scripts, templates, and docs
   - versioned by git; reviewable in PRs
   - tracked `.githooks/` files are repository policy artifacts, not routine
     bootstrap output; `scripts/install-canonical-precommit.sh` must not update
     them unless the operator explicitly opts into a versioned hook migration
   - handoff runbooks and delegated prompts under `docs/runbook/` and
     `docs/prompts/` are portable context surfaces, not runtime state
   - generated canonical hook drift in `.githooks/commit-msg` and
     `.githooks/pre-commit` is treated as disposable local enforcement state
     when it is the only canonical dirt; `scripts/dx-verify-clean.sh`
     auto-restores those two files from HEAD and still blocks any mixed source
     dirt
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
   - active warmed repo scope is declared in
     `configs/semantic-index/repositories.json` and currently includes
     `agent-skills`, `prime-radiant-ai`, `affordabot`, `llm-common`, and
     `bd-symphony`
   - owner: semantic index refresh workflow (`scripts/semantic-index-refresh`)
   - contents: non-canonical `repo/`, repo-scoped `coco-global/`,
     `state.json`, `refresh.log`, and `refresh.lock`
   - ccc project DB/settings are expected under
     `repo/.cocoindex_code/` for current ccc versions; `coco-global/` is the
     repo-scoped `COCOINDEX_CODE_DIR` daemon/global state
   - ordinary `scripts/semantic-search status/query` calls are read-only over
     this warmed state; init/index/refresh remains infra-owned
   - worktree creation and query paths must not start indexing; spoke cron
     installation owns the scheduled `semantic-index-cron.sh` refresh and
     prunes legacy semantic prewarm entries
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
   - deterministic Agent Coordination/Slack follow-ups are operational
     notifications, not repo state. Skill docs should route scheduled posts
     through `scripts/lib/dx-slack-alerts.sh`, cache-only auth, and the
     resolved `#fleet-events` default rather than storing channel discovery in
     ad hoc scripts.
5. Repo-memory refresh state (not committed)
   - `dx-repo-memory-refresh` and `dx-repo-memory-refresh-all` store run
     reports and generated worktrees under the configured state root,
     defaulting to `~/.dx-state/repo-memory`
   - scheduled runs create Git branches and draft PRs for reviewable doc
     changes; runtime logs and lock files are operational evidence, not
     canonical memory
6. Codex session health state (not committed)
   - `dx-codex-session-repair.sh` writes scan/repair reports under
     `~/.dx-state/codex-session-repair/last.json` by default
   - backup-first repair copies original JSONL files under
     `~/.codex/session-repair-backups/` before changing session files
   - `dx-codex-weekly-health.sh` stores its latest digest JSON under
     `~/.dx-state/codex-weekly-health/last.json`
   - cron installer scripts are tracked repo policy; they may update host
     crontabs, but the schedule entries and generated logs remain host-local
     operational state
   - Codex session JSONL files and repair backups are host-local operational
     state, not repo-owned memory; the repo owns only the scripts and tests
     that govern how they are inspected or repaired
7. Olivaw/Hermes local operational state (not committed)
   - Olivaw profile files, gateway logs, Kanban SQLite data, and Google OAuth
     token material live under host-local Hermes/gog state, not in this repo
   - `scripts/olivaw-gog-safe.sh`, `scripts/olivaw-runtime-check.sh`,
     `scripts/olivaw-redaction-canary.sh`,
     `scripts/olivaw-cron-silent-canary.sh`,
     `scripts/olivaw-kanban-policy-canary.sh`, and
     `scripts/olivaw-slack-thread-evidence.sh` are repo-owned policy and
     evidence helpers for those external/local state surfaces
   - the durable Olivaw non-GasCity contract and verification evidence live in
     `docs/specs/2026-05-05-olivaw-*` specs; runtime logs, Slack messages,
     Google artifacts, and Kanban DB rows remain external operational evidence
8. Olivaw Google Workspace operational state (not committed)
   - `scripts/olivaw-gog-safe.sh` is the repo-owned policy wrapper for the
     Star's End `olivaw-gog` Google client and `fengning@stars-end.ai` account
   - `scripts/olivaw-google-ops-bootstrap.sh` creates or binds the approved
     Drive folder tree, `Olivaw Ops Tracker`, Gmail labels, and calendar ID,
     then writes host-local state to
     `~/.hermes/profiles/olivaw/google-ops-state.env`
   - `scripts/olivaw-google-ops-canary.sh` creates only synthetic Drive, Docs,
     Sheets, Gmail draft, and Calendar artifacts and verifies blocked external
     actions
   - Google OAuth tokens, Drive files, Docs, Sheets, Gmail drafts/labels, and
     Calendar events are external Workspace state, not repo state
   - the durable repo contract and evidence live in
     `docs/specs/2026-05-06-olivaw-google-internal-write-surfaces.md` and
     `docs/specs/2026-05-06-olivaw-google-internal-write-evidence.md`

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
