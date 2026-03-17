# Context-Plus OpenRouter Rollout Checklist

**Beads**: bd-hil7.3
**Status**: Revised for local-only patch model + repaired env/fallback/enrichment/drift

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
- [ ] Drift check passes: `scripts/install-contextplus-patched.sh --check` returns `current (sha=..., checksum=...)`
- [ ] Drift check fails on checksum mismatch: modify patch file, re-run `--check`, confirm `patch-drift` output
- [ ] Patch includes provider branching logic (Section 1.3 of spec)
- [ ] Patch includes durable fallback: 5xx/network -> pin to Ollama for process lifetime; 401/403/404 -> fail fast
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
- [ ] Run fleet-sync: `scripts/dx-mcp-tools-sync.sh apply` - confirms env blocks rendered
- [ ] **Verify rendered config**: `OPENROUTER_API_KEY` is present (resolved from parent process) OR absent (if key not in parent env). NO literal `${OPENROUTER_API_KEY}` placeholders.
- [ ] Verify `OPENROUTER_EMBED_MODEL` and `CONTEXTPLUS_EMBED_PROVIDER` are in env block
- [ ] Restart IDE (Claude Code / Codex / OpenCode)
- [ ] `semantic_code_search` smoke test passes
- [ ] Embedding cache written as V2 format with correct dimensions
- [ ] Fallback verified: temporarily unset `OPENROUTER_API_KEY`, confirm Ollama takeover
- [ ] Re-run fleet-sync after unsetting key: confirm `OPENROUTER_API_KEY` absent from rendered config

### Host-Specific

#### macmini (Apple Silicon, primary dev)
- [ ] OpenRouter active, smoke tests pass
- [ ] Durable fallback: induce 5xx, confirm subsequent calls stay on Ollama (no flapping)
- [ ] Nightly enrichment cron installed (see T4)

#### homedesktop-wsl
- [ ] OpenRouter active, smoke tests pass
- [ ] Fallback to Ollama verified

#### epyc12
- [ ] OpenRouter active, smoke tests pass
- [ ] CPU usage normal during indexing (no spikes - OpenRouter is remote)
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
- [ ] Env propagation confirmed: `OPENROUTER_API_KEY` present in rendered `environment` block

## Nightly Enrichment (T4)

- [ ] `scripts/enrichment/nightly-enrichment.py` committed (uses llm-common ZaiClient)
- [ ] `llm-common` installed: `pip install llm-common`
- [ ] Cron job installed on one host:
  ```bash
  # 3 AM UTC daily
  0 3 * * * ZAI_API_KEY=$(op read 'op://dev/Agent-Secrets-Production/ZAI_API_KEY') /path/to/python3 /path/to/agent-skills/scripts/enrichment/nightly-enrichment.py >> /tmp/enrichment.log 2>&1
  ```
- [ ] First run (dry): `python3 scripts/enrichment/nightly-enrichment.py --dry-run`
- [ ] Artifacts written to `~/.dx-state/enrichment/{repo-name}/` (NOT into canonical clones)
- [ ] `~/.dx-state/enrichment/agent-skills/cluster-labels.json` exists
- [ ] `~/.dx-state/enrichment/agent-skills/file-summaries.json` exists
- [ ] `~/.dx-state/enrichment/agent-skills/semantic-descriptions.json` exists
- [ ] No `.mcp_data/enrichment/` directory created inside any canonical repo

## Rollback Procedure

1. Reinstall without OpenRouter: `CONTEXTPLUS_EMBED_PROVIDER=ollama scripts/install-contextplus-patched.sh`
2. Remove `OPENROUTER_API_KEY` from shell profiles on all hosts
3. Re-run fleet-sync: `scripts/dx-mcp-tools-sync.sh apply` - confirms key absent from rendered configs
4. Clear `.mcp_data/embeddings-cache.json` on all repos (dimension mismatch between models)
5. Restart IDE / MCP servers
6. Verify Ollama fallback activates
7. No code rollback needed - the patch always includes Ollama fallback
