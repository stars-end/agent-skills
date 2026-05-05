---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 1ac6de75932e98c0f8331eefcc03421adee09a655
last_verified_at: 2026-05-05T01:30:00Z
stale_if_paths:
  - docs/architecture/**
---

# Architecture Docs Index

- `BROWNFIELD_MAP.md`: first-stop orientation for existing-system changes,
  including the `dx-loop`/`dx-runner`/`dx-batch` runtime boundary and
  repo-specific Railway topology skills such as Affordabot and Prime Radiant
  dev context, plus the active warmed semantic-index repo scope
- `DATA_AND_STORAGE.md`: memory, storage, portable handoff context, delegated
  prompt, optional ccc semantic-index cache, and orchestration runtime artifact
  ownership boundaries, including scheduled canonical semantic-index refresh
  and the current allowlisted cache surfaces, hook-only canonical drift
  auto-restore boundaries, plus host-local Codex session health reports/backups
- `WORKFLOWS_AND_PATTERNS.md`: recurring workflow contracts, orchestration
  surface hierarchy, anti-drift rules, and the active discovery contract:
  `rg` + direct reads first, optional read-only `scripts/semantic-search`
  status/query only when semantic status is `ready`, `serena` for
  symbol-aware edits, narrow `dx-verify-clean` hook-only self-heal, and
  tracked-wrapper requirements for Codex session health cron jobs

Current review-dispatch policy lives in `configs/dx-review/default.yaml` and the
map docs: `dx-review` reads reviewer `id/provider/model` rows and uses only the
OpenCode Kimi K2.6 and DeepSeek V4 Pro lanes by default.

Scheduled repo-memory refreshes must keep this index in sync whenever mapped
architecture docs are added, removed, or materially reorganized.
