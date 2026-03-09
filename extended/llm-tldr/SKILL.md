---
name: llm-tldr
description: Local-first static-analysis context slicing skill for precise, low-token task context extraction.
---

# llm-tldr (Fleet Sync V2.1)

Use this skill when you work involves codebase understanding, surgery context extraction, and will benefit from reduced token overhead.

## Status
- Fleet contract: MCP-rendered tool
- Canonical install: `uv tool install "llm-tldr==1.5.2"`
- Canonical health checks:
  - `tldr-mcp --version || llm-tldr --version`
  - client MCP visibility checks such as `claude mcp list`, `codex mcp list`, `gemini mcp list`, `opencode mcp list`
## Upstream Docs
- PyPI: `https://pypi.org/project/llm-tldr/`
- Package docs: `https://pypi.org/project/llm-tldr/`
## Contract
- Run local-first.
- Use for surgical context extraction and reduced token overhead.
- Keep fallback path to normal repo-local context gathering.
## Runtime Notes
- Python runtime with tree-sitter + FAISS dependencies.
- Per-project local indexes (no central index requirement).
## Fleet Usage
- Run via MCP server mode to provide semantic intent via tldr-mcp
- Supports codex, claude, opencode, gemini-cli clients when configured
## Tool Contract
- Install: `uv tool install "llm-tldr==1.5.2"`
- Health: `tldr-mcp --version || llm-tldr --version`
- Validate client visibility (Layer 4)
