# grepai + OpenRouter Semantic Spike

Date: 2026-04-29  
Beads: `bd-9n1t2.19`  
Mode: `qa_pass`

## Scope

Benchmark `grepai` using OpenRouter embeddings model `qwen/qwen3-embedding-8b` and answer:

1. Reliability with OpenRouter embeddings
2. Whether OpenRouter use is embeddings-only (no chat/completions dependency)
3. Indexing and query latency on real repos
4. Critical-path suitability vs async/on-demand enrichment value
5. Whether grepai can demote llm-tldr semantic default

## Prior Art / Inputs Fetched First

Requested PR/commit states were fetched and inspected:

- `agent-skills` PR 597 @ `4f23d6769351c247224006774cb734df883066b0`
- `affordabot` PR 447 @ `e0ed87f3f0072378008d99b5281169c65af10189`
- `prime-radiant-ai` PR 1119 @ `fa9abafe4c06bfe6fab39cb92871b5a329a38c32`
- `agent-skills` PR 592 @ `e1476ae9e1a0a007ce77916ac60fc47367203c7b`
- `agent-skills` PR 593 @ `79774cec2db1f337f54f10b3da0e9ddd95a831b3`
- `agent-skills` PR 594 @ `d662dcabe0710860bbd9c1b42a0a35aa83d165c8`

Required file presence notes:

- Missing in some referenced commits by design/time:
  - `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md` (missing in PR 592/597 commits)
  - `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md` (missing in PR 592/597 commits)
  - `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md` (missing in PR 592/597 commits)
  - `docs/architecture/2026-04-29-openrouter-cross-repo-contract-map.md` (missing in PR 592/593/594 commits)
  - `docs/investigations/2026-04-29-openrouter-env-contract.md` (missing in the referenced `agent-skills` commits; present in `affordabot`/`prime-radiant-ai` commits)

## Memory Retrieval (Required)

Commands run:

```bash
bdx memories llm-tldr --json
bdx memories grepai --json
bdx memories OpenRouter --json
bdx search "llm-tldr" --label memory --status all --json
bdx search "OpenRouter" --label memory --status all --json
bdx search "semantic mixed-health" --label memory --status all --json
```

Result: no matching records (`{}` / `[]`), so no follow-up `bdx show`/`bdx comments` was applicable.

## Primary Source Grounding

- grepai docs: <https://yoanbernabeu.github.io/grepai/>
- grepai init docs: <https://yoanbernabeu.github.io/grepai/commands/grepai_init/>
- grepai embedders docs: <https://yoanbernabeu.github.io/grepai/backends/embedders/>
- OpenRouter qwen embedding page: <https://openrouter.ai/qwen/qwen3-embedding-8b/api>
- OpenRouter embeddings endpoint/docs: <https://openrouter.ai/docs/api-reference/embeddings/create-embeddings>
- OpenRouter errors/docs: <https://openrouter.ai/docs/api/reference/errors-and-debugging>
- grepai source: <https://github.com/yoanbernabeu/grepai>

Additional source-level checks from grepai repository:

- `embedder/openrouter.go`: OpenRouter embedder hits `POST /embeddings`; no chat/completions path.
- `search/search.go`: one `embedder.Embed(...)` call per search query.
- `indexer/indexer.go`: indexing uses `EmbedBatch` / `EmbedBatches` over file chunks.

## Setup Commands (Executed)

```bash
# Workspace
dx-worktree create bd-9n1t2.19 agent-skills
dx-worktree create bd-9n1t2.19 affordabot

# Secret auth (cache-only, no secret print)
source /home/fengning/agent-skills/scripts/lib/dx-auth.sh
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY >/dev/null

# Install grepai (user-local to avoid sudo)
INSTALL_DIR="$HOME/.local/bin" timeout 120 sh -c 'curl -sSL https://raw.githubusercontent.com/yoanbernabeu/grepai/main/install.sh | sh'
timeout 120 /home/fengning/.local/bin/grepai version

# Required init shape
timeout 120 /home/fengning/.local/bin/grepai init \
  --provider openrouter \
  --model qwen/qwen3-embedding-8b \
  --backend gob \
  --yes
```

## Exact Config (No Secrets)

Generated `.grepai/config.yaml` (both repos):

```yaml
embedder:
  provider: openrouter
  model: qwen/qwen3-embedding-8b
  endpoint: https://openrouter.ai/api/v1
store:
  backend: gob
```

## Benchmark Timing Table

All benchmark commands were wrapped with `timeout 120 ...` unless intentionally testing shorter timeout behavior.

| Metric | agent-skills | affordabot | Notes |
|---|---:|---:|---|
| Install grepai (local bin) | 1.424s | n/a | One-time |
| `grepai init ...` | 49ms | 27ms | Fast |
| `grepai watch --background` return | 30.080s (status=1) | 30.087s (status=1) | Timed out waiting for ready; watcher process did start during attempts |
| `grepai watch --no-ui` cold run | 121.214s (status=124) | 122.015s (status=124) | Did not complete full index in 120s |
| Post-run index status | 396 files / 2099 chunks / 51.9 MB | 0 files / 0 chunks / 384 B | agent-skills partially materialized; affordabot did not |

