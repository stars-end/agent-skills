---
name: serena
description: Serena MCP integration reference for Fleet Sync, including current blocker state and validation contract.
---

# Serena (Fleet Sync V2.1)

Use this skill when evaluating, restoring, or validating Serena in the Fleet Sync tool stack.

## Current Fleet Status
- Fleet contract: intended MCP-rendered tool
- Current state: BLOCKED
- Blocker: PyPI package `serena==0.9.1` provides no executable entrypoint. Installation with `uv tool install` fails with reason_code: `serena_no_entrypoint`

## Upstream Docs
- GitHub: `https://github.com/oraios/serena`
- Repository docs: `https://github.com/oraios/serena#readme`

## Expected Contract
- Install source must avoid the unrelated PyPI collision.
- Health check must prove a real executable entrypoint, not just package resolution.
- Tool is only considered restored when:
  - install succeeds on all canonical hosts
  - health command succeeds on all canonical hosts
  - supported client CLIs can see the MCP server after config converge

## Validation Notes
- Prefer explicit executable proof, for example:
  - `serena start-mcp-server --help`
- Treat missing entrypoints or failed client connections as hard blockers.
- Do not mark Fleet Sync full-GO while Serena remains unresolved unless the platform contract explicitly excludes it.

## Resolution
- Blocked until upstream provides a working executable entrypoint
- Alternative tools may need to be evaluated
- Current workaround: disable in manifest with clear rationale
