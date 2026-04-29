# OpenRouter Cross-Repo Contract Map

Date: 2026-04-29  
Beads: `bd-9n1t2.23`  
Inputs:

- Affordabot investigation: https://github.com/stars-end/affordabot/pull/446 @ `e3b81f5839687959fa8cae41eec165da459f3dd9`
- Prime Radiant investigation: https://github.com/stars-end/prime-radiant-ai/pull/1118 @ `6fc8bcfb3ae69fcebf3b9f2768deb425d9cdf983`
- Affordabot OpenRouter env contract: https://github.com/stars-end/affordabot/pull/447 @ `e0ed87f3f0072378008d99b5281169c65af10189`
- Prime Radiant OpenRouter env contract: https://github.com/stars-end/prime-radiant-ai/pull/1119 @ `fa9abafe4c06bfe6fab39cb92871b5a329a38c32`
- grepai/OpenRouter semantic spike rerun: https://github.com/stars-end/agent-skills/pull/598 @ `7a62cfdae91beed0214c1762098a2b58d1ecdc65`
- affordabot OpenRouter guard repair: https://github.com/stars-end/affordabot/pull/448 @ `36b289e7febe6dc95f68bac0ec1ae6857b120ae2`
- Prior llm-tldr synthesis: https://github.com/stars-end/agent-skills/pull/595

## Decision

`ALL_IN_NOW`: stabilize OpenRouter as a shared operational contract.

`DEFER_TO_P2_PLUS`: defer any LiteLLM-vs-custom-client architecture change.

Reason: both downstream apps already depend on OpenRouter paths, especially embeddings, but neither investigation found active direct LiteLLM runtime usage. A LiteLLM migration now would be an architecture change without enough call-site evidence. An OpenRouter contract map reduces immediate drift and also unblocks the grepai/OpenRouter llm-tldr semantic spike.

## Current Secret-Auth Status

Agent-safe cache check passed on 2026-04-29:

```bash
source /home/fengning/agent-skills/scripts/lib/dx-auth.sh
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY >/dev/null
```

Result:

```text
OPENROUTER_CACHE_OK
```

Implication: the earlier `bd-9n1t2.19` grepai/OpenRouter blocker should be re-tested with the same cache-only contract before closing that lane.

## Live OpenRouter Embedding Probe Status

The app-side OpenRouter contract inventories added no-secret-print qwen embedding probes and validated the same OpenRouter model needed by grepai:

| Repo | PR | Model | Dimensions | Observed Latency | Result |
|---|---|---|---:|---:|---|
| affordabot | https://github.com/stars-end/affordabot/pull/447 | `qwen/qwen3-embedding-8b` | 4096 | 946 ms | pass |
| prime-radiant-ai | https://github.com/stars-end/prime-radiant-ai/pull/1119 | `qwen/qwen3-embedding-8b` | 4096 | 908 ms | pass |

These probes validate OpenRouter auth, model routing, and embedding dimensionality, but they do not prove grepai indexing/query behavior. The grepai spike still needs tool-specific measurements for index latency, query embedding latency, retrieval latency, failure behavior, and worktree state containment.

## grepai/OpenRouter Rerun Result

Rerun artifact: https://github.com/stars-end/agent-skills/pull/598 @ `7a62cfdae91beed0214c1762098a2b58d1ecdc65`

Evidence quality review:

- Accepted: official grepai/OpenRouter docs and source were inspected.
- Accepted: OpenRouter usage was source-checked as embeddings-only for grepai index/search.
- Accepted: benchmark commands used bounded `timeout 120`.
- Accepted: `agent-skills` and `affordabot` were both attempted as real repos.
- Accepted: latency measurements separate empty/partial-index query behavior from indexing behavior.
- Caveat: the worker memo's embedded PR head line trails the final metadata-only repair commit, which is self-referential if kept perfectly current. Treat GitHub PR metadata above as the PR-head source of truth.

Measured result:

