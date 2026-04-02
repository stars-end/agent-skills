# bd-7su9 — Codex llm-tldr MCP Launcher Stabilization

## Summary
Replace the shell-based `llm-tldr` MCP launch command with a direct launcher that executes the contained Python MCP server under the same interpreter as the installed `llm-tldr` tool. Keep the contained runtime layer, prove Codex no longer hits the `rmcp EOF while parsing a value` failure in normal-home `codex exec`, and preserve OpenCode compatibility.

## Problem
The canonical MCP manifest currently launches `llm-tldr` through `bash -lc "exec ~/agent-skills/scripts/tldr-mcp-contained.sh"`.

Observed state on April 1, 2026:
- manual MCP handshake succeeds (`initialize`, `initialized`, `tools/list`)
- OpenCode works with the contained server path
- normal-home `codex exec` still fails with `rmcp ... EOF while parsing a value at line 1 column 0`
- the same contained server works in Codex when launched via a tiny direct Python launcher instead of the shell wrapper

This makes the problem a launch-path compatibility bug, not an upstream `llm-tldr` protocol bug.

## Goals
1. Keep repo-safe containment and semantic auto-bootstrap intact.
2. Remove the Codex-sensitive shell hop from the MCP launch path.
3. Keep OpenCode working with the same rendered MCP command.
4. Make the fleet contract truthful about the launcher actually used.
5. Prove the fix with real Codex and OpenCode smokes against `~/affordabot`.

## Non-Goals
- changing upstream `~/llm-tldr`
- removing the contained runtime layer
- centralizing `llm-tldr` on `epyc12`
- redesigning semantic/index behavior beyond preserving current contained semantics

## Active Contract
- `llm-tldr` remains a local stdio MCP server on each host/client.
- The contained runtime layer remains required for:
  - externalized `.tldr` / `.tldrignore` state
  - semantic auto-bootstrap
- IDE/client configs should launch a direct executable, not `bash -lc ...`.
- Completion requires a successful normal-home Codex smoke and OpenCode smoke in `~/affordabot`.

## Architecture / Design
### Existing stable logic
- `scripts/tldr-mcp-contained.py` remains the contained MCP server entrypoint.
- `scripts/tldr_contained_runtime.py` remains the containment + semantic bootstrap layer.

### New launcher
Add `scripts/tldr-mcp-contained-launch.py`:
- resolve `llm-tldr` on PATH
- read its shebang to identify the correct Python interpreter for the installed tool
- `execv()` that interpreter with `scripts/tldr-mcp-contained.py`
- pass through argv unchanged

Why this shape:
- avoids `bash -lc` stdio/process semantics that are failing under Codex
- keeps the contained MCP implementation unchanged
- avoids maintaining a fork of upstream `llm-tldr`

### Config and docs updates
Update:
- `configs/mcp-tools.yaml`
- `extended/llm-tldr/SKILL.md`
- `infra/fleet-sync/SKILL.md`
- `infra/fleet-sync/resources/tool-contracts.md`

These surfaces must describe the new direct launcher path, not the old shell wrapper.

## Execution Phases
### Phase 1: Implement launcher swap
- add direct launcher script
- change manifest/docs to reference it

### Phase 2: Validate launcher behavior
- direct Codex smoke in `~/affordabot`
- direct OpenCode smoke in `~/affordabot`
- ensure `llm-tldr` is first-tool usable again in both lanes

### Phase 3: Review and ship
- review diff for accidental behavior change
- run `make publish-baseline` if required by touched surfaces
- run `~/agent-skills/scripts/dx-verify-clean.sh`
- open draft PR with findings-first summary

## Beads Structure
- Epic/Bug: `bd-7su9`
- Implementation task: `bd-7su9.1`
- Verification task: `bd-7su9.2`
- Blocking edge: `bd-7su9.2` blocked by `bd-7su9.1`

## Validation
### Required local checks
1. Config/render truth
- confirm manifest references `tldr-mcp-contained-launch.py`

2. Codex smoke
- normal-home `codex exec` in `~/affordabot`
- prompt must force `llm-tldr` first
- no `rmcp EOF while parsing a value`
- successful `llm-tldr` tool call visible in output

3. OpenCode smoke
- normal-home `opencode run` in `~/affordabot`
- prompt must force `llm-tldr` first
- successful `llm-tldr` tool call visible in logs/output

4. Repo cleanliness
- `~/agent-skills/scripts/dx-verify-clean.sh`

5. Optional baseline refresh
- if generated surfaces drift, run `make publish-baseline`

## Risks / Rollback
### Risk
- launcher resolves the wrong interpreter if `llm-tldr` is absent or installed unusually

### Mitigation
- fail loudly with a precise error if `llm-tldr` is not on PATH or the shebang cannot be parsed
- keep implementation small and isolated to launch path

### Rollback
- revert manifest/docs to `tldr-mcp-contained.sh`
- remove the launcher script

## Recommended First Task
Start with `bd-7su9.1`.

Why first:
- verification is only meaningful once the direct launcher exists and the manifest/docs reflect the intended launch path.
