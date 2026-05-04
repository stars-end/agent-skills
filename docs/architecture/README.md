---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 1860c9ad30a874b653cf7b18147371990fb7fdbd
last_verified_at: 2026-05-04T14:48:00Z
stale_if_paths:
  - docs/architecture/**
---

# Architecture Docs Index

- `BROWNFIELD_MAP.md`: first-stop orientation for existing-system changes,
  including the `dx-loop`/`dx-runner`/`dx-batch` runtime boundary and
  repo-specific Railway topology skills such as Affordabot and Prime Radiant
  dev context
- `DATA_AND_STORAGE.md`: memory, storage, portable handoff context, delegated
  prompt, optional ccc semantic-index cache, and orchestration runtime artifact
  ownership boundaries
- `WORKFLOWS_AND_PATTERNS.md`: recurring workflow contracts, orchestration
  surface hierarchy, anti-drift rules, and the active discovery contract:
  `rg` + direct reads first, optional read-only `scripts/semantic-search`
  status/query only when semantic status is `ready`, and `serena` for
  symbol-aware edits

Current review-dispatch policy lives in `configs/dx-review/default.yaml` and the
map docs: `dx-review` reads reviewer `id/provider/model` rows and uses only the
OpenCode Kimi K2.6 and DeepSeek V4 Pro lanes by default.

Scheduled repo-memory refreshes must keep this index in sync whenever mapped
architecture docs are added, removed, or materially reorganized.
