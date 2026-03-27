# Post-Merge Tool Routing Validation

**Date**: 2026-03-27
**Subtask**: bd-dqhl
**Epic**: bd-8ws5
**Dependencies**: bd-2qhi
**Mode**: qa_pass

## Merged Inputs Checked

- agent-skills merge commit: `a0b6306202aef20979dfaeec10f036b600a9fca7` (PR #406)
- prime-radiant-ai merge commit: `e1320248370ac4db9e810e22096d9beef26c9bbb` (PR #1027)

### agent-skills PR #406 Scope

```
git diff a0b63062^..a0b63062 --stat
 docs/specs/2026-03-27-mcp-tool-first-routing-and-cass-disposition.md | 358 +++++
 1 file changed, 358 insertions(+)
```

PR #406 added the spec document only. Zero implementation changes were merged.

### prime-radiant-ai PR #1027 Scope

PR #1027 merged the repo-addendum with V2 contract + tool-first routing overlay. This part is correct.

## Commands Run

```bash
# Agent-skills sweep
rg -n "MCP Tool-First Routing Contract|Tool routing exception|cass-memory|context-plus|llm-tldr|serena" \
  AGENTS.md dist/universal-baseline.md dist/dx-global-constraints.md \
  configs/mcp-tools.yaml extended/context-plus/SKILL.md extended/llm-tldr/SKILL.md \
  extended/serena/SKILL.md extended/cass-memory/SKILL.md \
  infra/fleet-sync/resources/tool-contracts.md core/tech-lead-handoff/SKILL.md \
  extended/prompt-writing/SKILL.md

# Prime-radiant-ai sweep
rg -n "V2 Product Contract|Tool-First Routing|Tool routing exception|verify-v2-contract|FOUNDER_SIGNOFF_FLOW|FAKE_METRIC_GUARDRAILS" \
  AGENTS.md fragments/repo-addendum.md

# Runtime checks
codex mcp list
opencode mcp list
rg -n "context-plus|llm-tldr|serena|cass" ~/.codex/config.toml ~/.config/opencode/opencode.jsonc

# Specific assertions
rg -n "MCP Tool-First Routing Contract" scripts/publish-baseline.zsh dist/universal-baseline.md dist/dx-global-constraints.md AGENTS.md
rg -n "Required Trigger Contract" extended/context-plus/SKILL.md extended/llm-tldr/SKILL.md extended/serena/SKILL.md
rg -n "pilot|NOT CANONICAL|disabled by default" extended/cass-memory/SKILL.md
rg -n "Tool Evidence" core/tech-lead-handoff/SKILL.md
rg -n "MCP routing" extended/prompt-writing/SKILL.md
```

## Pass/Fail by Assertion

### A1: publish-baseline.zsh contains MCP Tool-First Routing Contract
**FAIL** - `rg` returns "NOT FOUND". The `## 5.4) MCP Tool-First Routing Contract (V8.5)` section is absent from the constraints heredoc. No routing matrix, no fallback clause, no "Tool routing exception" language exists between sections 5.3 and 6.

### A2: Generated baseline artifacts include routing contract
**FAIL** - All three artifacts (`AGENTS.md`, `dist/universal-baseline.md`, `dist/dx-global-constraints.md`) lack the routing contract. This is a cascading failure from A1.

### A3: configs/mcp-tools.yaml shows correct tool states
**FAIL** - Three issues:
1. `cass-memory: enabled: true` at line 43 (spec requires `enabled: false`)
2. `llm-tldr` upstream: `https://github.com/simonw/llm-tldr` at line 35 (spec requires `parcadei/llm-tldr`)
3. cass-memory comment at line 39: "CLI-native episodic memory (CLI mode)" (spec requires "pilot-only CLI episodic memory (disabled by default)")

### A4: Skills contain Required Trigger Contract sections
**FAIL** - None of `context-plus`, `llm-tldr`, or `serena` SKILL.md files contain a "Required Trigger Contract" section.

### A5: cass-memory demoted from canonical default
**FAIL** - cass-memory/SKILL.md still reads:
- Title: "CASS Memory (Fleet Sync V2.2)" (not "Pilot Only")
- Description: "CLI-native procedural/episodic memory workflow with opt-in sanitized cross-agent digest sharing" (not pilot-only language)
- No "## Status" section with NOT CANONICAL language

### A6: prime-radiant-ai AGENTS.md has V2 Product Contract + Tool-First Routing
**PASS** - `fragments/repo-addendum.md` contains both sections (lines 32-132). `AGENTS.md` correctly inherits them via `agents-md-compile.zsh`.
- "V2 Product Contract" found at `AGENTS.md:411`, `fragments/repo-addendum.md:32`
- "Tool-First Routing" found at `AGENTS.md:504`, `fragments/repo-addendum.md:125`
- "verify-v2-contract" found at `AGENTS.md:431,456,481`
- "FOUNDER_SIGNOFF_FLOW" found at `AGENTS.md:421,462,482`
- "FAKE_METRIC_GUARDRAILS" found at `AGENTS.md:422,487`

### A7: agents-md-compile.zsh consistent with fragment-source model
**PASS** - Script correctly layers universal-baseline.md + repo-addendum.md.

### A8: Runtime MCP listings show no cass confusion
**PASS** - `codex mcp list` shows: context-plus, llm-tldr, serena (3 tools, no cass-memory). `opencode mcp list` shows same 3 tools. `~/.codex/config.toml` has context-plus, llm-tldr, serena (no cass). `~/.config/opencode/opencode.jsonc` same. `~/.claude.json` has no cass entry.

### Additional: tool-contracts.md missing Layer 5 section
**FAIL** - `infra/fleet-sync/resources/tool-contracts.md` still reads "Full platform GO achieved for verified Layer 4 visibility" at line 39 with no Layer 5 Agent Adoption section.

### Additional: tech-lead-handoff missing Tool Evidence
**FAIL** - `core/tech-lead-handoff/SKILL.md` has no "Tool Evidence" artifact in the shared required artifacts list.

### Additional: prompt-writing missing MCP routing contract
**FAIL** - `extended/prompt-writing/SKILL.md` description still reads "...Beads traceability (epic/subtask/dependencies), and required PR artifacts" without "MCP routing expectations".

## Residual Findings

| # | Severity | Surface | Evidence |
|---|----------|---------|----------|
| R1 | **BLOCKING** | `scripts/publish-baseline.zsh` | Missing `## 5.4) MCP Tool-First Routing Contract (V8.5)` section entirely |
| R2 | **BLOCKING** | `configs/mcp-tools.yaml:43` | `cass-memory: enabled: true` instead of `false` |
| R3 | **BLOCKING** | `configs/mcp-tools.yaml:35-36` | Wrong llm-tldr upstream (`simonw` not `parcadei`) |
| R4 | **BLOCKING** | `extended/context-plus/SKILL.md` | Stale `npx` install, no trigger contract |
| R5 | **BLOCKING** | `extended/llm-tldr/SKILL.md:116-117` | Wrong upstream repo, no trigger contract |
| R6 | **BLOCKING** | `extended/serena/SKILL.md` | No trigger contract |
| R7 | **BLOCKING** | `extended/cass-memory/SKILL.md` | Not demoted; still uses canonical-stack language |
| R8 | **BLOCKING** | `infra/fleet-sync/resources/tool-contracts.md:39` | Missing Layer 5 Agent Adoption section |
| R9 | **BLOCKING** | `core/tech-lead-handoff/SKILL.md` | Missing Tool Evidence artifact |
| R10 | **BLOCKING** | `extended/prompt-writing/SKILL.md` | Missing MCP routing expectation in description and delivery contract |
| R11 | NON-BLOCKING | `prime-radiant-ai/fragments/universal-baseline.md:3` | Stale (SHA `5bbf654d` from 2026-02-26); expected to be updated by baseline-sync workflow after upstream implementation lands |
| R12 | PASS | Host runtime (codex, opencode) | cass-memory absent from all IDE MCP listings |
| R13 | PASS | `prime-radiant-ai/fragments/repo-addendum.md` | V2 contract + tool-first routing correctly present |

## Root Cause

PR #406 (`a0b63062`) merged only the spec document (`docs/specs/2026-03-27-mcp-tool-first-routing-and-cass-disposition.md`). The implementation changes described in that spec (changes 1-9 covering `publish-baseline.zsh`, `mcp-tools.yaml`, four SKILL.md files, `tool-contracts.md`, `tech-lead-handoff/SKILL.md`, and `prompt-writing/SKILL.md`) were never applied to `agent-skills` trunk.

The prime-radiant-ai downstream PR #1027 (`e1320248`) correctly merged the repo-addendum overlay, but that overlay sits on top of a stale universal-baseline that lacks the routing contract.

## Verdict

**bd-dqhl CANNOT CLOSE.** The upstream implementation (bd-2qhi) was not actually merged. All 10 blocking findings trace back to missing implementation changes in agent-skills. The spec exists but no code changes were applied to the files the spec targets.

### Required Next Steps

1. Implement the 10 file changes described in `docs/specs/2026-03-27-mcp-tool-first-routing-and-cass-disposition.md` sections "### 1" through "### 9" against agent-skills trunk.
2. Run `make publish-baseline` to regenerate artifacts.
3. Re-run this validation (bd-dqhl) against the new implementation merge commit.
4. Sync updated `dist/universal-baseline.md` to `prime-radiant-ai/fragments/universal-baseline.md`.
