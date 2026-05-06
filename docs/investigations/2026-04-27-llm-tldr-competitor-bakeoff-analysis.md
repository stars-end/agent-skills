# llm-tldr Competitor Bakeoff — Investigation Summary

**Date**: 2026-04-27
**BEADS_EPIC**: bd-9n1t2
**BEADS_SUBTASK**: bd-9n1t2.16
**Full Memo**: `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`

## Key Findings

1. **llm-tldr is stale** — last upstream push 2026-01-17, PyPI pinned at 1.5.2. 555-line containment wrapper needed for basic worktree safety. MCP timeouts, CLI missing `status` subcommand, cold-start model downloads from HuggingFace.

2. **grepai is the strongest replacement candidate** — 1646 stars, MIT, push TODAY. Single Go binary, no dependencies. Semantic search + call graph tracing. Clean MCP surface. 27 AI agent skills available. Requires Ollama for local embeddings.

3. **No single tool matches llm-tldr's full surface** — grepai lacks CFG/DFG/slice/arch/diagnostics. cocoindex-code has no structural analysis. CodeGraphContext has no semantic search.

4. **byterover-cli is not comparable** — it's a memory/orchestration layer (parallel map-reduce + context tree), not a code analysis tool. Confirmed via source inspection of `~/byterover-cli/src`.

## Source-Checked Evidence

- `~/llm-tldr/tldr/cross_file_calls.py`: 3,941 lines of tree-sitter-based call graph resolution
- `~/byterover-cli/src/agent/core/domain/tools/constants.ts`: `agentic_map` = parallel map-reduce over JSONL, `grep_content` = text grep only
- GitHub API: grepai last push 2026-04-27, llm-tldr last push 2026-01-17
- Runtime: llm-tldr semantic search timed out at 60s downloading HF model; structure worked in 8s; CLI has no `status` subcommand

## Recommendation

**DEFER_TO_P2_PLUS** — Run a narrow 2-week spike integrating grepai alongside llm-tldr to measure actual capability gap usage before committing to replacement.
