# Context-Plus OpenRouter Rollout Checklist

**Beads**: bd-hil7.2
**Status**: Draft

## Pre-Flight

- [ ] 1Password entry exists: `op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY`
- [ ] OpenRouter API key is active and has credit (or free tier)
- [ ] OpenRouter `/embeddings` endpoint responds with `openai/nomic-embed-text` model
- [ ] Compat layer wrapper script (`contextplus-openrouter-embed.js`) is committed and tested
- [ ] All existing `context-plus` tools pass with Ollama fallback (no regressions)

## Per-Host Rollout

### macmini (Apple Silicon, primary dev)

- [ ] `OPENROUTER_API_KEY` added to shell profile
- [ ] `context-plus` restarted with OpenRouter active
- [ ] `semantic_code_search` smoke test passes
- [ ] `semantic_identifier_search` smoke test passes
- [ ] Embedding cache written to `.mcp_data/embeddings-cache.json`
- [ ] Fallback verified: unset key, confirm Ollama takeover

### homedesktop-wsl

- [ ] `OPENROUTER_API_KEY` added to shell profile
- [ ] `context-plus` restarted with OpenRouter active
- [ ] Smoke tests pass (same as macmini)
- [ ] Fallback verified

### epyc12

- [ ] `OPENROUTER_API_KEY` added to shell profile
- [ ] `context-plus` restarted with OpenRouter active
- [ ] Smoke tests pass (same as macmini)
- [ ] CPU usage normal during indexing (no spikes expected - OpenRouter is remote)
- [ ] Fallback verified

## IDE Validation

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

## Nightly Enrichment

- [ ] `scripts/enrichment/nightly-enrichment.py` committed
- [ ] Cron job or systemd timer installed on one host
- [ ] First run produces `.mcp_data/enrichment/cluster-labels.json`
- [ ] First run produces `.mcp_data/enrichment/file-summaries.json`
- [ ] z.ai API calls succeed (check job logs)

## Rollback Procedure

1. Unset `OPENROUTER_API_KEY` on affected host(s)
2. Restart MCP servers (Claude Code, OpenCode, Codex)
3. Verify Ollama fallback activates (or fail gracefully if Ollama absent)
4. No code rollback needed
