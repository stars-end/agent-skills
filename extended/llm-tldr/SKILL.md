---
name: llm-tldr
description: Local-first static-analysis context slicing skill for precise, low-token task context extraction.
---

# llm-tldr (Fleet Sync V2.1)

Status: available (`llm-tldr` v1.5.2+, local-first MCP via `tldr-mcp`).

## Contract
- Run local-first.
- Use for surgical context extraction and reduced token overhead.
- Keep fallback path to normal repo-local context gathering.

## Runtime Notes
- Python runtime with tree-sitter + FAISS dependencies.
- Per-project local indexes (no central index requirement).
