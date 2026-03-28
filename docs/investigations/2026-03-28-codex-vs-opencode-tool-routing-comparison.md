# Codex vs OpenCode MCP Tool-First Routing Comparison (Round 2 Retest)

**Date**: 2026-03-28  
**Runtime checked**: Codex CLI (`codex exec --json`)  
**Epic**: bd-rb0c  
**Subtask**: bd-e5z8  
**Mode**: qa_pass

## Why PR #413 Was Invalid/Incomplete

PR #413 did not fully control for the retest integrity conditions requested for this comparison:
- it did not explicitly enforce and document the fresh-retry rule for LT1/LT2 after first-call cancellation
- it did not explicitly document controlled semantic-case session root checks for `prime-radiant-ai`
- it mixed strong conclusions with incomplete runtime controls

This round re-runs the suite with those controls applied.

## Controlled Conditions In This Retest

- Semantic-case execution root controlled via `codex exec -C /Users/fengning/prime-radiant-ai`
- Pre-suite target SHA verified in `prime-radiant-ai`: `e1320248370ac4db9e810e22096d9beef26c9bbb`
- First-tool evidence taken from JSONL events only (no inference from prose)
- LT1/LT2 rerun once in a fresh attempt after first-call cancellation
- No Workflow B work (`bd-4a8e`) performed: no context-plus/runtime config changes, no repair lane work

## Source Revisions Used

| Repo | Revision | Source |
|------|----------|--------|
| agent-skills | `db970b87dc99ec932336f57381b9aefee32d2710` | [PR #410](https://github.com/stars-end/agent-skills/pull/410) |
| prime-radiant-ai | `e1320248370ac4db9e810e22096d9beef26c9bbb` | [PR #1027](https://github.com/stars-end/prime-radiant-ai/pull/1027) |
| OpenCode pilot baseline | `8a49765ebbb35b53efe9e10255ecb8041bf96857` | [PR #411](https://github.com/stars-end/agent-skills/pull/411) |

## Commands Run

```bash
# Step 0 PR artifacts
cd ~/agent-skills
git fetch origin pull/413/head:pr-413
git fetch origin pull/411/head:pr-411
git checkout pr-413
# read PR #413 memo on branch
# read PR #411 memo via git show pr-411:...

git fetch origin
git checkout db970b87dc99ec932336f57381b9aefee32d2710

cd ~/prime-radiant-ai
git fetch origin
git checkout e1320248370ac4db9e810e22096d9beef26c9bbb

# validation
cd ~/prime-radiant-ai
codex mcp list
git rev-parse HEAD

# worktree
cd ~/agent-skills
dx-worktree create bd-e5z8 agent-skills

# suite (all from prime-radiant-ai context)
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<CP1 prompt>" > /tmp/bd-e5z8-r2-CP1.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<CP2 prompt>" > /tmp/bd-e5z8-r2-CP2.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<LT1 prompt>" > /tmp/bd-e5z8-r2-LT1-a1.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<LT2 prompt>" > /tmp/bd-e5z8-r2-LT2-a1.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<SE1 prompt>" > /tmp/bd-e5z8-r2-SE1.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<SE2 prompt>" > /tmp/bd-e5z8-r2-SE2.jsonl

# required fresh retries after canceled first-call for LT cases
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<LT1 prompt>" > /tmp/bd-e5z8-r2-LT1-a2.jsonl
codex exec --json --sandbox read-only -C /Users/fengning/prime-radiant-ai "<LT2 prompt>" > /tmp/bd-e5z8-r2-LT2-a2.jsonl
```

## Codex Results

| Case | Expected | First Tool Used | Verdict | Note | Vs OpenCode |
|------|----------|-----------------|---------|------|-------------|
| CP1 | context-plus | llm-tldr (`tree`) | SOFT PASS | expected tool skipped; valid `Tool routing exception` returned; response paths stayed in `prime-radiant-ai` | different failure mode |
| CP2 | context-plus | llm-tldr (`semantic`) | SOFT PASS | expected tool skipped; valid `Tool routing exception` returned | worse |
| LT1 | llm-tldr | llm-tldr (`extract`) | RUNTIME FAIL | first call canceled in attempt 1 and fresh retry attempt 2 (same failure) | worse |
| LT2 | llm-tldr | llm-tldr (`impact`) | RUNTIME FAIL | first call canceled in attempt 1 and fresh retry attempt 2 (same failure) | worse |
| SE1 | serena | serena (`activate_project`) | PASS | expected tool selected first and succeeded | same |
| SE2 | serena | serena (`initial_instructions`) | PASS | expected tool selected first and succeeded | same |

## Comparison Against OpenCode PR #411

- OpenCode CP2/LT1/LT2 were PASS; Codex remained below that in this controlled rerun.
- OpenCode CP1 was a context-plus-first runtime failure; Codex CP1 remained a skip-with-exception path (different failure mode).
- Serena behavior remained aligned (SE1/SE2 PASS in both runtimes).

## Summary

- routing compliance: **4/6** (expected tool first in LT1, LT2, SE1, SE2)
- runtime success: **4/6** (non-runtime-fail cases)
- `Tool routing exception` uses: **4** (CP1, CP2, LT1, LT2)

## Recommendation

**fix/re-test required**

Codex still does not select `context-plus` first for semantic cases and still exhibits repeat `llm-tldr` first-call cancellation in LT1/LT2 even after the required clean retry. This is not yet at the OpenCode baseline quality level.

## Workflow Separation

If follow-up is needed, treat it as **separate Workflow B (`bd-4a8e`)** for runtime/config repair. No Workflow B changes were made in this QA run.
