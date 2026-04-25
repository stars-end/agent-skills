---
repo_memory: true
status: active
owner: dx-architecture
last_verified_commit: bd461df6f958056b8f1e25675bf8d7b54c486689
last_verified_at: 2026-04-25T14:45:00Z
stale_if_paths:
  - docs/architecture/**
---

# Architecture Docs Index

- `BROWNFIELD_MAP.md`: first-stop orientation for existing-system changes,
  including the `dx-loop`/`dx-runner`/`dx-batch` runtime boundary
- `DATA_AND_STORAGE.md`: memory, storage, portable handoff context, delegated
  prompt, and orchestration runtime artifact ownership boundaries
- `WORKFLOWS_AND_PATTERNS.md`: recurring workflow contracts, orchestration
  surface hierarchy, and anti-drift rules

Current review-dispatch policy lives in the map docs: `dx-review` uses the GLM
lane plus Gemini by default, with OpenCode as GLM fallback and no Claude review
lane.

Current llm-tldr routing policy lives in the workflow and storage maps:
semantic mixed-health is treated as a bounded analysis degradation, not a full
MCP hydration outage. Contained MCP, contained CLI, and daemon fallback semantic
paths should fail fast with `semantic_index_missing`; agents should prewarm the
semantic index only when the result is worth the latency.

Scheduled repo-memory refreshes must keep this index in sync whenever mapped
architecture docs are added, removed, or materially reorganized.
