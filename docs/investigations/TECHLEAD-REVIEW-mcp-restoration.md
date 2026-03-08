# Tech Lead Review: MCP Tool Restoration Research (bd-d8f4)

## Overview
This investigation identifies the root causes of current Fleet Sync MCP tool failures and provides a corrected manifest and rollout plan.

## Key Findings
1.  **llm-tldr**: Fully operational.
2.  **context-plus**: Broken due to incorrect package name (`@forloopcodes/contextplus` -> `contextplus`) and stale version.
3.  **cass-memory**: Broken due to incorrect package name, invalid version (`1.0.0`), and missing `bun` runtime on some hosts. Recommended fix: switch to `npm` and GitHub source.
4.  **serena**: Broken due to PyPI name collision with an AMQP client. Recommended fix: install directly from GitHub.

## Artifacts
- [mcp-tool-restoration-research.md](../runbook/fleet-sync/mcp-tool-restoration-research.md)
- [mcp-ide-surface-matrix.md](../runbook/fleet-sync/mcp-ide-surface-matrix.md)
- [mcp-tool-rollout-plan.md](../runbook/fleet-sync/mcp-tool-rollout-plan.md)

## Manifest Correction
Updated `configs/mcp-tools.yaml` with correct package names, versions, and installation commands. Tools are kept `enabled: false` pending review.

## Recommendation
Approve research findings and transition to an implementation agent for Phase 2 (Rollout).