## Critical-Path Query Latency

Representative 10-query set:

- where is semantic mixed-health handled?
- where are MCP hydration rules documented?
- where is OpenRouter or embedding provider configured?
- local government corpus structured source proof cataloged_intent live_proven
- where are Beads memory conventions defined?
- where is dx-worktree workflow documented?
- where are llm-tldr fallback scripts?
- where is OpenRouter API key read in this repo?
- where are PR metadata rules defined?
- where is tldr_contained_runtime.py used?

### Pre-index/empty-index behavior

| Repo | First query | 10-query p50 | 10-query p95 | Result quality |
|---|---:|---:|---:|---|
| agent-skills | 328ms | 519.5ms | 716ms | empty result sets |
| affordabot | 570ms | 447ms | 1483ms | empty result sets |

### Post-partial-index behavior (`agent-skills`)

| Metric | Value |
|---|---:|
| First query after partial index | 965ms |
| 10 representative queries p50 | 977.5ms |
| 10 representative queries p95 | 1774ms |
| Repeated single-query p50 (10 runs) | 1118ms |
| Repeated single-query p95 (10 runs) | 1847ms |

Observation: query-time cloud embedding contributes a near-constant floor even before vector retrieval does useful work.

## Failure Modes

### Timeout behavior

- `grepai watch --no-ui` under bounded runtime returned `124` at ~120s on both repos.
- During timeout cancellation, logs show many per-file errors like:
  - `failed to send request to OpenRouter ... context canceled`

### Network error behavior

- For a controlled bad endpoint test (`endpoint: http://127.0.0.1:9`), `grepai search` returned JSON error:
  - `failed to send request to OpenRouter ... connect: connection refused`

### Rate-limit behavior

- A live 429 was not reproduced in this run.
- OpenRouter docs explicitly list `429` for embeddings and general API rate limiting.

## Embedding Call Pattern (Observed / Source-Inferred)

- Query path: one embedding call per query (`search/search.go` uses `embedder.Embed(query)` once).
- Index path: batch embedding over chunks (`indexer/indexer.go` uses `EmbedBatch` / `EmbedBatches`).
- Exact indexing call count was not emitted as a single numeric counter in CLI output.

## `.grepai/` Worktree Containment

- `grepai init` creates `.grepai/` in repo root and appends `.grepai/` to `.gitignore`.
- This is worktree-local but still in-tree state; it requires explicit containment policy if adopted broadly.

## OpenRouter Dependency Scope

Answer: **OpenRouter usage in grepai is embedding-only for this workflow.**

- Source implementation for OpenRouter provider calls embedding endpoint only.
- No grepai search/index path dependency on chat/completions APIs was found.

## Privacy / IP Egress Risk

High for private repos when cloud embedder is enabled:

- Code chunks are sent to OpenRouter embeddings endpoint during indexing.
- Query text is sent to OpenRouter at query time.
- This violates strict local-only expectations unless a local embedder is used.

## Cost Estimate

Model pricing reference on qwen page is `$0.01` per 1M input tokens.

Order-of-magnitude estimate:

- Query path: tiny (short query text), effectively near-zero per query.
- Index path: potentially low direct dollar cost but high operational latency/coupling; rough range for medium repo indexing is still cents-level, but not zero.
- Cost certainty is limited without full successful index completion and token totals per run.

## Agent Cognitive Load

High for default-path usage:

- Requires secret auth + cloud uptime for each semantic query.
- Introduces additional failure classes (`network`, `429`, `402`, provider availability).
- Adds repo-local state management (`.grepai/`) and background watcher lifecycle.

## Founder HITL Load

High if used as critical-path default:

- Cold-indexing exceeds bounded agent time budget on tested repos.
- Needs operational babysitting when timeout/error states occur.
- Mixed index completeness can produce inconsistent semantic coverage.

## Answers to Objective Questions

1. **Does grepai work reliably with OpenRouter embeddings?**  
   Partially. Query calls are reliable at sub-2s, but full indexing did not complete within 120s on either tested repo.

2. **Is OpenRouter usage limited to embeddings, with no chat/completion dependency?**  
   Yes, for grepai semantic search/index flows.

3. **What is indexing latency on real repos?**  
   Exceeded 120s for both repos under bounded runs; `agent-skills` only reached partial index, `affordabot` remained effectively unindexed.

4. **What is live query embedding latency?**  
   Roughly ~0.8s to ~1.8s p95 band in this environment, depending on index state and repo.

5. **Does query-time cloud embedding make grepai unsuitable for critical-path default lookup?**  
   Yes for this environment and constraints.

6. **Is grepai useful as async/on-demand semantic enrichment?**  
   Yes, conditional on background indexing windows and non-critical usage.

7. **Can grepai demote llm-tldr semantic?**  
   Not as direct default replacement in this spike; no.

## Verdict

`async/on-demand enrichment only`

Rationale: useful capability, but current bounded runtime behavior and cloud dependency profile do not fit critical-path default lookup requirements.

## Draft PR Artifact

PR_URL: `TBD`  
PR_HEAD_SHA: `TBD`

