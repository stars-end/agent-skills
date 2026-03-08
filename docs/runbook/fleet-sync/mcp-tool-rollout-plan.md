# Fleet Sync MCP Tool Rollout Plan (bd-d8f4)

## Overview
This plan outlines the recommended order of restoration and validation for the Fleet Sync MCP tool stack across all canonical VMs.

## Phase 1: Correct Manifest
- **Target:** `configs/mcp-tools.yaml`
- **Changes:**
  1.  Update `context-plus` package name to `contextplus` and version to `1.0.7`.
  2.  Update `cass-memory` package to `git+https://github.com/Dicklesworthstone/cass_memory_system.git` and binary name to `cm`.
  3.  Update `serena` package to `git+https://github.com/oraios/serena.git`.
  4.  Change `cass-memory` runtime to `node` (using `npm install -g`) to bypass missing `bun` on `epyc6`.

## Phase 2: Host Restoration
- **Command:** `~/agent-skills/scripts/dx-fleet-repair.sh --apply --json`
- **Order:**
  1.  `macmini` (primary macOS)
  2.  `epyc6` (primary Linux)
  3.  `homedesktop-wsl` (WSL2)
  4.  `epyc12` (secondary Linux)

## Phase 3: Validation
- Run `~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json` on each host.
- Confirm `cm --version`, `contextplus --version`, `serena start-mcp-server --help`, and `llm-tldr --version` all pass.

## Rollback/Disable Strategy
- **Emergency Disable:** Set `enabled: false` in `configs/mcp-tools.yaml` and run `dx-fleet converge --apply`.
- **Uninstall:** Run `~/agent-skills/scripts/dx-mcp-tools-sync.sh --uninstall` (if implemented) or manually remove globally installed packages.