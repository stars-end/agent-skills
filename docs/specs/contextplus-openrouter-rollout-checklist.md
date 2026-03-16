# Context-Plus OpenRouter Rollout Checklist

**Beads**: bd-hil7.3
**Status**: Revised for local-only patch model

## Pre-Implementation Gate (T0)

- [ ] Verify `OPENROUTER_API_KEY` is active (1Password: `op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY`)
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

- [ ] Local patch applied at `~/.local/share/contextplus-patched` via `scripts/install-contextplus-patched.sh`
- [ ] `install-metadata.json` written with correct upstream SHA and patch checksum
- [ ] Drift check passes: `scripts/install-contextplus-patched.sh --check` returns `current`
- [ ] Patch includes provider branching logic (Section 1.3 of spec)
- [ ] Patch includes runtime fallback: 5xx/network → Ollama; 401/403/404 → fail fast
- [ ] Patch includes cache invalidation on model/dimension mismatch
- [ ] All existing `context-plus` tools pass with Ollama fallback (no regressions)

## Per-Host Rollout (T2)

### Common Steps (all hosts)

- [ ] `OPENROUTER_API_KEY` exported in shell profile (`.zshrc` / `.bashrc`):
  ```bash
  export OPENROUTER_API_KEY="$(op read 'op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY')"
  ```
- [ ] Run install script: `scripts/install-contextplus-patched.sh`
- [ ] Verify drift check: `scripts/install-contextplus-patched.sh --check`
- [ ] Run fleet-sync: `scripts/dx-mcp-tools-sync.sh apply` — confirms env blocks rendered
- [ ] Verify rendered config contains env block with `OPENROUTER_API_KEY`, `OPENROUTER_EMBED_MODEL`, `CONTEXTPLUS_EMBED_PROVIDER`
- [ ] Restart IDE (Claude Code / Codex / OpenCode)
- [ ] `semantic_code_search` smoke test passes
- [ ] Embedding cache written as V2 format with correct dimensions
- [ ] Fallback verified: temporarily unset `OPENROUTER_API_KEY`, confirm Ollama takeover

### Host-Specific

#### macmini (Apple Silicon, primary dev)
- [ ] OpenRouter active, smoke tests pass
- [ ] Fallback to Ollama verified
- [ ] Nightly enrichment cron installed (see T4)

#### homedesktop-wsl
- [ ] OpenRouter active, smoke tests pass
- [ ] Fallback to Ollama verified

#### epyc12
- [ ] OpenRouter active, smoke tests pass
- [ ] CPU usage normal during indexing (no spikes — OpenRouter is remote)
- [ ] Fallback to Ollama verified

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
- [ ] Env propagation confirmed (check MCP server logs for `OPENROUTER_API_KEY` presence)

## Nightly Enrichment (T4)

- [ ] `scripts/enrichment/nightly-enrichment.py` committed (uses llm-common ZaiClient)
- [ ] `llm-common` installed: `pip install llm-common`
- [ ] Cron job installed on one host:
  ```bash
  # 3 AM UTC daily
  0 3 * * * ZAI_API_KEY=$(op read 'op://dev/Agent-Secrets-Production/ZAI_API_KEY') /path/to/python3 /path/to/agent-skills/scripts/enrichment/nightly-enrichment.py >> /tmp/enrichment.log 2>&1
  ```
- [ ] First run (dry): `python3 scripts/enrichment/nightly-enrichment.py --dry-run`
- [ ] First run produces `.mcp_data/enrichment/cluster-labels.json`
- [ ] First run produces `.mcp_data/enrichment/file-summaries.json`
- [ ] First run produces `.mcp_data/enrichment/semantic-descriptions.json`

## Rollback Procedure

1. Reinstall without OpenRouter: `CONTEXTPLUS_EMBED_PROVIDER=ollama scripts/install-contextplus-patched.sh`
2. Remove `OPENROUTER_API_KEY` from shell profiles on all hosts
3. Clear `.mcp_data/embeddings-cache.json` on all repos (dimension mismatch between models)
4. Restart IDE / MCP servers
5. Verify Ollama fallback activates
6. No code rollback needed — the patch always includes Ollama fallback
