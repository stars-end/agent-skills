# OpenCode MCP Tool-First Routing Conformance Pilot

**Date**: 2026-03-28
**Runtime**: OpenCode (glm-5-turbo via `opencode`)
**Epic**: bd-rb0c
**Subtask**: bd-8zzt
**Mode**: qa_pass

## Merged Source Revisions

| Repo | Merge Commit | PR |
|------|-------------|-----|
| agent-skills | `db970b87dc99ec932336f57381b9aefee32d2710` | [#410](https://github.com/stars-end/agent-skills/pull/410) |
| prime-radiant-ai | `e1320248370ac4db9e810e22096d9beef26c9bbb` | [#1027](https://github.com/stars-end/prime-radiant-ai/pull/1027) |

## Commands Run

```bash
cd ~/agent-skills && git fetch origin && git checkout db970b87dc99ec932336f57381b9aefee32d2710 --detach
cd ~/prime-radiant-ai && git fetch origin && git checkout e1320248370ac4db9e810e22096d9beef26c9bbb --detach
opencode mcp list  # 3 servers connected: context-plus, llm-tldr, serena
~/agent-skills/scripts/dx-verify-clean.sh  # FAIL: pre-existing .tldr/ artifacts only
dx-worktree create bd-8zzt agent-skills
```

## Results

| Case | Expected | First Tool Used | Verdict | Note |
|------|----------|-----------------|---------|------|
| CP1 | context-plus | context-plus (timed out, 2 attempts) | RUNTIME FAIL | context-plus connected but returned timeout on semantic search; fell through to documented fallback path |
| CP2 | context-plus | context-plus | PASS | Returned 3 ranked results for V2 metrics/chart query |
| LT1 | llm-tldr | llm-tldr | PASS | Full structural extract + call graph for chartSpecToRecharts |
| LT2 | llm-tldr | llm-tldr | PASS | Importer search found 3 files importing from plaidLink |
| SE1 | serena | serena | PASS | Symbol found at line 525; zero referencing symbols (incomplete index) |
| SE2 | serena | serena | PASS | Symbol found with full body; insertion point clear |

## Compliance Summary

- **Overall rate**: 5/6 = 83%
- **PASS**: 5
- **RUNTIME FAIL**: 1
- **FAIL**: 0
- **SOFT PASS**: 0
- **Tool routing exceptions used**: 0

## Runtime Failures

### CP1 (context-plus timeout)

`context-plus_semantic_code_search` returned `MCP error -32001: Request timed out` on two consecutive attempts with different queries. The server showed as `connected` in `opencode mcp list`. CP2 succeeded shortly after with a different query.

This is a runtime reliability issue, not a routing/contract failure. The agent correctly attempted the expected tool first in both CP1 and CP2.

### Root Cause Analysis

**Most likely cause**: `context-plus` hit a cold-start semantic-search path where full-tree walking plus uncached embedding work exceeded the available request budget.

**Cache-compatibility edge (likely contributor)**:

The repo-local cache at `<repo>/.mcp_data/embeddings-cache.json` contained 748 entries (19 MB) but in V1 format (plain dict, no `version` field). The cache loader rejects V1-format caches when model validation is in effect:

```js
// V1 format (plain cache object) — reject when model validation is requested
if (expectedModel)
    return {};
```

Since `CONTEXTPLUS_EMBED_PROVIDER=auto` with an OpenRouter key present produces a non-null `expectedModel` (`"openai/text-embedding-3-small"`), the 748-entry cache was silently discarded on every load, forcing `context-plus` to behave as a cold start despite having a populated cache file.

**What happens on cold start**: `buildIndex()` walks the full repo tree (respecting `.gitignore`; skipping `node_modules`, `.git`, `dist`, `build`, `.mcp_data`, etc.), builds search documents per file, then embeds uncached documents via the OpenRouter API in batches before running the actual search. That full path can plausibly exceed the request budget.

**Timeout/fallback behavior**: `AbortError` is explicitly classified as non-retriable, and unknown errors default to no-retry. So timeout-like failures bypass the auto-mode OpenRouter-to-Ollama fallback regardless of whether the timeout originated at the HTTP layer or the MCP transport layer.

**What is not yet proven**:
- Whether the timeout occurred during index build, embedding, or query execution
- Whether CP2 succeeded because CP1 partially built and persisted the index, or due to some other factor (e.g., smaller effective search scope for the CP2 query)
- The exact file count processed by the walker (raw `find` counts include directories the walker skips)

**OpenRouter API health**: Direct test showed the API responding in 0.52s with valid embeddings, so the timeout was not caused by an OpenRouter outage.

## dx-verify-clean.sh Status

Script reported FAIL due to pre-existing `.tldr/` and `.tldrignore` files in agent-skills and prime-radiant-ai canonical clones. These are unrelated runtime artifacts (llm-tldr index files), not work from this task.

## Recommendation

**Advance to Codex comparison.**

Rationale:
- 5/6 cases passed with correct first-tool routing
- The single failure (CP1) is a runtime timeout, not a routing decision failure
- llm-tldr and serena showed 100% compliance across their cases
- context-plus reliability should be addressed separately (likely fix: upgrade the V1 cache to V2 format so the existing 748 entries are used instead of discarded)
- The Codex comparison should include retry logic for context-plus timeouts to distinguish "agent skips the tool" from "tool is flaky"