| Measurement | Result |
|---|---|
| `grepai init` | Fast: 49 ms on `agent-skills`, 27 ms on `affordabot` |
| Cold index/watch bounded at 120s | Did not complete on either repo |
| `agent-skills` partial index | 396 files / 2099 chunks / 51.9 MB |
| `affordabot` index | 0 files / 0 chunks after bounded run |
| Query latency after partial index | p50 977.5 ms, p95 1774 ms |
| Repeated single-query latency | p50 1118 ms, p95 1847 ms |
| Failure modes | Timeout cancellation; provider/network errors are legible |

Conclusion: `grepai + OpenRouter` is viable only as async/on-demand semantic enrichment. It should not demote or replace `llm-tldr` semantic in the default critical-path lookup loop.

## Cross-Repo Findings

| Topic | Affordabot | Prime Radiant | Contract Implication |
|---|---|---|---|
| `llm_common` use | Broad runtime use in services, agents, routers, ingestion, retrieval, cron/substrate scripts | Broad runtime use in advisor services, APIs, RAG, agents, provenance, retrieval, history | Treat `llm_common` APIs as the current shared boundary |
| LiteLLM | Dependency present; no direct runtime imports/calls found | Dependency present; no direct backend runtime imports/calls found | Do not choose LiteLLM migration until active call sites are mapped and a concrete target API is proposed |
| OpenRouter chat | Fallback provider through `OpenRouterClient`; direct AsyncOpenAI fallback in classifier | Configured via shared `llm_common` OpenRouter client; local legacy OpenRouter client also exists | Preserve current chat behavior while mapping duplicate paths |
| OpenRouter embeddings | Active OpenAI-compatible embedding endpoint using `qwen/qwen3-embedding-8b`, 4096 dims | OpenAI-compatible embeddings via `OpenAIEmbeddingService`, OpenRouter fallback key/base URL; default model may differ | Embedding contract needs model/dimension normalization before reuse by grepai or RAG work |
| Env contract | `OPENROUTER_API_KEY` active; `OPENROUTER_BASE_URL` mostly historical/not active; site metadata not active | `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`, `OPENROUTER_DEFAULT_MODEL`, site metadata active in config | Use additive env alignment, not rename/removal |
| Drift risk | Multiple initialization paths for runtime and scripts | Multiple provider paths: shared clients, pydantic-ai, local legacy client | Start with inventory and checks, not provider rewrites |

## Stable Contract Today

These are safe assumptions for follow-on work:

1. `OPENROUTER_API_KEY` is the required secret name.
2. Agent workflows must read it only through:

```bash
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY
```

3. Runtime apps should receive OpenRouter secrets through app environment, not agent shell state.
4. `llm_common` is the current shared API surface for both repos.
5. OpenRouter embeddings should use an OpenAI-compatible endpoint shape.
6. `qwen/qwen3-embedding-8b` is already used and documented by affordabot; any cross-repo adoption must pin dimensions and confirm Prime compatibility before switching defaults.

## Open Questions

1. Should Prime standardize on `qwen/qwen3-embedding-8b` for RAG, or keep its existing `EMBEDDING_MODEL` default until a RAG-specific test proves parity?
2. Should affordabot adopt active `OPENROUTER_BASE_URL`, `OPENROUTER_SITE_URL`, and `OPENROUTER_SITE_NAME` env vars to match Prime, or should those stay optional metadata only?
3. Which local/legacy OpenRouter clients are still invoked in production paths versus retained for tests or archives?
4. Should `llm_common` expose one small OpenRouter embedding factory so both apps stop duplicating base URL/model/dimension choices?
5. Should grepai use the app-level embedding contract or remain an agent-tool-only experiment?

## Recommended Work Order

### 1. OpenRouter Auth + Env Inventory

Decision: `ALL_IN_NOW`

Create a small, source-grounded inventory for each repo:

- required OpenRouter env vars
- optional OpenRouter env vars
- runtime code paths that consume each var
- Railway service/environment targets where the vars must exist
- smoke commands that verify key presence without printing secrets

Do not mutate Railway until the inventory identifies exact project/environment/service targets.

### 2. Repo-Level Smoke Tests

Decision: `ALL_IN_NOW`

