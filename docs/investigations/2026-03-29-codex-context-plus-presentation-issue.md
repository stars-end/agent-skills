# 2026-03-29 Codex Context-Plus Presentation Issue

## Summary

Post-PR-419, the repo-scoped `context-plus-*` MCP entries were present and healthy in Codex, but Codex still failed the semantic-routing cases in the conformance harness.

The remaining issue was presentation, not backend availability:
- Codex showed four near-identical `context-plus-*` servers in one flat MCP list
- the intended repo (`context-plus-prime-radiant-ai`) had no stronger affordance than unrelated repos
- semantic cases continued to soft-pass via exceptions instead of selecting the intended `context-plus` entry first

## Observed UI Problem

In Codex Desktop, the MCP window exposed:
- `context-plus-agent-skills`
- `context-plus-prime-radiant-ai`
- `context-plus-affordabot`
- `context-plus-llm-common`

This backend-correct presentation created a poor selection surface for Codex.

## Decision

Keep the repo-scoped backend contract for fleet correctness, but change Codex presentation:
- Codex should expose a single visible semantic alias: `context-plus`
- that alias should rely on the Codex workspace/session root rather than a flat list of repo-scoped siblings
- repo-scoped `context-plus-*` entries remain the primary truth for other IDEs

## Why This Is A Different Layer

PR #419 fixed:
- repo rooting correctness
- explicit path-arg launch contract
- V1 cache migration

It did not solve:
- Codex tool-selection ambiguity caused by a cluttered MCP server list

## Follow-Up Expectation

After the Codex-specific alias change is rendered and applied:
1. restart Codex Desktop
2. verify `codex mcp list` shows a single visible `context-plus` entry for Codex
3. rerun `bd-e5z8`
4. confirm whether semantic cases now select `context-plus` first without needing routing exceptions
