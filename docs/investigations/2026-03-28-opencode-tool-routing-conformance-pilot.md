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

1. **CP1 (context-plus timeout)**: `context-plus_semantic_code_search` returned `MCP error -32001: Request timed out` on two consecutive attempts with different queries. The server showed as `connected` in `opencode mcp list`. This suggests either an embedding backend issue (OpenRouter/Ollama latency) or the patched build hanging on index build. CP2 succeeded moments later with a different query, suggesting intermittent rather than permanent failure.

## dx-verify-clean.sh Status

Script reported FAIL due to pre-existing `.tldr/` and `.tldrignore` files in agent-skills and prime-radiant-ai canonical clones. These are unrelated runtime artifacts (llm-tldr index files), not work from this task.

## Recommendation

**Advance to Codex comparison.**

Rationale:
- 5/6 cases passed with correct first-tool routing
- The single failure (CP1) is a runtime timeout, not a routing decision failure — the agent correctly attempted the expected tool first
- llm-tldr and serena showed 100% compliance across their cases
- context-plus passed 1/2 (intermittent timeout), which is a reliability concern but not a contract awareness failure
- The Codex comparison should include retry logic for context-plus timeouts to distinguish "agent skips the tool" from "tool is flaky"
