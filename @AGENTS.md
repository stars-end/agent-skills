# Deprecated Agent Instructions

This file is a legacy compatibility shim. Do not use it as an active workflow contract.

Use the generated root `AGENTS.md` and the canonical skills in this repository instead.

Current coordination summary:
- Use `bdx` for Beads coordination.
- Use worktrees under `/tmp/agents/<beads-id>/<repo>` for development.
- Use `dx-loop` as the default agent-facing orchestrator for chained Beads work, multi-step outcomes, implement/review baton flow, PR-aware follow-up, and "keep going until reviewed or blocked."
- Use `dx-runner` as the lower-level provider runner.
- Treat `dx-batch` as legacy/compatibility/internal substrate, not the default agent workflow surface.
