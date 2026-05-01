---
name: context-plus
description: |
  REMOVED from canonical fleet contract (bd-rb0c.8).
  context-plus was fully removed in favor of default discovery via rg/fd/direct
  reads, serena for symbol-aware edits, and optional bounded llm-tldr
  structural/context fallback. This skill is retained as a tombstone only.
tags:
  - removed
  - deprecated
  - fleet-sync
---

# context-plus — REMOVED

context-plus was fully removed from the canonical fleet contract in bd-rb0c.8.

## Why Removed

- **Worktree blindness**: ROOT_DIR locked at server startup; agents in worktrees got stale results
- **Single-root binding**: Each MCP instance bound to one repo; no dynamic root selection
- **Cross-repo overhead**: O(n) per-repo MCP entries for n repos
- **Unused capabilities**: Spectral clustering, memory graph, and feature hub had near-zero agent usage
- **Superseded by V8.6 routing contract**: default repo discovery is `rg`/`fd`/direct reads; `serena` handles known-symbol edits; `llm-tldr` remains optional bounded structural/context fallback with worktree-safe per-call project parameter

## Replacement

| Former context-plus use | Replacement |
|------------------------|-------------|
| Repo discovery / feature location | `rg` / `fd` / direct reads |
| Structural analysis | optional bounded `llm-tldr` (structure, calls, cfg, dfg, slice, arch) |
| "Understand this function" | direct reads first; optional bounded `llm-tldr` context |
| Symbol-aware edits | `serena` |

## Historical Reference

- Upstream: https://github.com/ForLoopCodes/contextplus
- Removed in: bd-rb0c.8 (2026-03-29)
- Demotion history: V8.6 demoted to experimental/optional, bd-rb0c.8 fully removed
