# Context-Plus OpenRouter Rollout Checklist

**Beads**: bd-hil7.2
**Status**: Draft (revised 2026-03-17)

## Pre-Implementation Gate (T0)

- [ ] Verify `OPENROUTER_API_KEY` is active (1Password entry exists)
- [ ] Run model availability test:
  ```bash
  curl -s -X POST "https://openrouter.ai/api/v1/embeddings" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"openai/text-embedding-3-small","input":"test"}'
  ```
  Expected: 200 with `data[0].embedding` of length 1536
- [ ] If `openai/text-embedding-3-small` fails, test `qwen/qwen3-embedding-0.6b`
- [ ] Record chosen model and dimension in task notes

## Pre-Flight (T1)

- [ ] Upstream PR submitted to `contextplus` repo (or internal fork created)
- [ ] Patch includes provider branching logic (Section 1.3 of spec)
- [ ] Patch includes cache invalidation on dimension mismatch (Section 2.4)
- [ ] All existing `context-plus` tools pass with Ollama fallback (no regressions)
- [ ] Patched `contextplus` installed globally on one host for initial testing

## Per-Host Rollout (T2)

### macmini (Apple Silicon, primary dev)

- [ ] `OPENROUTER_API_KEY` added to shell profile (`.zshrc`)
- [ ] Claude Code MCP env block updated with `OPENROUTER_API_KEY` and `OPENROUTER_EMBED_MODEL`
- [ ] Codex MCP env block updated (or shell profile if TOML lacks env support)
- [ ] OpenCode `environment` block updated with `OPENROUTER_API_KEY` and `OPENROUTER_EMBED_MODEL`
- [ ] `context-plus` restarted with OpenRouter active
- [ ] `semantic_code_search` smoke test passes
- [ ] `semantic_identifier_search` smoke test passes
- [ ] Embedding cache written with correct dimensions
- [ ] Fallback verified: unset key, confirm Ollama takeover + cache invalidation

### homedesktop-wsl

- [ ] `OPENROUTER_API_KEY` added to shell profile
- [ ] Claude Code MCP env block updated
- [ ] Codex MCP env block updated
- [ ] OpenCode `environment` block updated
- [ ] `context-plus` restarted with OpenRouter active
- [ ] Smoke tests pass (same as macmini)
- [ ] Fallback verified

### epyc12

- [ ] `OPENROUTER_API_KEY` added to shell profile
- [ ] Claude Code MCP env block updated
- [ ] Codex MCP env block updated
- [ ] OpenCode `environment` block updated
- [ ] `context-plus` restarted with OpenRouter active
- [ ] Smoke tests pass (same as macmini)
- [ ] CPU usage normal during indexing (no spikes — OpenRouter is remote)
- [ ] Fallback verified

## IDE Validation (T3)

### Codex

- [ ] `context-plus` MCP tools listed in Codex
- [ ] `semantic_code_search` returns ranked results
- [ ] `add_interlinked_context` works with OpenRouter embeddings

### Claude Code

- [ ] `context-plus` MCP tools listed in Claude Code
- [ ] `semantic_code_search` returns ranked results
- [ ] `get_context_tree` works (structural, no embedding dependency)
- [ ] `search_memory_graph` works with OpenRouter embeddings

### OpenCode

- [ ] `context-plus` MCP tools listed in OpenCode
- [ ] `semantic_code_search` returns ranked results
- [ ] `semantic_identifier_search` returns identifier matches
- [ ] Env propagation confirmed (`OPENROUTER_API_KEY` reachable via OpenCode `environment` block or parent env)

## Nightly Enrichment (T4)

- [ ] `scripts/enrichment/nightly-enrichment.py` committed
- [ ] Cron job or systemd timer installed on one host
- [ ] First run produces `.mcp_data/enrichment/cluster-labels.json`
- [ ] First run produces `.mcp_data/enrichment/file-summaries.json`
- [ ] z.ai API calls succeed (check job logs)

## Rollback Procedure

1. Remove `OPENROUTER_API_KEY` from MCP env blocks on all clients
2. Remove `OPENROUTER_API_KEY` from shell profiles on all hosts
3. Restart MCP servers (Claude Code, OpenCode, Codex)
4. Clear `.mcp_data/embeddings-cache.json` on all repos (dimension mismatch)
5. Verify Ollama fallback activates (or fail gracefully if Ollama absent)
6. No code rollback needed (Ollama fallback is always present)
