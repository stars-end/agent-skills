---
name: mcp-doctor
description: |
  Warn-only health check for canonical MCP configuration and related DX tooling.
  Strict mode is opt-in via MCP_DOCTOR_STRICT=1.
tags: [dx, mcp, health, verification]
allowed-tools:
  - Bash(health/mcp-doctor/check.sh:*)
---

# mcp-doctor

Runs a fast, safe verification of canonical MCP + DX expectations.

## Usage

```bash
~/agent-skills/health/mcp-doctor/check.sh
MCP_DOCTOR_STRICT=1 ~/agent-skills/health/mcp-doctor/check.sh
```

## Design

- Warn-only by default (never blocks automation unless strict mode is enabled).
- Never prints secrets.
- Checks canonical IDE config locations (see `docs/CANONICAL_TARGETS.md`).
- Operates as the living operational MCP skill backed by the researched client contract.
- Authoritative reference: `docs/runbook/fleet-sync/client-mcp-contract.md`
- Merge gate matrix: `docs/runbook/fleet-sync/merge-acceptance-matrix.md`

## Client Contracts

The doctor distinguishes between host runtime health, config/render health, and client-visible MCP activation.

Current verified per-client sources of truth:
- **Claude Code**: `~/.claude.json` (uses `mcpServers` object)
- **Gemini CLI**: `~/.gemini/settings.json` (uses `mcpServers` object)
- **Codex CLI**: `~/.codex/config.toml` (uses `[mcp_servers]` table, required on `macmini`, optional on Linux hosts)
- **OpenCode**: `~/.config/opencode/opencode.jsonc` (uses `mcp` object)
- **Antigravity**: Inherits from `~/.gemini/settings.json` (uses `mcpServers` object)

## Status Semantics
- `VERIFIED`: Proven via client CLI output.
- `INFERRED`: Verified by config presence but lacks a native client list command (e.g. `antigravity`).
- `BLOCKED`: Client currently ignores known config paths or formats.
