---
name: context-plus
description: Local-first structural context analysis workflow for codebase mapping and dependency-aware targeting.
---

# Context+ (Fleet Sync V2.1)

Use this skill when agents need higher-fidelity codebase mapping before edits.

## Status
- Fleet contract: MCP-rendered tool
- Expected package: `contextplus`
- Expected runtime: Node.js
- Canonical health checks:
  - `contextplus --version`
  - client MCP visibility checks such as `claude mcp list`, `codex mcp list`, `gemini mcp list`, `opencode mcp list`

## Upstream Docs
- GitHub: `https://github.com/ForLoopCodes/contextplus`
- npm package: `https://www.npmjs.com/package/contextplus`

## Contract
- Execute locally (stdio MCP), never as a mandatory central gateway dependency.
- Prefer repository-local indexes and embeddings.
- Fail open to normal local navigation if Context+ is unavailable.
## Canonical Fleet Notes
- Historical manifest entries using `@forloopcodes/contextplus` are stale.
- The Fleet Sync source of truth must point at the real package name and version `1.0.7`
- This tool should only be considered restored when:
  - runtime health passes on all canonical hosts
  - MCP entries render correctly into supported client configs
  - Layer 4 client visibility tests show the tool from the relevant CLIs
## Expected Output
- Ranked target files/modules
- Dependency or cluster hints for safer edits
