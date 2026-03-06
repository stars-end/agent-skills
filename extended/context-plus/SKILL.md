---
name: context-plus
description: Local-first structural context analysis workflow for codebase mapping and dependency-aware targeting.
---

# Context+ (Fleet Sync V2.1)

Use this skill when agents need higher-fidelity codebase mapping before edits.

## Contract
- Execute locally (stdio MCP), never as a mandatory central gateway dependency.
- Prefer repository-local indexes and embeddings.
- Fail open to normal local navigation if Context+ is unavailable.

## Inputs
- Local worktree path
- Active branch/repo scope

## Expected Output
- Ranked target files/modules
- Dependency or cluster hints for safer edits