Add or standardize no-secret-printing smokes:

- affordabot: OpenRouter embedding smoke for `qwen/qwen3-embedding-8b`, expected dimension 4096
- Prime Radiant: OpenRouter chat smoke via current `llm_common` path; RAG embedding smoke if `USE_PGVECTOR_RAG` is enabled

Smokes should skip or fail with a clear reason when `OPENROUTER_API_KEY` is absent. They should report model, latency, token/dimension metadata when available, and never print the key.

### 3. Re-Run grepai/OpenRouter Spike

Decision: `DEFER_TO_P2_PLUS` after auth inventory

Status on 2026-04-29: re-dispatched under `bd-9n1t2.19` after OpenRouter cache and app-side qwen embedding probes passed. Result: `async/on-demand enrichment only`; do not make it the default first-hop semantic lookup.

Re-dispatch `bd-9n1t2.19` only after confirming agent-safe OpenRouter cache in the worker runtime. Required measurements remain:

- install/init time
- index/build time
- incremental index behavior
- live query embedding latency
- retrieval latency
- p50/p95 over representative queries
- embedding call count if observable
- timeout/rate-limit behavior
- `.grepai/` containment implications

Classification target: async/on-demand semantic enrichment unless query-time cloud embedding is exceptionally fast and reliable.

Actual classification: async/on-demand semantic enrichment only.

### 3a. Affordabot Guard Drift Repair

Decision: `ALL_IN_NOW`

Follow-up PR opened: https://github.com/stars-end/affordabot/pull/448

Reason: app-side inventory found several paths that accepted `OPENAI_API_KEY` or `ZAI_API_KEY` as sufficient while constructing OpenRouter-backed embedding clients. The repair makes those OpenRouter paths require `OPENROUTER_API_KEY` explicitly and adds an OPENAI-only regression test for the cron harvester path.

### 3b. Prime RAG qwen Dimension Validation

Decision: `DEFER_TO_P2_PLUS` until exact Railway target context is supplied

Beads: `bd-9n1t2.27`

Railway auth works, but the Prime worktree has no linked project and checked-in source does not prove the exact project/environment/service id. Per the no-guessing Railway contract, do not mutate or run app-level RAG validation until the backend Railway target is known.

### 4. LiteLLM Architecture Decision

Decision: `DEFER_TO_P2_PLUS`

Do not migrate provider routing to LiteLLM yet.

Prerequisites:

- affordabot and Prime active call-site maps are complete
- `llm_common` revision/pin drift is understood
- custom clients that are truly redundant are identified
- z.ai-specific features and pydantic-ai paths are either supported or intentionally excluded
- cost tracking and fallback behavior are equivalent or better

### 5. CodeGraphContext Structural Complement

Decision: `DEFER_TO_P2_PLUS`

Keep separate from OpenRouter work. It does not depend on cloud provider auth and should not be bundled into the OpenRouter contract.

## What Not To Do Yet

- Do not switch either app to LiteLLM routing globally.
- Do not remove custom `OpenRouterClient` or local legacy clients.
- Do not rename env vars.
- Do not make OpenRouter cloud embeddings mandatory in the agent critical path.
- Do not set Railway variables by guessing project/service context.
- Do not treat grepai success as app-runtime proof; grepai is an agent-tool spike unless explicitly promoted.

## Immediate Next Command Set

For an agent-safe grepai retry:

```bash
source /home/fengning/agent-skills/scripts/lib/dx-auth.sh
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY >/dev/null
```

For repo env inventory, start from the two investigation PRs and inspect live code paths only:

```bash
rg -n "OPENROUTER|openrouter|qwen/qwen3-embedding-8b|OpenRouterClient|OpenAIEmbeddingService|litellm|LiteLLM" <repo>
```

For app runtime mutation, first identify Railway target explicitly:

```bash
railway status
railway variables --service <service>
```

Use `railway run -p <project-id> -e <environment> -s <service> -- <cmd>` or a repo-native `dx-railway-run.sh` wrapper from worktrees. Do not rely on ambient linked state from another repo.
