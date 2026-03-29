---
name: fleet-sync
description: |
  Canonical Fleet Sync skill for cross-VM tool convergence, client visibility testing, and runtime-truth documentation.
  Use when the work involves Fleet Sync architecture, canonical VM rollout, MCP tool restoration, or end-to-end validation across codex, claude, gemini, and opencode.
tags: [fleet, mcp, vm, ide, rollout, validation]
allowed-tools:
  - Read
  - Bash(rg:*)
  - Bash(sed:*)
  - Bash(ssh:*)
  - Bash(git:*)
---

# Fleet Sync

Canonical orchestrator for Fleet Sync work across:
- canonical VMs
- canonical IDE/client surfaces
- tool runtime health
- MCP config convergence
- fleet-wide daily and weekly validation

## Read First
- `resources/tool-contracts.md`
- `resources/validation-matrix.md`
- `resources/live-docs.md`
- `../../docs/runbook/fleet-sync/client-mcp-contract.md`

## Goal

Keep Fleet Sync honest and executable:
- CLI-native tools are not forced into IDE MCP drift gates
- MCP-rendered tools are converged and visible from actual client CLIs
- docs reflect runtime truth, not aspirations

## Core Architecture

- Canonical hosts and IDEs come from `scripts/canonical-targets.sh`
- Tool manifest comes from `configs/mcp-tools.yaml`
- Local convergence comes from `scripts/dx-mcp-tools-sync.sh`
- Fleet aggregation comes from `scripts/dx-fleet-check.sh` and `scripts/dx-fleet.sh`

### Tool Classes
- `cli`: host-level tool, verified by runtime health, not required in IDE MCP configs
- `mcp`: rendered into supported client config surfaces and verified by both file-level convergence and client-visible CLI checks

### Current Tool Roster (V2.2)

| Tool | Class | Status | Notes |
|------|-------|--------|-------|
| `cass-memory` | `cli` | Enabled | CLI-native, not rendered to IDE configs |
| `llm-tldr` | `mcp` | Enabled | Static analysis context slicing |
| `context-plus` | `mcp` | Enabled | Structural context analysis |
| `serena` | `mcp` | Enabled | AI assistant memory |

## When To Use

Use this skill when the user asks to:
- complete Fleet Sync
- restore MCP tools fleet-wide
- verify canonical VM x canonical agent IDE coverage
- investigate why an IDE/client cannot see an MCP server
- update Fleet Sync docs or evidence

## Working Rules

- Prefer runtime truth over historical evidence bundles.
- Always distinguish:
  - host runtime health
  - rendered config correctness
  - client-visible MCP availability
- For `context-plus`, keep a split presentation model. Codex gets one
  visible workspace-local alias named `context-plus` to reduce MCP-list
  ambiguity. Other IDEs keep repo-scoped MCP entries (e.g.,
  `context-plus-agent-skills`, `context-plus-prime-radiant-ai`) launched with
  explicit repo-path arguments per the upstream README contract.
- `antigravity` and `gemini-cli` use wrapped launcher form with the repo
  path inside the exec string.
- `CONTEXTPLUS_ROOT` env var: escape-hatch only, not the primary contract.
- Do not claim full GO while `serena` remains unresolved unless the contract explicitly excludes it.

## Validation Order

1. Host runtime checks
2. Local config convergence checks
3. Fleet daily/weekly audits
4. Layer 4 client visibility tests:
   - `codex mcp list`
   - `claude mcp list`
   - `gemini mcp list`
   - `opencode mcp list`

## Related Skills

- `canonical-targets` for canonical host and IDE registry
- `fleet-deploy` for rollout mechanics
- `mcp-doctor` for warning-style diagnostics
- `cass-memory`
- `context-plus`
- `llm-tldr`
- `serena`
