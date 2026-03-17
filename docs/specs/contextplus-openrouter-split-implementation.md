# Context-Plus OpenRouter Embeddings + Nightly z.ai Enrichment: Implementation Spec

**Beads**: bd-hil7.3
**Status**: Implementation (local-only patch model, hardened)
**Date**: 2026-03-16 (revised 2026-03-17)
**Supersedes**: 2026-03-16-context-backend-finalization.md, 2026-03-16-serena-contextplus-cass-research.md

## Summary

This spec converts the research phase into an execution contract. Phase 1 adds OpenRouter-backed embeddings to `context-plus` as the primary path, keeps Ollama as a fallback, and runs nightly z.ai enrichment jobs outside `context-plus` for chat-based labeling.

The implementation uses a local-only patch applied at install time (Section 2). No upstream changes to `contextplus`.

---

## 1. Provider Path

### 1.1 Embedding Provider Branching

`context-plus` must support two embedding backends:

| Priority | Provider | Trigger | Model | Cost |
|----------|----------|---------|-------|------|
| 1 (primary) | OpenRouter | `OPENROUTER_API_KEY` set | Configurable via `OPENROUTER_EMBED_MODEL` (see 1.2) | See 1.5 |
| 2 (fallback) | Ollama (local) | `OPENROUTER_API_KEY` absent | `nomic-embed-text` (local) | Free, CPU-bounded |

### 1.2 Exact Env Vars

| Var | Purpose | Default | Required |
|-----|---------|---------|----------|
| `OPENROUTER_API_KEY` | Switches embedding provider to OpenRouter | absent = Ollama fallback | No (absent = fallback) |
| `OPENROUTER_EMBED_MODEL` | Embedding model on OpenRouter | `openai/text-embedding-3-small` | No |
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

### 1.5 Embedding Model Strategy

**Recommended default**: `openai/text-embedding-3-small`

