# Worker A Prompt: grepai + OpenRouter Semantic Spike

You are a spike worker agent at a tiny fintech startup. Your job is to benchmark grepai with OpenRouter Qwen embeddings and return evidence, not advocacy.

## DX Global Constraints

1. No writes in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`.
2. Worktree first: `dx-worktree create bd-9n1t2.19 agent-skills`.
3. Open a draft PR after the first real commit.
4. Before done, run `~/agent-skills/scripts/dx-verify-clean.sh`.
5. Final response must include `PR_URL`, `PR_HEAD_SHA`, and `BEADS_SUBTASK: bd-9n1t2.19`.

## Secret-Auth Safety

- Do not run raw `op read`, `op item get`, `op item list`, or `op whoami`.
- Use only cached/service-account helpers.
- For OpenRouter, use:

```bash
DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached op://dev/Agent-Secrets-Production/OPENROUTER_API_KEY
```

- Do not print the secret.
- If cache/service-account auth is unavailable, return exactly:

```text
BLOCKED: secret_auth_cache_unavailable
```

## Assignment Metadata

- MODE: qa_pass
- BEADS_EPIC: bd-9n1t2
- BEADS_SUBTASK: bd-9n1t2.19
- BEADS_DEPENDENCIES: bd-9n1t2.17
- FEATURE_KEY: bd-9n1t2.19
- CLASS: product
- UPDATE_EXISTING_PR: false
- PR_STATE_TARGET: draft
- REQUIRE_MERGE_READY: false
- SELF_REPAIR_ON_CHECK_FAILURE: true
- FINAL_RESPONSE_MODE: qa_findings

## Required Prior Art

Fetch and read:

```bash
git fetch origin master --prune
git fetch origin pull/592/head:pr-592
git fetch origin pull/593/head:pr-593
git fetch origin pull/594/head:pr-594
```

Read these repo paths from the fetched refs where present:

- `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`
- `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`
- `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md`
- `extended/llm-tldr/SKILL.md`
- `fragments/dx-global-constraints.md`
- `scripts/tldr_contained_runtime.py`
- `scripts/tldr-daemon-fallback.sh`

If a file is missing in a prior-art PR, note it and continue.

## Required Sources

Inspect official docs/source:

- `https://yoanbernabeu.github.io/grepai/`
- `https://yoanbernabeu.github.io/grepai/commands/grepai_init/`
- `https://yoanbernabeu.github.io/grepai/backends/embedders/`
- `https://openrouter.ai/qwen/qwen3-embedding-8b/api`
- `https://github.com/yoanbernabeu/grepai`

Use primary sources for claims. Record source URLs in the memo.

## Objective

Answer:

- Does grepai work reliably with OpenRouter embeddings?
- Is OpenRouter usage limited to embeddings, with no chat/completion dependency?
- What is indexing latency on real repos?
- What is live query embedding latency?
- Does query-time cloud embedding make grepai unsuitable for critical-path default lookup?
- Is grepai useful as async/on-demand semantic enrichment?
- Can grepai demote `llm-tldr` semantic?

## Required Benchmarks

Run against at least:

- `agent-skills`
- `affordabot`
- optionally `prime-radiant-ai` if setup is cheap and safe

Measure:

- install time
- `grepai init --provider openrouter --model qwen/qwen3-embedding-8b --backend gob --yes`
- index/build time
- watcher or incremental update behavior
- first semantic query latency
- repeated semantic query latency
- p50/p95 over at least 10 representative semantic queries
- failure behavior under timeout
- OpenRouter rate-limit or network errors
- number of embedding calls during indexing vs querying if observable
- whether `.grepai/` is created in the worktree and whether containment/gitignore handling is needed

Representative queries:

- `where is semantic mixed-health handled?`
- `where are MCP hydration rules documented?`
- `where is OpenRouter or embedding provider configured?`
- `local government corpus structured source proof cataloged_intent live_proven`
- `where are Beads memory conventions defined?`

Wrap benchmark commands:

```bash
timeout 120 <command>
```

## Deliverable

Create:

```text
docs/architecture/2026-04-27-grepai-openrouter-semantic-spike.md
```

Include:

- setup commands
- exact config excluding secrets
- timing table
- critical-path latency table
- async-indexing suitability
- privacy/IP egress risk
- cost estimate
- failure modes
- agent cognitive load
- founder HITL load
- verdict: replace `llm-tldr` semantic, async/on-demand enrichment only, or reject
- draft PR URL/head SHA

## Done Gate

Do not claim complete until:

- memo exists
- changes are committed and pushed
- draft PR exists
- `~/agent-skills/scripts/dx-verify-clean.sh` passes
- final response includes:

```text
PR_URL: https://github.com/stars-end/agent-skills/pull/<n>
PR_HEAD_SHA: <40-char sha>
BEADS_SUBTASK: bd-9n1t2.19
```

If blocked, return:

```text
BLOCKED: <reason_code>
NEEDS: <single dependency/info needed>
NEXT_COMMANDS:
bdx show bd-9n1t2.19 --json
```
