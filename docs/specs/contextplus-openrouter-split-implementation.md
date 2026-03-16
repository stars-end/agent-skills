# Context-Plus OpenRouter Embeddings + Nightly z.ai Enrichment: Implementation Spec

**Beads**: bd-hil7.2
**Status**: Draft Spec
**Date**: 2026-03-16
**Supersedes**: 2026-03-16-context-backend-finalization.md, 2026-03-16-serena-contextplus-cass-research.md

## Summary

This spec converts the research phase into an execution contract. Phase 1 adds OpenRouter-backed embeddings to `context-plus` as the primary path, keeps Ollama as a fallback, and runs nightly z.ai enrichment jobs outside `context-plus` for chat-based labeling.

The spec does **not** patch `context-plus` source code itself. That is a follow-on task.

---

## 1. Provider Path

### 1.1 Embedding Provider Branching

`context-plus` must support two embedding backends:

| Priority | Provider | Trigger | Model | Cost |
|----------|----------|---------|-------|------|
| 1 (primary) | OpenRouter | `OPENROUTER_API_KEY` set | `nomic-embed-text` (via `openai/nomic-embed-text`) | ~$0.008/1M tokens |
| 2 (fallback) | Ollama (local) | `OPENROUTER_API_KEY` absent | `nomic-embed-text` (local) | Free, CPU-bounded |

### 1.2 Exact Env Vars

| Var | Purpose | Default | Required |
|-----|---------|---------|----------|
| `OPENROUTER_API_KEY` | Switches embedding provider to OpenRouter | absent = Ollama fallback | No (absent = fallback) |
| `OPENROUTER_EMBED_MODEL` | Embedding model on OpenRouter | `openai/nomic-embed-text` | No |
| `OLLAMA_HOST` | Ollama endpoint (fallback path) | `http://localhost:11434` | No (only when OpenRouter absent) |
| `OLLAMA_EMBED_MODEL` | Ollama embedding model (fallback path) | `nomic-embed-text` | No |
| `CONTEXTPLUS_EMBED_PROVIDER` | Explicit provider override | `auto` | No |

### 1.3 Provider Selection Logic

```
if CONTEXTPLUS_EMBED_PROVIDER == "ollama":
    use Ollama
elif CONTEXTPLUS_EMBED_PROVIDER == "openrouter":
    use OpenRouter (fail if OPENROUTER_API_KEY missing)
elif OPENROUTER_API_KEY is set and non-empty:
    use OpenRouter
else:
    use Ollama
```

`CONTEXTPLUS_EMBED_PROVIDER=auto` (default) means: prefer OpenRouter if key available, else Ollama.

### 1.4 Chat in Phase 1

Phase 1 does **not** add OpenRouter-backed chat to `context-plus`. The `semantic-navigate` tool's `chatCompletion()` function (which labels clusters) will remain disabled unless Ollama is available. This is acceptable because:

- `semantic-navigate` falls back gracefully to path-pattern labels when chat fails (line 144 of `semantic-navigate.ts`)
- Nightly z.ai enrichment (Section 3) provides a richer labeling mechanism outside `context-plus`

---

## 2. Patch Strategy

### 2.1 Recommendation: Thin Compatibility Layer (Wrapper Script)

**Chosen path**: Maintain a thin compatibility layer that sits between `context-plus` and the embedding backends, rather than patching upstream `context-plus` source code.

### 2.2 Why This Path

| Option | Blast Radius | Maintenance Cost | Upgrade Risk |
|--------|-------------|------------------|-------------|
| **Patch upstream contextplus** | Medium (must maintain fork or submit PR) | High (merge conflicts on every npm update) | High |
| **Internal fork** | High (full repo divergence) | Very High (own all future changes) | Very High |
| **Compat layer (RECOMMENDED)** | Low (isolated wrapper) | Low (upgrade contextplus freely) | Low |

The compat layer intercepts the `ollama.embed()` call. The recommended approach for Phase 1 is a **`NODE_OPTIONS --require` preload script**:

Write a standalone Node.js module (`contextplus-openrouter-embed.js`) that monkey-patches the `embedWithTimeout` function at runtime. It is loaded via `NODE_OPTIONS="--require /path/to/contextplus-openrouter-embed.js"` in the MCP server's `env` block.