**Rationale**:
- 8,192 token context window — matches `nomic-embed-text` and is sufficient for embedding entire classes/files without truncation
- 1,536 output dimensions — higher than nomic-embed-text (768), better for semantic discrimination
- Proven OpenAI model — well-documented, stable API contract, widely available through routing providers
- Cost: ~$0.02/1M tokens on OpenRouter (confirmed via OpenAI's published pricing)

**Fallback/override path**: `OPENROUTER_EMBED_MODEL` allows switching to any OpenRouter-compatible embedding model. Candidate alternatives include:
- `qwen/qwen3-embedding-0.6b` — free tier on OpenRouter, smaller/faster, lower quality (not recommended for code-heavy repos)
- `openai/text-embedding-3-large` — higher quality, ~$0.13/1M tokens, overkill for Phase 1

**Known gap**: OpenRouter's `/api/v1/models` endpoint does not list embedding models in its catalog (all 345 listed models are chat/completion). However, the `/api/v1/embeddings` endpoint returns 401 (auth required, not 404), confirming the endpoint exists. The upstream docs reference `openai/text-embedding-3-small` and `qwen/qwen3-embedding-0.6b` as available models. **T1 (implementation) must include a validation gate** that confirms the chosen model is actually routable before fleet rollout.

**Dimension mismatch risk**: If the OpenRouter model outputs different dimensions than `nomic-embed-text` (768), existing embedding caches become invalid. The patch must handle cache invalidation when the embedding dimension changes. This is addressed in Section 2.4.

---

## 2. Patch Strategy

### 2.1 Chosen Path: Local-Only Patch

**Decision**: context-plus is NOT modified upstream. The patch is applied locally at install time via `scripts/install-contextplus-patched.sh` to `~/.local/share/contextplus-patched`. No upstream PR is submitted.

**Rationale**:
- context-plus is an OSS project we consume, not contribute to
- A local patch at a pinned upstream SHA gives us full control over rollout timing
- The patch is applied deterministically via `install-metadata.json` with SHA and checksum tracking
- Fleet-sync renders IDE configs to point at the local patched build

### 2.2 Upstream Patch Approach (REJECTED)

The original spec proposed submitting an upstream PR. This was rejected in favor of the local-only patch (Section 2.1). The rationale below is retained for context on why the alternative was considered.

**Original proposal**: Submit a PR to the upstream `contextplus` repository that adds an OpenAI-compatible embeddings provider alongside the existing Ollama provider, gated by `OPENROUTER_API_KEY`.

### 2.2 Why This Path (and why alternatives are rejected)

The original spec proposed a `NODE_OPTIONS --require` preload monkey-patch. That approach is **not technically viable** for these reasons:

| Constraint | Impact |
|-----------|--------|
| `contextplus` is ESM-only (`"type": "module"`) | `--require` is CJS-only; cannot preload into ESM |
| No `"exports"` or `"main"` field in package.json | Cannot `import { embedWithTimeout }` from outside |
| `embedWithTimeout` is a private function (not exported) | Cannot intercept at the function level |
| `contextplus` runs as a stdio MCP subprocess, not a library | No hook point for external code injection |
| MCP configs launch bare `contextplus` binary with no args | No `NODE_OPTIONS` injection surface |

**Comparison of viable options**:

| Option | Implementability | Maintenance Cost | Upgrade Path |
|--------|-----------------|-------------------|-------------|
| **Local-only patch (CHOSEN)** | Direct — modify `src/core/embeddings.ts`, apply at install time | Low — pinned SHA + checksum, full control | Manual re-base on upstream changes |
| Upstream patch | Direct — submit PR | Low if accepted, blocked if rejected | Automatic via `npm update` if accepted |
| Internal fork | Direct — full control | High — merge upstream changes manually | Manual rebase on every release |
| HTTP proxy as `OLLAMA_HOST` | Complex — must translate OpenAI schema to Ollama schema | Medium — maintain proxy process | Decoupled from contextplus updates |
| Wrapper MCP server that delegates to contextplus | Complex — must re-implement tool registrations | Very High — must track tool interface changes | Fragile |

**Why local-only wins**: No dependency on upstream maintainer acceptance timeline. The pinned SHA + patch checksum gives deterministic, auditable builds. Fleet-sync renders all IDE configs to the local binary. If upstream later accepts a similar change, we can drop the patch and switch to `npx -y contextplus`.

### 2.3 Patch Scope

The local patch modifies `src/core/embeddings.ts`:

**Current code** (lines 77, 90, 126-135):
```typescript
const EMBED_MODEL = process.env.OLLAMA_EMBED_MODEL ?? "nomic-embed-text";
const ollama = new Ollama({ host: process.env.OLLAMA_HOST });

async function embedWithTimeout(request: ...): Promise<{ embeddings: number[][] }> {
  const timeoutCtrl = AbortSignal.timeout(EMBED_TIMEOUT_MS);
  const signal = AbortSignal.any([embedAbortController.signal, timeoutCtrl]);
  return ollama.embed({ ...request, signal } as Parameters<typeof ollama.embed>[0]);
}
```

**Proposed change**: Add an `openRouterEmbed()` function that calls `POST https://openrouter.ai/api/v1/embeddings` using native `fetch` (no new dependency). Modify `embedWithTimeout` to route based on provider selection logic (Section 1.3).

Key details:
- Use native `fetch` (available in Node 18+, contextplus targets ES2022)
- OpenAI-compatible request/response schema: `{ model, input }` → `{ data: [{ embedding }] }`
- Convert OpenRouter response format to match Ollama's `{ embeddings: number[][] }` shape
- Add dimension check: if OpenRouter returns different dimension than cached vectors, clear cache

### 2.4 Cache Invalidation

When switching embedding providers or models, the vector dimension may change (e.g., nomic-embed-text = 768, text-embedding-3-small = 1536). The patch must:

1. Store the embedding model and dimension in the cache file header: `{ version: 2, model: "...", dimensions: N, entries: { ... } }`
2. On load, if `model` or `dimensions` differ from current config, invalidate the cache
3. Trigger a full re-index with the new provider

### 2.5 Runtime Fallback Policy

When `CONTEXTPLUS_EMBED_PROVIDER=auto` (default), the patched context-plus implements runtime fallback:

| OpenRouter Error | Action | Rationale |
|-----------------|--------|-----------|
| 5xx server error | Fall back to Ollama | Transient; Ollama provides continuity |
| Network failure (ECONNREFUSED, ENOTFOUND, fetch failed) | Fall back to Ollama | Transient or local outage |
| 401 Unauthorized | Fail fast | Bad API key; Ollama fallback won't help |
| 403 Forbidden | Fail fast | Rate limit or permissions; retry is wrong |
| 404 Not Found | Fail fast | Model doesn't exist; configuration error |
| AbortError (timeout) | Fail fast | Already retried via timeout; don't loop |

When `CONTEXTPLUS_EMBED_PROVIDER=openrouter` or `ollama` (explicit mode), no fallback occurs — errors propagate to the caller.

**Durable fallback in auto mode**: After a retriable OpenRouter failure, the process pins to Ollama for its remaining lifetime (`_cachedProvider = "ollama"`). No automatic recovery within the same process — recovery requires a process restart (next MCP session). This prevents flapping between providers.

### 2.6 Install and Drift Detection

The install script (`scripts/install-contextplus-patched.sh`) manages the local patch lifecycle:

1. **Install**: Clone upstream at pinned SHA, apply patch, build to `~/.local/share/contextplus-patched`
2. **Metadata**: Write `install-metadata.json` with upstream SHA, patch checksum, timestamp
3. **Drift check**: `--check` flag verifies **both** installed SHA and patch checksum against the script's pinned values. Fails with `patch-drift` if the checksum mismatches.
4. **Fatal on SHA miss**: If pinned SHA is not available in upstream, abort — never silently drift to latest
5. **Recovery**: If `--check` reports drift, re-run the install script without `--clean` to re-apply the patch at the current pinned SHA.

Install location: `~/.local/share/contextplus-patched` (overridable via `CONTEXTPLUS_PATCH_DIR`)

---

## 3. Nightly Enrichment Design

### 3.1 Architecture Boundary

`context-plus` owns: live embedding-based search, indexing, cache management.
Nightly enrichment owns: chat-based cluster labeling, semantic summaries, metadata enrichment.

The boundary is strict: nightly jobs **write** enriched artifacts that `context-plus` **reads**, but the jobs do not modify `context-plus` internals at runtime.

### 3.2 Artifacts Produced Nightly

Artifacts are written to an **external state root** (not into canonical repo clones) to comply with the no-writes-in-canonical-clones policy.

Default location: `~/.dx-state/enrichment/{repo-name}/` (overridable via `ENRICHMENT_ARTIFACT_ROOT`).

| Artifact | Format | Location | Consumer |
|----------|--------|----------|----------|
| Cluster labels | JSON | `~/.dx-state/enrichment/{repo}/cluster-labels.json` | `context-plus` semantic-navigate (if wired) |
| File summaries | JSON | `~/.dx-state/enrichment/{repo}/file-summaries.json` | `context-plus` memory graph |
| Semantic descriptions | JSON | `~/.dx-state/enrichment/{repo}/semantic-descriptions.json` | Agent prompts |

The enrichment job still **reads** `.mcp_data/embeddings-cache.json` from the canonical repo (read-only access is acceptable).

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

All canonical hosts (macmini, homedesktop-wsl, epyc12) need `OPENROUTER_API_KEY` accessible to the `context-plus` MCP server process.

### 4.2 MCP Config: Per-Client Env Injection

**This is the normative contract.** Env vars are propagated through the fleet-sync renderer, which resolves secret env vars from the parent process environment at render time.

1. **Fleet-sync renderer** (`dx-mcp-tools-sync.sh --apply`): Reads `mcp.env` and `mcp.env_from_parent` from `mcp-tools.yaml` manifest. Static env vars (like `CONTEXTPLUS_EMBED_PROVIDER`) are written as-is. Secret env vars listed in `env_from_parent` are resolved from the renderer's own process environment and written with their resolved values. If the env var is not set in the renderer's environment, it is **omitted** from the rendered config entirely.
2. **IDE client runtime**: Each IDE client passes its `env` (or `environment`) block entries to the stdio subprocess. Since fleet-sync resolved all values, no further interpolation is needed.

**Source of truth**: The `mcp.env` and `mcp.env_from_parent` blocks in `configs/mcp-tools.yaml` for each tool.

**No literal `${VAR}` placeholders** are ever written to rendered IDE configs.

#### Claude Code (`~/.claude.json`)

Fleet-sync writes an `env` block with resolved values:

```json
{
  "mcpServers": {
    "context-plus": {
      "command": "node",
      "args": ["~/.local/share/contextplus-patched/build/index.js"],
      "type": "stdio",
      "env": {
        "OPENROUTER_API_KEY": "sk-or-v1-...",
        "OPENROUTER_EMBED_MODEL": "openai/text-embedding-3-small",
        "CONTEXTPLUS_EMBED_PROVIDER": "auto"
      }
    }
  }
}
```

If `OPENROUTER_API_KEY` is not set when fleet-sync runs, the key is omitted:

```json
{
  "mcpServers": {
    "context-plus": {
      "command": "node",
      "args": ["~/.local/share/contextplus-patched/build/index.js"],
      "type": "stdio",
      "env": {
        "OPENROUTER_EMBED_MODEL": "openai/text-embedding-3-small",
        "CONTEXTPLUS_EMBED_PROVIDER": "auto"
      }
    }
  }
}
```

**Prerequisite**: `OPENROUTER_API_KEY` must be exported in the shell profile of the user running fleet-sync.

#### Codex (`~/.codex/config.toml`)

Same resolution pattern. Fleet-sync writes resolved values into `[mcp_servers."name".env]`:

```toml
[mcp_servers."context-plus".env]
OPENROUTER_API_KEY = "sk-or-v1-..."
OPENROUTER_EMBED_MODEL = "openai/text-embedding-3-small"
CONTEXTPLUS_EMBED_PROVIDER = "auto"
```

#### OpenCode (`~/.config/opencode/opencode.jsonc`)

Same resolution pattern. Fleet-sync writes resolved values into `environment`:

```jsonc
{
  "mcp": {
    "context-plus": {
      "command": ["node", "~/.local/share/contextplus-patched/build/index.js"],
      "type": "local",
      "environment": {
        "OPENROUTER_API_KEY": "sk-or-v1-...",
        "OPENROUTER_EMBED_MODEL": "openai/text-embedding-3-small",
        "CONTEXTPLUS_EMBED_PROVIDER": "auto"
      }
    }
  }
}
```

### 4.3 Summary: Per-Client Propagation Mechanism

| Client | Config key | Values written | Secret omission behavior |
|--------|-----------|---------------|-------------------------|
| Claude Code | `env` | Resolved from renderer process env | Key omitted -> auto falls back to Ollama |
| Codex | `env` subtable | Resolved from renderer process env | Key omitted -> auto falls back to Ollama |
| OpenCode | `environment` | Resolved from renderer process env | Key omitted -> auto falls back to Ollama |

**Important**: Fleet-sync must be run from a shell where `OPENROUTER_API_KEY` is exported for the key to appear in rendered configs. If the key is not set, the rendered config simply omits it — `CONTEXTPLUS_EMBED_PROVIDER=auto` will use Ollama.

**For secrets managed via 1Password**: Use `op read` in the shell profile or a launcher script to resolve the secret before the IDE process starts. See Section 4.4.

### 4.4 Secret Resolution

```bash
# 1Password reference for OPENROUTER_API_KEY
op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY

# Resolution for shell profile (all hosts):
# Add to ~/.zshrc or ~/.bashrc:
export OPENROUTER_API_KEY="$(op read 'op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY')"

# For MCP env blocks that require resolved values (Codex fallback):
# Write resolved value directly, NOT the op:// reference
```

### 4.5 What Stays Unchanged

- `OLLAMA_HOST` configuration (still valid for fallback)
- `OLLAMA_EMBED_MODEL` (still valid for fallback)
- `OLLAMA_CHAT_MODEL` (still valid if Ollama is used for chat)
- Serena MCP config
- cass-memory status (still paused)
- `CONTEXTPLUS_EMBED_*` tuning vars (batch size, thread count, etc.)

### 4.6 Nightly Enrichment Env Requirements

```bash
# Required for nightly z.ai enrichment job
ZAI_API_KEY=<from 1password>
ZAI_BASE_URL=https://api.z.ai/api/anthropic  # or use default from ZaiClient

# Not required (uses local embedding cache, no live embeddings)
# OPENROUTER_API_KEY
```

---

## 5. Validation

### 5.0 Pre-Implementation Gate (NEW)

Before fleet rollout, the implementation agent must:

1. Verify the chosen OpenRouter embedding model (`openai/text-embedding-3-small`) is actually routable:
   ```bash
   curl -s -X POST "https://openrouter.ai/api/v1/embeddings" \
     -H "Authorization: Bearer $OPENROUTER_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"openai/text-embedding-3-small","input":"test"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'dim={len(d[\"data\"][0][\"embedding\"])}')"
   ```
   Expected: `dim=1536`
2. If the model is not routable, fall back to `qwen/qwen3-embedding-0.6b` or defer Phase 1 embeddings and use Ollama-only

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

1. Unset `OPENROUTER_API_KEY` (or remove from MCP env block)
2. Restart `context-plus`
3. Verify: embeddings still work (falls back to Ollama if running, or fails gracefully)
4. Re-set `OPENROUTER_API_KEY`
5. Verify: cache is invalidated and re-indexed with new provider
6. Verify: embeddings work via OpenRouter

### 5.4 Failure Modes

| Scenario | Expected Behavior |
|----------|-------------------|
| `OPENROUTER_API_KEY` invalid (401) | Fail fast; propagate error |
| OpenRouter API down (5xx) | Pin process to Ollama for lifetime; log error |
| OpenRouter rate limited (403) | Fail fast; propagate error |
| Model not routable (404) | Fail fast with clear error |
| Ollama not running and OpenRouter absent | Embeddings fail gracefully; tools return empty results |
| Network timeout | Fail fast (AbortError is non-retriable) |
| Dimension mismatch (provider switch) | Invalidate cache, trigger full re-index |

In `auto` mode, only 5xx and network errors trigger fallback to Ollama. Auth errors (401/403), model-not-found (404), and timeouts fail fast. After fallback, the process stays on Ollama until restart — there is no automatic recovery or retry-with-backoff.

### 5.5 Rollback

To rollback to Ollama-only:
1. Remove `OPENROUTER_API_KEY` from MCP env blocks and shell profile
2. Restart MCP servers
3. Clear `.mcp_data/embeddings-cache.json` (dimension mismatch)
4. No code changes needed (Ollama fallback is always present)

### 5.6 Minimum Viable Acceptance Test List

For the future implementation PR:

- [ ] `OPENROUTER_API_KEY` present: `semantic_code_search` returns results with `semanticScore > 0`
- [ ] `OPENROUTER_API_KEY` absent: falls back to Ollama (if running) or fails gracefully
- [ ] `CONTEXTPLUS_EMBED_PROVIDER=ollama` forces Ollama even when `OPENROUTER_API_KEY` is set
- [ ] `CONTEXTPLUS_EMBED_PROVIDER=openrouter` forces OpenRouter and fails fast without key
- [ ] Embedding cache persists across sessions
- [ ] Cache invalidation triggers on provider/model switch
- [ ] No regressions in existing `context-plus` tools (`get_context_tree`, `get_file_skeleton`, etc.)
- [ ] `semantic_identifier_search` works with OpenRouter embeddings
- [ ] `add_interlinked_context` and `search_memory_graph` work with OpenRouter embeddings
- [ ] OpenRouter model is confirmed routable via pre-implementation gate (5.0)

---

## 6. Follow-On Tasks

### 6.1 Task Breakdown

| # | Task | Scope | Priority | Dependencies |
|---|------|-------|----------|-------------|
| T0 | Validate OpenRouter embedding model availability | curl test against `/api/v1/embeddings` with candidate models | P0 (gate) | None |
| T1 | Upstream PR: add OpenAI-compatible embeddings provider to `contextplus` | Patch `src/core/embeddings.ts` with provider branching, cache invalidation | P1 | T0 passes |
| T1b | Fallback: internal fork if upstream PR rejected | Fork `stars-end/contextplus`, pin in npm | P2 (contingent) | T1 rejected |
| T2 | Fleet config rollout: `OPENROUTER_API_KEY` on all hosts | MCP env blocks + shell profile on macmini, homedesktop-wsl, epyc12 | P1 | T1 merged/forked |
| T3 | Validate embeddings on all three IDEs | Smoke test per Section 5 | P1 | T2 complete |
| T4 | Implement nightly z.ai enrichment job | New Python script at `scripts/enrichment/nightly-enrichment.py` | P2 | T3 complete |
| T5 | Wire enrichment artifacts into `context-plus` reads | Optional: make semantic-navigate read cluster-labels.json | P2 | T4 complete |
| T6 | (Optional) Add OpenRouter-backed chat to `context-plus` | If live cluster labeling is desired | P3 | T1 complete |

### 6.2 Suggested Beads Task Titles

- **T0**: `bd-hil7.2a` - "Gate: validate OpenRouter embedding model availability"
- **T1**: `bd-hil7.3` - "Impl: local-only patch for OpenAI-compatible embeddings in contextplus"
- **T2**: `bd-hil7.4` - "Rollout: OPENROUTER_API_KEY to all canonical hosts"
- **T3**: `bd-hil7.5` - "Validate: context-plus embeddings on Codex, Claude Code, OpenCode"
- **T4**: `bd-hil7.6` - "Impl: nightly z.ai enrichment job for semantic labeling"
- **T5**: `bd-hil7.7` - "Wire: enrichment artifacts into context-plus semantic-navigate"
- **T6**: `bd-hil7.8` - "Impl: OpenRouter chat support in context-plus (deferred)"

### 6.3 Dependency Graph

```
This spec (bd-hil7.2)
  -> T0 (bd-hil7.2a): validate model availability [GATE]
     -> T1 (bd-hil7.3): local-only patch
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
- `contextplus/src/index.ts` - OpenCode config generator uses `environment` for local MCP config
- `contextplus/package.json` - Confirms `"type": "module"`, ESM-only, no exports/main
- `llm_common/providers/zai_client.py` - z.ai LLM client (reference for nightly job)
- `llm_common/providers/openrouter_client.py` - OpenRouter LLM client (reference for API patterns)
- `scripts/adapters/cc-glm.sh` - z.ai auth resolution pattern (reference)
- `docs/investigations/2026-03-16-context-backend-finalization.md` - Embedding model selection
- `docs/investigations/2026-03-16-epyc12-load-analysis.md` - Centralized Ollama rejection rationale
- `docs/investigations/2026-03-16-serena-contextplus-cass-research.md` - Architecture comparison
- `docs/investigations/TECHLEAD-REVIEW-serena-contextplus-cass.md` - Final architecture decision
- [OpenRouter Embeddings API](https://openrouter.ai/docs/api-reference/embeddings) - Confirms endpoint exists
- [OpenRouter Models](https://openrouter.ai/models?modality=embeddings) - Embedding model catalog

## 8. Revision History

| Date | Change |
|------|--------|
| 2026-03-16 | Initial spec |
| 2026-03-17 | Rev1: Fix patch strategy (upstream patch, not preload); fix model choice (text-embedding-3-small with validation gate); fix fleet config (per-client MCP env injection) |
