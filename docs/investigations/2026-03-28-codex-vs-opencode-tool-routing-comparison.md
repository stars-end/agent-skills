# Codex vs OpenCode MCP Tool-First Routing Comparison (Post-PR-426 Rerun)

**Date**: 2026-03-29  
**Runtime checked**: Codex CLI (`codex exec --json`)  
**Epic**: bd-rb0c  
**Subtask**: bd-e5z8  
**Mode**: qa_pass

## Why The Pre-PR-426 Codex Result Was Stale/Partially Stale

The previous Codex memo in PR #413 scored semantic cases against the old context-plus-first contract. PR #426 replaced that contract: semantic discovery now routes to `llm-tldr` by default, and `context-plus` is experimental/optional.

So prior CP1/CP2 failures tied to context-plus expectations were not valid V8.6 compliance evidence.

## What Changed After PR #426

Under V8.6:
- semantic discovery -> `llm-tldr` (canonical default)
- exact static analysis -> `llm-tldr`
- symbol-aware tasks -> `serena`
- `context-plus` -> optional/experimental only

OpenCode PR #411 was also updated to this V8.6 baseline (`acb69003bcc7c46255da25c4e075567a10b4adc4`).

## Merged Source Revisions Used

| Repo | Revision Used | Notes |
|------|---------------|-------|
| agent-skills | `origin/master` -> `ebbe77933a722eece3633870d945b8b32ae9c2ef` | Verified V8.6 routing text via `origin/master` (canonical checkout blocked by unrelated untracked files) |
| prime-radiant-ai | `e1320248370ac4db9e810e22096d9beef26c9bbb` | Required downstream baseline |

## Commands Run

```bash
# Mandatory fetch/read phase in canonical agent-skills
git fetch origin pull/411/head:pr-411
git fetch origin pull/413/head:pr-413
git fetch origin pull/426/head:pr-426
git checkout pr-413

# Trunk verification (checkout blocked by unrelated untracked canonical files)
git fetch origin
git rev-parse origin/master
git show origin/master:docs/specs/2026-03-27-mcp-tool-first-routing-and-cass-disposition.md

git show origin/master:extended/llm-tldr/SKILL.md

# prime baseline checkout
git -C ~/prime-radiant-ai fetch origin
git -C ~/prime-radiant-ai checkout e1320248370ac4db9e810e22096d9beef26c9bbb
git -C ~/prime-radiant-ai rev-parse HEAD

# worktrees
dx-worktree create bd-e5z8 agent-skills
dx-worktree create bd-e5z8 prime-radiant-ai

# preflight from prime-radiant-ai worktree
cd /tmp/agents/bd-e5z8/prime-radiant-ai
codex mcp list
git rev-parse HEAD
tldr warm .

# 6 isolated codex exec runs (one per case) with first-MCP-call evidence capture
codex exec --json "<case prompt>" | <first-mcp-parser>
```

## Preflight Validation

- `llm-tldr`: visible/enabled
- `serena`: visible/enabled
- `tldr warm .`: completed successfully in `/tmp/agents/bd-e5z8/prime-radiant-ai`
- Suite target HEAD: `e1320248370ac4db9e810e22096d9beef26c9bbb`

## Codex Rerun Results (V8.6)

| Case | Expected | First Tool Used | Verdict | Note | Vs OpenCode |
|------|----------|-----------------|---------|------|-------------|
| CP1 | llm-tldr | llm-tldr (`semantic`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |
| CP2 | llm-tldr | llm-tldr (`semantic`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |
| LT1 | llm-tldr | llm-tldr (`extract`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |
| LT2 | llm-tldr | llm-tldr (`status`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |
| SE1 | serena | serena (`activate_project`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |
| SE2 | serena | serena (`activate_project`) | PASS | first MCP tool matched expected server; first call completed cleanly | same |

## Comparison Against Updated OpenCode Baseline (PR #411)

- Updated baseline already shows 6/6 PASS under V8.6.
- Codex rerun matches that baseline on required first-tool server selection (6/6).
- No remaining context-plus-era semantic drift under the current contract.

## Metrics

- routing compliance: **6/6**
- runtime success: **6/6**
- `Tool routing exception` count: **0**

## PR #426 Impact Assessment

PR #426 materially fixed the prior Codex semantic-routing problem **for this lane** by changing the canonical semantic route to `llm-tldr`; rerun evidence is clean against the updated contract.

Residuals:
- No routing residuals in this rerun.
- No MCP runtime residuals in scored case evidence.
- Post-suite, additional ad hoc `codex exec` attempts hit a **client usage-limit** error; this is a client limitation outside repo control and did not affect the completed 6-case evidence above.

## Recommendation

**no further fix round needed**

Rationale: Codex is clean (6/6 PASS, 0 exceptions) against the active V8.6 MCP Tool-First Routing Contract and aligns with the updated OpenCode baseline.
