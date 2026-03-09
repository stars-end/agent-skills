# Fleet Sync Live Docs Map

Use primary sources whenever possible. Internal runbooks are supporting context, not substitutes for upstream docs.

## Upstream Tool Docs

- `cass-memory`
  - GitHub: `https://github.com/Dicklesworthstone/cass_memory_system`
  - Install/use/MCP docs: `https://github.com/Dicklesworthstone/cass_memory_system#readme`
- `context-plus`
  - GitHub: `https://github.com/ForLoopCodes/contextplus`
  - npm: `https://www.npmjs.com/package/contextplus`
- `llm-tldr`
  - PyPI: `https://pypi.org/project/llm-tldr/`
- `serena`
  - GitHub: `https://github.com/oraios/serena`

## Internal Source of Truth

- Canonical targets: `scripts/canonical-targets.sh`
- Tool manifest: `configs/mcp-tools.yaml`
- Local converge/check: `scripts/dx-mcp-tools-sync.sh`
- Fleet aggregation: `scripts/dx-fleet-check.sh`
- Fleet wrapper: `scripts/dx-fleet.sh`

## Internal Supporting Docs

- `docs/runbook/fleet-sync/mcp-tool-restoration-research.md`
- `docs/runbook/fleet-sync/mcp-tool-rollout-plan.md`
- `docs/runbook/fleet-sync/mcp-ide-surface-matrix.md`

## Usage Rule

- Prefer upstream docs for install/runtime semantics.
- Prefer repo scripts and current CLI behavior for what Fleet Sync actually does.
- If upstream docs and local runtime disagree, document the discrepancy and trust current runtime for status reporting.