The wrapper does:
1. Check `OPENROUTER_API_KEY` in process environment
2. If present: call `POST https://openrouter.ai/api/v1/embeddings` with model and input payload
3. If absent: delegate to the original Ollama `embed()` call (no-op passthrough)
4. Return results in the shape `context-plus` expects: `{ embeddings: number[][] }`

**Rejected alternatives**:
- HTTP proxy presenting as `OLLAMA_HOST`: adds network indirection and Ollama schema translation complexity. Not worth it when we can intercept at the function level.
- Patching upstream `contextplus` source: we don't own the repo; npm updates would clobber changes.

**Why this works**: `context-plus` is installed as a global npm package. The preload script runs before the MCP server process, giving us access to patch the `embedWithTimeout` export from `contextplus/src/core/embeddings.ts`. The Ollama npm import is only used for `embed()` and `chat()`, so intercepting `embedWithTimeout` covers all embedding paths.

### 2.3 Wrapper Architecture

The wrapper intercepts at the `embedWithTimeout` function level. The minimal interception surface in `context-plus`:

```typescript
// Source: contextplus/src/core/embeddings.ts
// Line 90: const ollama = new Ollama({ host: process.env.OLLAMA_HOST });
// Line 131-135: ollama.embed({ ...request, signal })
```

The compat layer provides a `createEmbedProvider()` function that returns an object matching the `{ embed(request) => Promise<{embeddings: number[][]}> }` interface. When `OPENROUTER_API_KEY` is set, it calls OpenRouter. When absent, it delegates to the existing Ollama client.

### 2.4 Upgrade Path

When `context-plus` publishes native OpenAI/OpenRouter support (if ever), we simply remove the compat layer and unset `OPENROUTER_API_KEY`. Zero migration cost.

---

## 3. Nightly Enrichment Design

### 3.1 Architecture Boundary

`context-plus` owns: live embedding-based search, indexing, cache management.
Nightly enrichment owns: chat-based cluster labeling, semantic summaries, metadata enrichment.

The boundary is strict: nightly jobs **write** enriched artifacts that `context-plus` **reads**, but the jobs do not modify `context-plus` internals at runtime.

### 3.2 Artifacts Produced Nightly

| Artifact | Format | Location | Consumer |
|----------|--------|----------|----------|
| Cluster labels | JSON | `.mcp_data/enrichment/cluster-labels.json` | `context-plus` semantic-navigate (if wired) |
| File summaries | JSON | `.mcp_data/enrichment/file-summaries.json` | `context-plus` memory graph |
| Semantic descriptions | JSON | `.mcp_data/enrichment/semantic-descriptions.json` | Agent prompts |

### 3.3 Job Design

```yaml
nightly-enrichment:
  schedule: "0 3 * * *"  # 3 AM UTC
  timeout: 30m
  steps:
    1. For each tracked repo in fleet:
       a. Read .mcp_data/embeddings-cache.json
       b. Extract file paths + headers + symbol lists
       c. Batch into clusters of ~20 files
       d. For each cluster, call z.ai (GLM-4.7) with labeling prompt
       e. For each file, call z.ai with summary prompt
       f. Write results to .mcp_data/enrichment/
```

### 3.4 Prompt Templates

**Cluster labeling prompt** (sent to z.ai via `ZaiClient`):
```
You are labeling clusters of code files. For each cluster below, produce EXACTLY
one JSON array of objects, each with:
- "label": 2-3 words describing the cluster
- "theme": a sentence about the cluster's purpose

{cluster_descriptions}

Respond with ONLY a JSON array. No other text.
```

**File summary prompt** (sent to z.ai via `ZaiClient`):
```
Provide a 5-10 word semantic description of this file for code search indexing.

File: {relative_path}
Header: {header}
Symbols: {symbols}

Respond with ONLY the description text.
```

### 3.5 Model Path

Use `z.ai` GLM-4.7 via `ZaiClient` from `llm-common`:
- Model: `glm-4.7` (or `glm-5` if available)
- Endpoint: `https://api.z.ai/api/anthropic` (Anthropic-compatible)
- Auth: `ZAI_API_KEY` from 1Password (`op://dev/Agent-Secrets-Production/ZAI_API_KEY`)
- Cost: $0.00 (z.ai provides free GLM access)

### 3.6 Implementation Reference

