# Post-Merge Tool Routing Validation

**Date**: 2026-03-27
**Subtask**: bd-dqhl
**Epic**: bd-8ws5
**Dependencies**: bd-2qhi
**Mode**: qa_pass

## Merged Inputs Checked

- agent-skills merge commit: `db970b87dc99ec932336f57381b9aefee32d2710` (PR #410)
- agent-skills PR head: `a7e9169dae27a7004ef3753f8313ae240afa946c`
- prime-radiant-ai merge commit: `e1320248370ac4db9e810e22096d9beef26c9bbb` (PR #1027)
- prime-radiant-ai PR head: `3030de6e04bab1035df0dd04c01f3fc579051443`

I inspected the merged inputs directly before creating the validation worktree. The merged upstream files are the source truth for this rerun, but the existing validation branch/worktree (`feature-bd-dqhl`, HEAD `0b17003c1af92658eac0425276dba012fb634cec`) is still stale relative to those merges.

### agent-skills PR #410 Scope

The merged implementation is supposed to add the MCP tool-first routing contract, demote `cass-memory`, and propagate the contract into generated baselines plus tool docs.

### prime-radiant-ai PR #1027 Scope

The repo addendum merge is in place and already contains both the V2 contract overlay and the repo-specific tool-first routing section.

## Commands Run

```bash
# agent-skills verification sweep
make publish-baseline
rg -n "MCP Tool-First Routing Contract|Tool routing exception|cass-memory|context-plus|llm-tldr|serena|Layer 5|Tool Evidence" \
  AGENTS.md dist/universal-baseline.md dist/dx-global-constraints.md \
  configs/mcp-tools.yaml extended/context-plus/SKILL.md extended/llm-tldr/SKILL.md \
  extended/serena/SKILL.md extended/cass-memory/SKILL.md \
  infra/fleet-sync/resources/tool-contracts.md core/tech-lead-handoff/SKILL.md \
  extended/prompt-writing/SKILL.md

# prime-radiant-ai verification sweep
make regenerate-agents-md
rg -n "V2 Product Contract|Tool-First Routing|Tool routing exception|verify-v2-contract|FOUNDER_SIGNOFF_FLOW|FAKE_METRIC_GUARDRAILS" \
  AGENTS.md fragments/repo-addendum.md

# runtime checks
codex mcp list || true
opencode mcp list || true
rg -n "context-plus|llm-tldr|serena|cass" ~/.codex/config.toml ~/.config/opencode/opencode.jsonc 2>/dev/null || true
~/agent-skills/scripts/dx-verify-clean.sh
```

## Pass/Fail by Assertion

### A1: `scripts/publish-baseline.zsh` contains MCP Tool-First Routing Contract
**FAIL** - `rg -n "MCP Tool-First Routing Contract|Tool routing exception" scripts/publish-baseline.zsh dist/universal-baseline.md dist/dx-global-constraints.md AGENTS.md` returned no matches. The generated baseline path still does not contain the routing contract text.

### A2: Generated `agent-skills` baseline artifacts include the routing contract and `Tool routing exception`
**FAIL** - `make publish-baseline` updated `AGENTS.md` and `dist/universal-baseline.md`, but the rerun still produced no `MCP Tool-First Routing Contract` section and no `Tool routing exception` string in the generated artifacts.

### A3: `configs/mcp-tools.yaml` shows `context-plus`, `llm-tldr`, `serena` as MCP and `cass-memory` disabled
**FAIL** - Current branch/worktree output still shows the pre-merge values:
- `configs/mcp-tools.yaml:19` `llm-tldr.enabled: true`
- `configs/mcp-tools.yaml:35-36` upstream/docs still point at `https://github.com/simonw/llm-tldr`
- `configs/mcp-tools.yaml:43` `cass-memory.enabled: true`
- `configs/mcp-tools.yaml:71` `context-plus.enabled: true`
- `configs/mcp-tools.yaml:120` `serena.enabled: true`
This is the clearest sign that the validation branch has not been refreshed to the merged agent-skills state.

### A4: `context-plus`, `llm-tldr`, and `serena` skills each contain explicit routing/trigger guidance
**FAIL** - The current validation branch still lacks the `Required Trigger Contract` sections in those skill docs. The targeted `rg` for `Required Trigger Contract` returned no matches across the three files.

### A5: `cass-memory` is no longer described as part of the canonical default assistant loop
**FAIL** - The current validation branch still presents `cass-memory` as a canonical CLI tool rather than a pilot-only/non-default surface.

### A6: `prime-radiant-ai` generated `AGENTS.md` contains both the V2 Product Contract and Tool-First Routing sections
**PASS** - `AGENTS.md` contains:
- `AGENTS.md:411` `## V2 Product Contract — Gated Shipping (bd-yj6k)`
- `AGENTS.md:504` `### Tool-First Routing (Repo-Specific)`
The same sections are present in `fragments/repo-addendum.md` at lines `32` and `125`.

### A7: `scripts/agents-md-compile.zsh` remains consistent with the fragment-source model
**PASS** - The script still generates `AGENTS.md` from `fragments/universal-baseline.md` plus `fragments/repo-addendum.md`; no alternate source path was introduced.

### A8: Live runtime checks do not show stale `cass` / `cm` confusion in IDE MCP listings
**PASS** - `codex mcp list` shows only `context-plus`, `llm-tldr`, `serena`, and `playwright`. The runtime config grep also shows only `context-plus`, `llm-tldr`, and `serena` in the IDE configs. No `cass-memory` entry appears in the MCP listings.

## Residual Findings

| # | Severity | Surface | Evidence |
|---|----------|---------|----------|
| R1 | **BLOCKING** | `agent-skills` generated baseline path | `make publish-baseline` on the validation branch still does not emit `MCP Tool-First Routing Contract` or `Tool routing exception` into `AGENTS.md` / `dist/universal-baseline.md` |
| R2 | **BLOCKING** | `configs/mcp-tools.yaml` | The validation branch still reports `cass-memory.enabled: true` and the old `llm-tldr` upstream/docs, so the branch is not yet aligned to the merged tool manifest |
| R3 | **BLOCKING** | `extended/context-plus/SKILL.md`, `extended/llm-tldr/SKILL.md`, `extended/serena/SKILL.md`, `extended/cass-memory/SKILL.md` | The validation branch still lacks the explicit trigger contracts and pilot-only demotion that the merged implementation is supposed to provide |

## Verdict

**bd-dqhl CANNOT CLOSE.** The merged upstream/downstream inputs exist, but the existing validation branch is still stale on the agent-skills side, so the generated baseline and tool-routing assertions do not yet certify the contract end-to-end.

### Required Next Step

Refresh the validation branch from the merged agent-skills implementation, regenerate the baseline, and rerun this memo’s assertions. Only then can `bd-dqhl` close.
