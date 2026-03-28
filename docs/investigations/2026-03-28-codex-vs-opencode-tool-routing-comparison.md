# Codex vs OpenCode MCP Tool-First Routing Comparison

**Date**: 2026-03-28  
**Runtime checked**: Codex CLI (`codex exec --json`)  
**Epic**: bd-rb0c  
**Subtask**: bd-e5z8  
**Mode**: qa_pass

## Merged Source Revisions Used

| Repo | Revision | Source |
|------|----------|--------|
| agent-skills | `db970b87dc99ec932336f57381b9aefee32d2710` | [PR #410](https://github.com/stars-end/agent-skills/pull/410) |
| prime-radiant-ai | `e1320248370ac4db9e810e22096d9beef26c9bbb` | [PR #1027](https://github.com/stars-end/prime-radiant-ai/pull/1027) |
| OpenCode pilot context | `8a49765ebbb35b53efe9e10255ecb8041bf96857` | [PR #411](https://github.com/stars-end/agent-skills/pull/411) |

## Commands Run

```bash
# Mandatory fetch/read flow
cd ~/agent-skills
git fetch origin pull/411/head:pr-411
git checkout pr-411
git fetch origin
git checkout db970b87dc99ec932336f57381b9aefee32d2710

cd ~/prime-radiant-ai
git fetch origin
git checkout e1320248370ac4db9e810e22096d9beef26c9bbb

# Connectivity validation
cd ~/prime-radiant-ai
codex mcp list
git rev-parse HEAD

# Worktree
cd ~/agent-skills
dx-worktree create bd-e5z8 agent-skills

# 6-case suite (isolated non-interactive runs)
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<CP1 prompt>" > /tmp/bd-e5z8-CP1.jsonl
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<CP2 prompt>" > /tmp/bd-e5z8-CP2.jsonl
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<LT1 prompt>" > /tmp/bd-e5z8-LT1.jsonl
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<LT2 prompt>" > /tmp/bd-e5z8-LT2.jsonl
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<SE1 prompt>" > /tmp/bd-e5z8-SE1.jsonl
codex exec --json --sandbox read-only -C ~/prime-radiant-ai "<SE2 prompt>" > /tmp/bd-e5z8-SE2.jsonl
```

## Codex Results

| Case | Expected | First Tool Used | Verdict | Note |
|------|----------|-----------------|---------|------|
| CP1 | context-plus | llm-tldr (`semantic`) | SOFT PASS | Expected tool skipped; explicit `Tool routing exception` returned; fallback invoked after MCP cancellations |
| CP2 | context-plus | llm-tldr (`semantic`) | SOFT PASS | Expected tool skipped; explicit `Tool routing exception` returned; used Serena/shell fallback for discovery |
| LT1 | llm-tldr | llm-tldr (`extract`) | RUNTIME FAIL | Correct first-tool selection, but first MCP call failed (`user cancelled MCP tool call`) |
| LT2 | llm-tldr | llm-tldr (`impact`) | RUNTIME FAIL | Correct first-tool selection, but first MCP call failed (`user cancelled MCP tool call`) |
| SE1 | serena | serena (`activate_project`) | PASS | Correct first-tool selection and successful symbol workflow |
| SE2 | serena | serena (`activate_project`) | PASS | Correct first-tool selection and successful symbol workflow |

## Comparison Against OpenCode PR #411

| Case | OpenCode | Codex | Comparison |
|------|----------|-------|------------|
| CP1 | RUNTIME FAIL (context-plus first, timeout) | SOFT PASS (llm-tldr first + exception) | different failure mode |
| CP2 | PASS (context-plus first) | SOFT PASS (llm-tldr first + exception) | worse than OpenCode |
| LT1 | PASS | RUNTIME FAIL | worse than OpenCode |
| LT2 | PASS | RUNTIME FAIL | worse than OpenCode |
| SE1 | PASS | PASS | same as OpenCode |
| SE2 | PASS | PASS | same as OpenCode |

## Summary

- routing compliance: **4/6** (expected tool selected first in LT1, LT2, SE1, SE2)
- runtime success: **4/6** (non-runtime-fail cases)
- tool routing exception uses: **4** (CP1, CP2, LT1, LT2)

### Delta vs OpenCode

- Codex-only residuals:
  - `context-plus` was not selected first in either semantic-discovery case (CP1/CP2)
  - `llm-tldr` first-call reliability degraded in both trace/impact cases (LT1/LT2 canceled)
- OpenCode-only residuals:
  - CP1 had context-plus timeout after correct first-tool selection (routing-conformant but flaky)

## Recommendation

**fix/re-test required**

Reason: Codex did not select `context-plus` first in either semantic case and showed repeat llm-tldr runtime cancellations in both llm-tldr cases; this is below OpenCode pilot behavior and below the desired tool-first reliability threshold for moving forward without another round.