The nightly job should reuse:
- `llm_common/providers/zai_client.py` for the LLM client
- `llm_common/core/models.py` for `LLMConfig`, `LLMMessage`
- Existing `dx-auth` secret resolution from `scripts/adapters/lib/dx-auth.sh`

The job itself is a new Python script at `scripts/enrichment/nightly-enrichment.py` in `agent-skills`, invoked via cron or systemd timer.

### 3.7 Volume Estimate

Per repo: ~100-500 files indexed. At ~20 files per cluster, that's 5-25 chat calls per repo. With 4 canonical repos, that's ~20-100 chat calls per night. Well within z.ai's free tier.

---

## 4. Fleet Config

### 4.1 Environment Variables Per Host

All canonical hosts (macmini, homedesktop-wsl, epyc12) get:

```bash
# Embedding provider (set in host env, NOT in MCP config env blocks)
export OPENROUTER_API_KEY="<from 1password: op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY>"

# Optional: explicit model override
# export OPENROUTER_EMBED_MODEL="openai/nomic-embed-text"
```

### 4.2 MCP Config Changes

No MCP config changes required for Phase 1. The compat layer reads `OPENROUTER_API_KEY` from the process environment. Since MCP servers inherit the parent shell's environment, setting `OPENROUTER_API_KEY` in the host profile is sufficient.

**Codex** (`~/.codex/config.toml`): No changes. `context-plus` reads env vars directly.

**Claude Code** (`~/.claude.json`): No changes to MCP config. Add `OPENROUTER_API_KEY` to shell profile.

**OpenCode** (`~/.config/opencode/opencode.jsonc`): No changes. Add `OPENROUTER_API_KEY` to shell profile.

### 4.3 What Stays Unchanged

- `OLLAMA_HOST` configuration (still valid for fallback)
- `OLLAMA_EMBED_MODEL` (still valid for fallback)
- `OLLAMA_CHAT_MODEL` (still valid if Ollama is used for chat)
- Serena MCP config
- cass-memory status (still paused)
- `CONTEXTPLUS_EMBED_*` tuning vars (batch size, thread count, etc.)

### 4.4 Secret Resolution

```bash
# 1Password reference for OPENROUTER_API_KEY
op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY

# Resolution method (same pattern as ZAI_API_KEY):
# Add to ~/.config/systemd/user/context-plus-env or shell profile
export OPENROUTER_API_KEY="$(op read 'op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY')"
```

### 4.5 Nightly Enrichment Env Requirements

```bash
# Required for nightly z.ai enrichment job
ZAI_API_KEY=<from 1password>
ZAI_BASE_URL=https://api.z.ai/api/anthropic  # or use default from ZaiClient

# Not required (uses local embedding cache, no live embeddings)
# OPENROUTER_API_KEY
```

---

## 5. Validation

### 5.1 Semantic Search Smoke Test

After implementation, verify in each IDE:

1. Start a new `context-plus` session in a known repo (e.g., `agent-skills`)
2. Run `semantic_code_search` with query: "how are beads tracked"
3. Verify: returns files related to Beads workflow (`core/beads-workflow`, `scripts/bd`, etc.)
4. Verify: results include `semanticScore > 0.5`
5. Run same query twice to verify cache hit (second call should be faster)

### 5.2 Indexing / Update Behavior

1. Open a project with existing `.mcp_data/embeddings-cache.json`
2. Modify one file
3. Trigger re-index (e.g., restart MCP server or wait for file watcher)
4. Verify: only the modified file is re-embedded (check cache file for updated hash)
5. Verify: cache file size grows minimally (only new entries)

### 5.3 Fallback Path Verification

1. Unset `OPENROUTER_API_KEY`
2. Restart `context-plus`
3. Verify: embeddings still work (falls back to Ollama if running, or fails gracefully)
4. Re-set `OPENROUTER_API_KEY`
5. Verify: embeddings work via OpenRouter

### 5.4 Failure Modes

| Scenario | Expected Behavior |
|----------|-------------------|
| `OPENROUTER_API_KEY` invalid | Fall back to Ollama; log warning |
| OpenRouter API down | Fall back to Ollama; log error |
| OpenRouter rate limited | Retry with backoff (3 attempts); then fall back |
| Ollama not running and OpenRouter absent | Embeddings fail gracefully; tools return empty results |
| Network timeout | 60s timeout per batch; fall back to Ollama |

