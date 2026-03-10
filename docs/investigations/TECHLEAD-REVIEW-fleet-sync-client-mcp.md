# Tech Lead Review: Fleet Sync Client MCP Integration

- MODE: investigation
- PR_URL: https://github.com/stars-end/agent-skills/pull/338
- PR_HEAD_SHA: ee7106569ee3ac4332eb53a7524ed6a7a14deffd
- BEADS_EPIC: bd-d8f4
- BEADS_SUBTASK: bd-d8f4
- BEADS_DEPENDENCIES: none
- Investigation Doc: docs/investigations/2026-03-10-fleet-sync-client-mcp-analysis.md

### Validation
- dx-fleet check --mode weekly: PASS (verified config presence across all hosts)
- claude mcp list: PASS (verified connected via `~/.claude.json`)
- gemini mcp list: PASS (verified connected via `~/.gemini/settings.json`)
- codex mcp list: PASS (verified connected via `~/.codex/config.toml`)
- opencode mcp list: PASS (verified connected via `~/.config/opencode/opencode.jsonc` using `mcp` key)

### Decisions Needed
1. **Gemini Configuration Path**: Approve `~/.gemini/settings.json` as the canonical path for Gemini CLI.
2. **OpenCode Configuration Key**: Approve `mcp` as the canonical key for OpenCode (fixing the previous assumption of `mcpServers`).

### How To Review
1. Open PR #338.
2. Inspect `docs/runbook/fleet-sync/client-mcp-contract.md` for accuracy.
3. Verify that `scripts/dx-mcp-tools-sync.sh` needs a follow-on PR to target the verified paths and keys.
