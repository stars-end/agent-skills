---
name: coordinator-dx
description: |
  Coordinator playbook for multi-repo, multi-VM parallel execution with dx-runner as canonical governance surface,
  OpenCode as primary execution lane, and cc-glm as reliability backstop. dx-dispatch is break-glass only.
---

# coordinator-dx (dx-runner Canonical)

Coordinator playbook for running multi‑repo, multi‑VM work in parallel without relying on humans copy/pasting long checklists.

**Canonical dispatch**: `dx-runner` (governed, unified governance layer)
- Primary lane: OpenCode via `dx-runner --provider opencode` 
- Backstop lane: cc-glm via `dx-runner --provider cc-glm` when policy/gates require fallback
- Break-glass: `dx-dispatch` (compatibility shim, deprecated - use only for legacy cross-VM fanout)

Key conventions:
- Each VM/agent sets `AGENT_NAME=<vm>-<tool>` (e.g. `macmini-codex`, `epyc6-claude-code`, `homedesktop-wsl-gemini`)
- For in-repo coordination, use the repo’s local Beads issue id as the coordination handle (no cross-repo renames).
- Always start a session with `dx-check` (baseline) and run `dx-doctor` when using coordinator services.

Recommended coordinator flow:
1. Assign work by repo (prime-radiant-ai / affordabot / llm-common / agent-skills).
2. Require agents to report:
   - `git status --porcelain`
   - `git branch --show-current`
   - output of `dx-check` (baseline)
   - output of `DX_BOOTSTRAP_COORDINATOR=1 dx-doctor` (only if using coordinator services)
3. Prevent collisions:
   - one repo per VM by default
   - prefer small PRs
4. Enforce “automation not checklists”:
   - if a step is repeated, codify it in `dx_doctor.sh` or shared skills.