### 5.5 Rollback

To rollback to Ollama-only:
1. Unset `OPENROUTER_API_KEY` from host environment
2. Restart MCP servers
3. No code changes needed (Ollama fallback is always present)

### 5.6 Minimum Viable Acceptance Test List

For the future implementation PR:

- [ ] `OPENROUTER_API_KEY` present: `semantic_code_search` returns results with `semanticScore > 0`
- [ ] `OPENROUTER_API_KEY` absent: falls back to Ollama (if running) or fails gracefully
- [ ] `CONTEXTPLUS_EMBED_PROVIDER=ollama` forces Ollama even when `OPENROUTER_API_KEY` is set
- [ ] `CONTEXTPLUS_EMBED_PROVIDER=openrouter` forces OpenRouter and fails fast without key
- [ ] Embedding cache persists across sessions
- [ ] No regressions in existing `context-plus` tools (`get_context_tree`, `get_file_skeleton`, etc.)
- [ ] `semantic_identifier_search` works with OpenRouter embeddings
- [ ] `add_interlinked_context` and `search_memory_graph` work with OpenRouter embeddings

---

## 6. Follow-On Tasks

### 6.1 Task Breakdown

| # | Task | Scope | Priority | Dependencies |
|---|------|-------|----------|-------------|
| T1 | Implement OpenRouter embeddings compat layer | Write `contextplus-openrouter-embed.js` wrapper; add to MCP server startup | P1 | This spec merged |
| T2 | Fleet config rollout: add `OPENROUTER_API_KEY` to all hosts | Shell profile updates on macmini, homedesktop-wsl, epyc12 | P1 | T1 complete |
| T3 | Validate embeddings on all three IDEs (Codex, Claude Code, OpenCode) | Smoke test per Section 5 | P1 | T2 complete |
| T4 | Implement nightly z.ai enrichment job | New Python script at `scripts/enrichment/nightly-enrichment.py` | P2 | T3 complete |
| T5 | Wire enrichment artifacts into `context-plus` reads | Optional: make semantic-navigate read cluster-labels.json | P2 | T4 complete |
| T6 | (Optional) Add OpenRouter-backed chat to `context-plus` | If live cluster labeling is desired | P3 | T1 complete |

### 6.2 Suggested Beads Task Titles

- **T1**: `bd-hil7.3` - "Impl: OpenRouter embeddings compat layer for context-plus"
- **T2**: `bd-hil7.4` - "Rollout: OPENROUTER_API_KEY to all canonical hosts"
- **T3**: `bd-hil7.5` - "Validate: context-plus embeddings on Codex, Claude Code, OpenCode"
- **T4**: `bd-hil7.6` - "Impl: nightly z.ai enrichment job for semantic labeling"
- **T5**: `bd-hil7.7` - "Wire: enrichment artifacts into context-plus semantic-navigate"
- **T6**: `bd-hil7.8` - "Impl: OpenRouter chat support in context-plus (deferred)"

### 6.3 Dependency Graph

```
This spec (bd-hil7.2)
  -> T1 (bd-hil7.3): compat layer
     -> T2 (bd-hil7.4): fleet rollout
        -> T3 (bd-hil7.5): validation
           -> T4 (bd-hil7.6): nightly enrichment
              -> T5 (bd-hil7.7): wire enrichment
     -> T6 (bd-hil7.8): chat support (parallel with T2)
```

---

## 7. Source References

- `contextplus/src/core/embeddings.ts` (upstream, 499 lines) - Ollama-only embedding engine
- `contextplus/src/tools/semantic-navigate.ts` (upstream, 295 lines) - Chat-based cluster labeling
- `llm_common/providers/zai_client.py` - z.ai LLM client (reference for nightly job)
- `llm_common/providers/openrouter_client.py` - OpenRouter LLM client (reference for compat layer)
- `scripts/adapters/cc-glm.sh` - z.ai auth resolution pattern (reference)
- `docs/investigations/2026-03-16-context-backend-finalization.md` - Embedding model selection
- `docs/investigations/2026-03-16-epyc12-load-analysis.md` - Centralized Ollama rejection rationale
- `docs/investigations/2026-03-16-serena-contextplus-cass-research.md` - Architecture comparison
- `docs/investigations/TECHLEAD-REVIEW-serena-contextplus-cass.md` - Final architecture decision
