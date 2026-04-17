---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: 7d7f77a4fa2159283817414601d330acb9a81ace
last_verified_at: 2026-04-17T05:48:13Z
stale_if_paths:
  - docs/architecture/**
---

# Architecture Docs Index

- `BROWNFIELD_MAP.md`: first-stop orientation for existing-system changes,
  including the `dx-loop`/`dx-runner`/`dx-batch` runtime boundary
- `DATA_AND_STORAGE.md`: memory, storage, and orchestration runtime artifact
  ownership boundaries
- `WORKFLOWS_AND_PATTERNS.md`: recurring workflow contracts, orchestration
  surface hierarchy, and anti-drift rules

Current review-dispatch policy lives in the map docs: `dx-review` uses the GLM
lane plus Gemini by default, with OpenCode as GLM fallback and no Claude review
lane.

Scheduled repo-memory refreshes must keep this index in sync whenever mapped
architecture docs are added, removed, or materially reorganized.
