---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: b1d57c744d03181bf5bc4ef5799903a1a40f4c5f
last_verified_at: 2026-05-06T15:01:00Z
stale_if_paths:
  - docs/architecture/**
---

# Architecture Docs Index

- `BROWNFIELD_MAP.md`: first-stop orientation for existing-system changes,
  including the `dx-loop`/`dx-runner`/`dx-batch` runtime boundary, the
  `goal-seeking-eval-loop` contract boundary, repo-specific Railway topology
  skills such as Affordabot and Prime Radiant dev context, plus the active
  warmed semantic-index repo scope
- `DATA_AND_STORAGE.md`: memory, storage, portable handoff context, delegated
  prompt, optional ccc semantic-index cache, and orchestration runtime artifact
  ownership boundaries, including scheduled canonical semantic-index refresh
  and the current allowlisted cache surfaces, versioned-hook migration
  boundaries, hook-only canonical drift auto-restore boundaries, plus
  host-local Codex session health reports/backups, tracked cron installer
  boundaries, Olivaw/Hermes host-local operational state boundaries, and
  Olivaw Google Workspace operational state boundaries
- `WORKFLOWS_AND_PATTERNS.md`: recurring workflow contracts, orchestration
  surface hierarchy, the goal-seeking single-gate eval-loop pattern,
  anti-drift rules, and the active discovery contract: `rg` + direct reads
  first, optional read-only `scripts/semantic-search` status/query only when
  semantic status is `ready`, `serena` for symbol-aware edits, explicit
  versioned-hook update opt-in, narrow `dx-verify-clean` hook-only self-heal,
  and tracked-wrapper requirements for Codex session health cron jobs and
  installer host coverage, plus deterministic Agent Coordination follow-up
  patterns for `#fleet-events` and the Olivaw non-GasCity operator-surface
  contract and Olivaw Google internal-write wrapper/bootstrap/canary pattern

Current review-dispatch policy lives in `configs/dx-review/default.yaml` and the
map docs: `dx-review` reads reviewer `id/provider/model` rows and uses only the
OpenCode Kimi K2.6 and DeepSeek V4 Pro lanes by default.

Scheduled repo-memory refreshes must keep this index in sync whenever mapped
architecture docs are added, removed, or materially reorganized.
