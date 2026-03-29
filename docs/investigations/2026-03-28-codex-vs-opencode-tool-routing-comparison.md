# Codex vs OpenCode MCP Tool-First Routing Comparison (Post-PR-419 Rerun)

**Date**: 2026-03-29  
**Runtime checked**: Codex CLI (`codex exec --json`)  
**Epic**: bd-rb0c  
**Subtask**: bd-e5z8  
**Mode**: qa_pass

## Why Pre-PR-419 Codex Result Was Stale/Incomplete

The prior blocker state was stale at client level: this VM now exposes repo-scoped MCP entries in `codex mcp list`:
- `context-plus-agent-skills`
- `context-plus-prime-radiant-ai`
- `context-plus-affordabot`
- `context-plus-llm-common`
- `llm-tldr`
- `serena`

So pre-PR-419 assumptions about missing repo-scoped entries are no longer valid for this client session.

## What Changed After PR #419

PR #419 merged the repo-scoped Context+ launcher contract on trunk (`origin/master` at `bf8d5836e804f9bc2fb19207ecaa4feea35e9bda`), including explicit path-arg MCP entries in:
- `configs/mcp-tools.yaml`
- `config-templates/fleet-sync-codex-cli.template.toml`

This rerun was executed after confirming that merged state.

## Preflight + Baselines

- `prime-radiant-ai` HEAD used: `e1320248370ac4db9e810e22096d9beef26c9bbb`
- OpenCode baseline memo read from PR #411
- Codex comparison branch updated on PR #413

## Rerun Results

| Case | Expected | First Tool Used | Verdict | Note | Vs OpenCode |
|------|----------|-----------------|---------|------|-------------|
| CP1 | context-plus-prime-radiant-ai | codex::list_mcp_resources | SOFT PASS | expected tool skipped; valid `Tool routing exception` returned in retry run | different failure mode |
| CP2 | context-plus-prime-radiant-ai | llm-tldr (`semantic`) | SOFT PASS | expected tool skipped; valid `Tool routing exception` returned in retry run | worse |
| LT1 | llm-tldr | llm-tldr (`extract`) | RUNTIME FAIL | first MCP call canceled in attempt 1 and retry attempt 2 (`user cancelled MCP tool call`) | worse |
| LT2 | llm-tldr | llm-tldr (`impact`) | RUNTIME FAIL | first MCP call canceled in attempt 1 and retry attempt 2 (`user cancelled MCP tool call`) | worse |
| SE1 | serena | serena (`activate_project`) | PASS | expected tool selected first and succeeded | same |
| SE2 | serena | serena (`activate_project`) | PASS | expected tool selected first and succeeded | same |

## Comparison Against OpenCode PR #411

- OpenCode CP2/LT1/LT2 were PASS; Codex rerun remains below that baseline.
- OpenCode CP1 was `context-plus`-first with runtime timeout; Codex CP1 remains skip-with-exception (different failure mode).
- Serena alignment remains stable (SE1/SE2 PASS in both lanes).

## Metrics

- routing compliance: **4/6**
- runtime success: **4/6**
- `Tool routing exception` count: **4**

## Did PR #419 Materially Fix Prior Codex Semantic-Routing Problem?

**Partially at configuration visibility level, not at execution behavior level in this lane.**

- Fixed: repo-scoped context-plus entries are now visible in preflight on this VM.
- Not fixed in this rerun: CP1/CP2 still did not select `context-plus-prime-radiant-ai` as first discovery tool.

Residual classification:
- CP1/CP2: **routing behavior / client limitation in `codex exec` lane**
- LT1/LT2: **runtime reliability (MCP cancellation noise)**

## Recommendation

**fix/re-test required**

Reason: post-PR-419 rerun still misses required first-tool selection for semantic cases and still shows repeat llm-tldr runtime cancellation after one clean retry.
