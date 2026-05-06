# 2026-04-30 CocoIndex Code Product Bakeoff (`ccc`)

## Problem statement

This rerun exists because prior discussion mixed up:

- CocoIndex V1 framework (`cocoindex>=1.0.0`, PR #604), and
- CocoIndex Code product (`cocoindex-code`, `ccc`, prior PR #602 context referenced by PR #603).

The actual product question is:

> Can current `cocoindex-code` / `ccc` work as a drop-in semantic search replacement (or demotion target) for failing/fragile `llm-tldr semantic`?

## Source/version/install evidence

- Prior synthesis context reviewed:
  - PR #600: [https://github.com/stars-end/agent-skills/pull/600](https://github.com/stars-end/agent-skills/pull/600)
  - PR #603: [https://github.com/stars-end/agent-skills/pull/603](https://github.com/stars-end/agent-skills/pull/603)
  - PR #604: [https://github.com/stars-end/agent-skills/pull/604](https://github.com/stars-end/agent-skills/pull/604)
- Memory lookup (required):
  - `bdx memories cocoindex --json` => `{}`
  - `bdx memories cocoindex-code --json` => `{}`
  - `bdx memories llm-tldr --json` => `{}`
  - `bdx search "cocoindex-code" --label memory --status all --json` => `[]`
  - `bdx search "llm-tldr replacement" --label memory --status all --json` => `[]`
- Upstream product source verified:
  - repo: [https://github.com/cocoindex-io/cocoindex-code](https://github.com/cocoindex-io/cocoindex-code)
  - observed commit required by orchestrator present: `51ea6efea1878ca1b412b155adedbadc1dd611ad`
  - local disposable clone resolved to same HEAD.
- Local runtime evidence:
  - `ccc --help` includes: `init/index/search/status/reset/doctor/mcp/daemon`
  - `ccc doctor` global model checks passed
  - `uv tool list`: `cocoindex-code v0.2.31`
  - `uv tool run --from 'cocoindex-code[full]' ...`:
    - `cocoindex-code 0.2.31`
    - `cocoindex 1.0.2`

## Setup commands

```bash
# Worktree-first edits (canonical clone untouched)
dx-worktree create bd-9n1t2.30.5 agent-skills

# Upstream verification
git ls-remote https://github.com/cocoindex-io/cocoindex-code.git 51ea6efea1878ca1b412b155adedbadc1dd611ad
git clone --depth 1 https://github.com/cocoindex-io/cocoindex-code.git /tmp/cocoindex-code-upstream

# Product checks
ccc --help
ccc doctor
ccc daemon stop

# Disposable benchmark roots only
/tmp/cocoindex-code-bench-bd-9n1t2.30.5/*
```

## Host contention note

At benchmark start, host showed high unrelated `llm-tldr` CPU load (load average ~69/65/58; multiple `tldr-mcp-contained`/index processes). This is recorded as confounder, not auto-failure cause.

## Required benchmark results

## `agent-skills` (full-surface) evidence

### Initial run (required path)

- `ccc init --force`: `elapsed_ms=4235`
- `ccc doctor`: `elapsed_ms=35088`
  - file walk matched `856` files
- first bounded full index: `timeout 300 ccc index`
  - `elapsed_ms=300050`
  - terminal output: `Indexing failed: Connection to daemon lost during indexing`

### Single bounded retry (required adjustment)

Fresh disposable copy + one bounded retry only:

- `timeout 900 ccc index`
  - `elapsed_ms=900025` (timed out)
  - no success completion line emitted
- post-timeout `ccc status`:
  - `Indexing in progress: 856 files listed | 356 added`
  - `Chunks: 3633`, `Files: 356` (partial only)
- immediate search after retry:
  - `elapsed_ms=120055` (timed out)
  - no result payload emitted
- state after partial indexing:
  - `.cocoindex_code/` size: `31M`
  - `target_sqlite.db`: `19M`
  - `cocoindex.db`: `12M`

Interpretation: on this real repo, `ccc` did useful partial work but failed bounded completion and was not reliably query-ready under bounded execution.

## `affordabot` (scoped clean surface) evidence

Disposable copy with explicit excludes (non-code/generated/artifact heavy paths removed before indexing):

- removed directories:
  - `.git`, `node_modules`, `.next`, `dist`, `build`, `coverage`, `.turbo`, `.playwright`, `playwright-report`, `test-results`, `screenshots`, `artifacts`
- removed matching files:
  - `screenshot_*.png`, `*.log`, `*.tmp`

Timings:

- `ccc init --force`: `1079 ms`
- `ccc doctor`: `22698 ms` (matched files: `944`)
- first index (`timeout 600 ccc index`): `600020 ms` (timed out)
- second no-change index: `18264 ms` (completed; `Chunks 8806`, `Files 929`)
- incremental index after one-file edit: `2204 ms`
- `ccc status`: `1042 ms`
- first query: `1040 ms`
- repeated query: `824 ms`

10-query sample latency:

- count: `10`
- p50: `1114 ms`
- p95: `1870 ms`

## Critical-path latency table

| Repo | Step | Result |
|---|---|---|
| agent-skills (full) | first index | 300050 ms + daemon disconnect |
| agent-skills (fresh retry) | bounded retry index | 900025 ms timeout, partial state |
| agent-skills (fresh retry) | post-timeout search | 120055 ms timeout |
| affordabot (scoped clean copy) | first index | 600020 ms timeout |
| affordabot (scoped clean copy) | second no-change index | 18264 ms success |
| affordabot (scoped clean copy) | incremental | 2204 ms success |
| affordabot (scoped clean copy) | query p50 / p95 | 1114 / 1870 ms |

## Result quality examples (successes + misses)

Successes:

- Affordabot conceptual query about memory conventions returned repo-memory/addendum docs quickly with good semantic proximity.
- Affordabot query for mixed-health/verification surfaced policy/pipeline docs and tests with relevant terms.

Misses/noisy results:

- Affordabot query for Stripe webhook signature verification did not clearly return canonical implementation first; top hits included artifact/report markdown.
- Agent-skills full-repo path never reached stable searchable state under bounded index + query windows.

## Failure behavior under `timeout`

- `agent-skills`: hard evidence of daemon disconnect on first bounded index, and 900s retry timing out with partial state.
- `affordabot`: first index timed out at 600s, but subsequent no-change and incremental commands succeeded quickly.
- `timeout 1 ccc index` used as forced failure path also confirms bounded-command failure behavior can occur before usable state.

## Daemon behavior and process/state observations

- CLI surface includes `ccc daemon status|stop|restart`.
- `ccc` auto-starts daemon on first use (matches README claim).
- `ccc mcp --help` works; MCP server mode is stdio.
- Daemon status showed loaded project states (`idle` / `indexing`).
- Product can leave partially indexed DB state after timeout (`target_sqlite.db` present and growing).

## State/cache location and containment

- Per-repo state: `<repo>/.cocoindex_code/`
  - `settings.yml`
  - `target_sqlite.db`
  - `cocoindex.db`
- In observed runs:
  - agent-skills partial state: `.cocoindex_code` ~31M
  - affordabot scoped state: `.cocoindex_code` ~68M
- README and observed behavior align: `.cocoindex_code/` should be gitignored; indexing must run only in disposable worktrees/copies for this workflow.

## MCP/skill integration shape

Upstream README documents:

- skill path (`npx skills add cocoindex-io/cocoindex-code`)
- MCP path (`ccc mcp`)
- Codex/Claude MCP add examples
- single exposed search tool in MCP mode.

Local CLI confirms MCP entrypoint exists (`ccc mcp`).

## Privacy/IP egress assessment

With `[full]` local embedding mode, query/index embedding compute is local after model availability.  
However, daemon logs showed outbound HuggingFace requests on first-run/model validation (`HEAD`/`GET` against `huggingface.co` and `api/resolve-cache/...` for `Snowflake/snowflake-arctic-embed-xs`).

Implication:

- not fully offline by default on cold model cache
- outbound model metadata/artifact fetch behavior must be accepted or pre-cached.

## Cost assessment

- `[full]` avoids per-query embedding API spend when local mode is active.
- Operational cost shifts to:
  - heavy local CPU/RAM during indexing
  - long first-index wall times on larger/complex repos
  - cognitive overhead handling partial/indexing-in-progress states.

## Agent cognitive-load assessment

- Positive:
  - straightforward CLI verbs once stable (`status`, warm `search`).
- Negative:
  - bounded first-index behavior is hard to reason about (timeouts, disconnects, partial in-progress states).
  - index readiness is not binary in practice; requires extra operator interpretation.

Net: higher-than-desired cognitive overhead for default first-hop routing.

## Founder HITL-load assessment

- For drop-in default use: too high (index completion uncertainty and timeout triage).
- For optional async enrichment after baseline retrieval: acceptable if explicitly non-blocking.

## Comparison to alternatives

## Targeted `rg` + direct reads (local deterministic)

Sample timed lookups from same disposable copies:

- MCP hydration rules (`agent-skills`): `18 ms`
- Beads memory conventions (`agent-skills`): `26 ms`
- Stripe webhook signature search (`affordabot`): `99 ms` (no immediate hit, but deterministic and transparent)

`rg` remains dramatically lower-latency and operationally predictable for first-hop discovery.

## grepai local-Ollama (PR #600)

PR #600 verdict was async/on-demand only; warm semantic utility exists but readiness and watcher behavior increased operational complexity. `ccc` shows similar “helpful when warm” behavior but with its own index lifecycle brittleness on real repos.

## CocoIndex V1 framework result (PR #604)

PR #604 tested framework-only path (`cocoindex>=1.0.0`) and explicitly excluded product `ccc`. Current rerun confirms product behavior can diverge materially from framework-only timing/stability evidence.

## `llm-tldr semantic` pain context

Current fragility in `llm-tldr semantic` motivated this bakeoff, but `ccc` did not demonstrate robust drop-in readiness across required repos under bounded realistic execution.

## Verdict

`async/on-demand semantic enrichment only`

## Direct answer to core question

Was ripping out `cocoindex-code` / `ccc` from consideration too aggressive?

**Partially yes**: removing it entirely was too aggressive for optional enrichment use, because warm/scoped behavior can be useful.  
**But no for drop-in replacement**: current product behavior on full `agent-skills` (300s disconnect + 900s timeout + partial indexing + timed-out search) is not strong enough for default first-hop semantic replacement.

## Draft PR metadata

- PR_URL: https://github.com/stars-end/agent-skills/pull/606
- PR_HEAD_SHA: b2de35491baf78b8e5e22fb7ec3b365121e589f8
