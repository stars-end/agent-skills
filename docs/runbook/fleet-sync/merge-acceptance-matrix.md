# Fleet Sync Merge Acceptance Matrix

This is the pre-merge gate for Fleet Sync MCP+CLI rollout.

## Scope

Managed MCP tools:
- `context-plus`
- `llm-tldr`
- `serena`

Managed CLI-only tools:
- `cass-memory` (`cm`) only; must not be required in MCP client lists.

## Layer Gate Requirements

1. Layer 1 host runtime:
- `cm --version`
- `tldr-mcp --version`
- `test -f ~/.local/share/contextplus-patched/build/index.js`
- `serena --help`

2. Layer 2 config convergence:
- `~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json --state-dir ~/.dx-state/fleet`
- `~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet`
- Required: `overall=green`, `tools_fail=0`, `files_fail=0`

3. Layer 3 fleet gates (MCP-scoped):
- `~/agent-skills/scripts/dx-fleet.sh check --mode daily --json --state-dir ~/.dx-state/fleet`
- `~/agent-skills/scripts/dx-fleet.sh check --mode weekly --json --state-dir ~/.dx-state/fleet`
- Required checks:
  - daily: `tool_mcp_health=pass` on all canonical hosts
  - weekly: `ide_config_presence_and_drift=pass` on all canonical hosts
- Note: non-MCP checks (for example Slack transport readiness) are important but do not block this MCP-specific merge gate.

## Layer 4 Client Visibility Matrix (Required Before Merge)

Legend:
- `PASS`: all three managed MCP tools visible
- `N/A`: client not required on that host
- `FAIL`: missing/incorrect visibility

| Host | Claude (`claude/cc-glm mcp list`) | Gemini (`gemini mcp list`) | OpenCode (`opencode mcp list`) | Codex (`codex mcp list`) |
|------|-----------------------------------|------------------------------|----------------------------------|---------------------------|
| `macmini` | `PASS` (connected) | `PASS` (connected) | `PASS` (connected) | `PASS` (listed+enabled) |
| `epyc6` | `PASS` (connected) | `PASS` (connected) | `PASS` (connected) | `N/A` (optional on Linux) |
| `epyc12` | `PASS` (connected) | `PASS` (connected) | `PASS` (connected) | `N/A` (optional on Linux) |
| `homedesktop-wsl` | `PASS` (connected) | `PASS` (connected) | `PASS` (connected) | `N/A` (optional on Linux) |

## Verification Command Set

Use this exact audit loop:

```bash
for h in macmini epyc6 epyc12 homedesktop-wsl; do
  if [ "$h" = "macmini" ]; then
    claude mcp list
    gemini mcp list
    opencode mcp list
    codex mcp list
  else
    ssh "$h" 'claude mcp list'
    ssh "$h" 'gemini mcp list'
    ssh "$h" 'opencode mcp list'
    ssh "$h" 'codex mcp list || true'
  fi
done
```

## Fail Conditions

Do not merge if any required cell fails:
- `No MCP servers configured` on Gemini or OpenCode
- missing `context-plus`, `llm-tldr`, or `serena` in required clients
- Codex on `macmini` missing any managed MCP tool or not `enabled`
- stale/manual-only state that is not preserved by Layer 2 converge

## Notes

- Antigravity is `INFERRED` through Gemini config/runtime and is not a separate Layer 4 list command.
- Extra non-Fleet-Sync MCP failures in client output (for unrelated servers) do not fail this matrix unless they mask managed server visibility.
