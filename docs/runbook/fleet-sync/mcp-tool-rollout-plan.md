# Fleet Sync MCP Tool Rollout Plan (bd-d8f4)

## Overview
This plan outlines the recommended order of restoration and validation for the Fleet Sync MCP tool stack across all canonical VMs.

## Phase 1: Correct Manifest
- **Target:** `configs/mcp-tools.yaml`
- **Changes:**
  1.  Update `context-plus` package name to `contextplus` and version to `1.0.7`. Maintain `mcp` contract.
  2.  Update `cass-memory` installation method to use its official bash script (bypassing the missing `bun` runtime on `epyc6`).
  3.  Update `serena` package to `git+https://github.com/oraios/serena.git` and set to `mcp`.

## Phase 2: Host Restoration
- **Primary Command:** `~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json`
- **Per-Host Execution:**
  1. `macmini` (primary macOS)
  2. `epyc6` (primary Linux)
  3. `homedesktop-wsl` (WSL2)
  4. `epyc12` (secondary Linux)
- **Note:** `dx-mcp-tools-sync.sh --apply` installs tools and patches IDE configs. For fleet-wide orchestration, see `dx-fleet-converge.sh`.

## Phase 3: Validation
- Run `~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json` on each host.
- Confirm `cm --version`, `contextplus --version`, `serena start-mcp-server --help`, and `tldr-mcp --version` all pass.
- Verify Layer 4 client visibility for each canonical IDE using the appropriate commands (`codex mcp list`, `claude mcp list`, `gemini mcp list`, `opencode mcp list`).

## Rollback/Disable Strategy
- **Emergency Disable:** Set `enabled: false` in `configs/mcp-tools.yaml` and run `dx-fleet converge --apply`.
- **Uninstall:** Run `~/agent-skills/scripts/dx-mcp-tools-sync.sh --uninstall` (if implemented) or manually remove globally installed packages.