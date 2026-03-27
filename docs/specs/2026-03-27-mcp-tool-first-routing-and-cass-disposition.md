# MCP Tool-First Routing and CASS Disposition

## Summary
- Convert the current MCP stack from "installed but optional" into an explicit routing contract.
- Make `context-plus`, `llm-tldr`, and `serena` the canonical first-choice surfaces for qualifying tasks.
- Remove `cass-memory` from the canonical default stack and preserve it only as a pilot/opt-in CLI surface.

## Problem
- Agents are not reliably using the enabled MCP tools because no instruction layer currently tells them when they must be preferred.
- The canonical docs still contain contradictory runtime truth:
  - `context-plus` skill docs still describe `npx contextplus` instead of the patched local build.
  - `llm-tldr` docs still point at the wrong upstream repo.
  - `tool-contracts.md` treats host visibility as "full platform GO" without measuring actual tool adoption.
  - `cass-memory` remains enabled in the manifest even though it is not part of the active MCP loop.

## Goals
- Define one canonical routing contract for semantic discovery, exact static analysis, and symbol-aware memory/editing.
- Make the routing contract inherit into generated AGENTS baselines.
- Add accountability so handoffs and delegated prompts show whether the correct tool was used.
- Demote `cass-memory` from canonical default without deleting the skill entirely.

## Non-Goals
- Add new MCP servers.
- Change IDE client transport formats beyond existing Fleet Sync rendering.
- Force `cass-memory` removal from every machine immediately.
- Redesign Beads, Serena memory layout, or repository-specific engineering workflows outside tool routing.

## Active Contract
- Canonical default assistant stack:
  - `context-plus`: semantic discovery and repo mapping
  - `llm-tldr`: exact static analysis and structural tracing
  - `serena`: symbol-aware edits and persistent assistant memory
- Canonical non-default memory surface:
  - `cass-memory`: pilot-only CLI tool; not part of the default assistant loop
- For qualifying tasks, agents must route the first discovery or context-gathering action through the matching MCP tool before broad shell search or repeated file traversal.
- Fallback to shell/file reads is allowed only when:
  - the MCP tool is unavailable in the current runtime
  - the MCP tool cannot answer after one reasonable attempt
  - the task is trivially faster with direct file access
- If the matching MCP tool is not used on a qualifying task, the agent must explicitly record:
  - `Tool routing exception: <reason>`

## Architecture / Design

### Routing Matrix
| Task shape | Required first tool | Reason |
|------------|---------------------|--------|
| "Where does this feature live?", "what code is related to X?", repo mapping before edits | `context-plus` | semantic discovery |
| call paths, impact analysis, slice/CFG/DFG/dead code, exact trace before edits | `llm-tldr` | precise structural analysis |
| symbol-aware edits, rename/refactor, insert-before/after, project memory, session continuity | `serena` | persistent context + structured edits |

### Enforcement Layers
1. Global generated baseline: establishes the default routing rule for all repos that import the universal baseline.
2. Skill contracts: define when each tool must be used.
3. Accountability skills: force handoffs/prompts to disclose tool use or routing exceptions.
4. Repo addendum: prime-radiant-ai gets concrete, repo-local examples.
5. Fleet/runtime docs: separate "tool available" from "tool adopted."

## Execution Phases
1. Baseline and manifest correction
2. Skill contract hardening
3. Accountability surfaces
4. Repo-level overlay
5. Validation and rollout

## Beads Structure
- Epic: `bd-8ws5`
- Child tasks:
  - `bd-b8te` research
  - `bd-2n6g` spec
  - `bd-2qhi` implementation
  - `bd-dqhl` validation
- Blocking edges:
  - `bd-b8te -> bd-2n6g`
  - `bd-2n6g -> bd-2qhi`
  - `bd-2qhi -> bd-dqhl`

## Exact File Changes

### 1. `/Users/fengning/agent-skills/scripts/publish-baseline.zsh`
Insert a new generated section immediately after `## 5.3) Blocking Skill Contracts Are Binding` and before `## 6) Parallel Agent Orchestration`.

```diff
+## 5.4) MCP Tool-First Routing Contract (V8.5)
+
+- **Canonical active assistant stack**:
+  - `context-plus`: semantic discovery / repo mapping
+  - `llm-tldr`: exact static analysis / trace / impact
+  - `serena`: symbol-aware edits / persistent assistant memory
+- **Canonical non-default memory surface**:
+  - `cass-memory`: pilot-only CLI tool; not part of the default assistant loop
+
+For qualifying tasks, agents MUST route the first discovery action through the matching MCP tool before broad shell search or repeated file traversal:
+- semantic repo discovery, feature location, "where does X live?", or "what code is related to X?" -> `context-plus`
+- exact call-path, slice, impact, CFG/DFG, dead-code, or structural trace -> `llm-tldr`
+- symbol-aware edits, rename/refactor, insertion, project memory, or prior-session continuity -> `serena`
+
+Fallback to shell/file reads is allowed only when:
+- the MCP tool is unavailable in the current runtime
+- the MCP tool cannot answer the question after one reasonable attempt
+- the task is trivially faster with direct file access
+
+If the agent does not use the matching MCP tool on a qualifying task, it MUST state `Tool routing exception: <reason>` in the final response or handoff.
```

Implementation rule:
- do not hand-edit downstream generated baselines; regenerate from this source.

### 2. `/Users/fengning/agent-skills/extended/context-plus/SKILL.md`
Replace the stale install/runtime section and add a trigger contract.

```diff
-## Current Fleet Status
-
- - Fleet contract: MCP-rendered tool
- - Current state: ✅ ENABLED
- - Install: `npx -y contextplus` or `bunx contextplus`
+## Current Fleet Status
+
+- Fleet contract: MCP-rendered tool
+- Current state: ✅ ENABLED
+- Install: `~/agent-skills/scripts/install-contextplus-patched.sh`
...
-## Installation
-```bash
-# Option 1: Run directly with npx (recommended)
-npx -y contextplus
-
-# Option 2: Install globally with bun
-bunx contextplus
-```
+## Installation
+```bash
+~/agent-skills/scripts/install-contextplus-patched.sh
+```
...
-      \"command\": \"npx\",
-      \"args\": [\"-y\", \"contextplus\"]
+      \"command\": \"node\",
+      \"args\": [\"/Users/$USER/.local/share/contextplus-patched/build/index.js\"]
```

Add this section after `## Usage Patterns`:

```diff
+## Required Trigger Contract
+
+Use `context-plus` first when the task is primarily about semantic discovery:
+- locating the part of the repo responsible for a concept or feature
+- mapping related files/modules before editing
+- answering "where does this live?" or "what else is related to this?"
+
+Do not skip directly to broad grep/file traversal for those questions unless a documented fallback condition applies.
```

### 3. `/Users/fengning/agent-skills/extended/llm-tldr/SKILL.md`
Fix upstream links and add an explicit trigger contract.

```diff
-## Upstream
-
- - **Repo**: https://github.com/simonw/llm-tldr
- - **Docs**: https://github.com/simonw/llm-tldr#readme
+## Upstream
+
+- **Repo**: https://github.com/parcadei/llm-tldr
+- **Docs**: https://github.com/parcadei/llm-tldr#readme
```

Add this section after `## Usage Patterns`:

```diff
+## Required Trigger Contract
+
+Use `llm-tldr` first when the task needs exact structure instead of semantic discovery:
+- call graph or reverse-call impact
+- CFG/DFG/program slice
+- dead code or architecture layer analysis
+- "trace the exact code path that leads here"
+
+Do not skip directly to repeated `read_file` traversal for these questions unless a documented fallback condition applies.
```

### 4. `/Users/fengning/agent-skills/extended/serena/SKILL.md`
Add the missing routing trigger contract.

```diff
+## Required Trigger Contract
+
+Use `serena` first when the task is primarily about symbol-aware editing or assistant continuity:
+- rename/refactor of known symbols
+- insert-before/after-symbol edits
+- retrieving or recording persistent project memory
+- structured symbol lookup before editing a known target
+
+If the task is "edit this exact symbol safely," `serena` is the default first tool.
```

Place the new section after `## Usage Patterns`.

### 5. `/Users/fengning/agent-skills/extended/cass-memory/SKILL.md`
Demote the skill from default-stack language to pilot-only language.

```diff
-description: CLI-native procedural/episodic memory workflow with opt-in sanitized cross-agent digest sharing.
+description: Pilot-only CLI episodic memory workflow for explicit cross-agent memory experiments.
...
-# CASS Memory (Fleet Sync V2.2)
+# CASS Memory (Pilot Only)
...
-CLI-native episodic memory for recurring patterns, decisions, and failure playbooks.
+CLI-native episodic memory for explicit experiments in recurring-pattern capture. This is not part of the canonical default assistant loop.
```

Add this section after `## Tool Class`:

```diff
+## Status
+
+- Default stack status: NOT CANONICAL
+- Fleet status: pilot-only / disabled by default in the manifest
+- Use only when the task explicitly asks for cross-session or cross-agent memory experimentation
+- Do not require this tool in standard repo workflows
```

### 6. `/Users/fengning/agent-skills/configs/mcp-tools.yaml`
Disable `cass-memory` by default and correct `llm-tldr` upstream metadata.

```diff
-    upstream: "https://github.com/simonw/llm-tldr"
-    docs: "https://github.com/simonw/llm-tldr#readme"
+    upstream: "https://github.com/parcadei/llm-tldr"
+    docs: "https://github.com/parcadei/llm-tldr#readme"
...
  cass-memory:
-    enabled: true
+    enabled: false
```

Add a clarifying comment above `cass-memory`:

```diff
-  # cass-memory: CLI-native episodic memory (CLI mode)
-  # Not rendered to IDE configs - standalone CLI tool.
+  # cass-memory: pilot-only CLI episodic memory (disabled by default)
+  # Not rendered to IDE configs and not part of the canonical assistant loop.
```

### 7. `/Users/fengning/agent-skills/infra/fleet-sync/resources/tool-contracts.md`
Add a Layer 5 adoption section so availability and usage stop being conflated.

```diff
-Full platform GO achieved for verified Layer 4 visibility.
+Layer 4 visibility is necessary but not sufficient.
+
+## Layer 5: Agent Adoption
+
+A tool is not considered healthy in practice unless agents are instructed to use it for the right task class.
+
+Required Layer 5 checks:
+- generated AGENTS baseline contains the MCP Tool-First Routing Contract
+- relevant skill docs contain Required Trigger Contract sections
+- repo-level addenda contain at least repo-specific examples where needed
+- handoffs/prompts can report tool use or a routing exception
+
+Current state: Layer 4 GO does not imply Layer 5 GO.
```

### 8. `/Users/fengning/agent-skills/core/tech-lead-handoff/SKILL.md`
Add a required tool-evidence artifact to make adoption reviewable.

```diff
 ## Shared Required Artifacts (Both Modes)
 ...
 - Validation summary (commands + pass/fail)
+- Tool Evidence summary:
+  - tools used: `context-plus`, `llm-tldr`, `serena`
+  - or `Tool routing exception: <reason>`
 - Changed files summary
```

Add a matching bullet in both output templates:

```diff
+### Tool Evidence
+- Used: <tool list>
+- Routing exception: none
```

### 9. `/Users/fengning/agent-skills/extended/prompt-writing/SKILL.md`
Require delegated prompts to tell workers which MCP tool should be used first.

```diff
-  Enforces: worktree-first, no canonical writes, Beads traceability (epic/subtask/dependencies), and required PR artifacts (PR_URL + PR_HEAD_SHA).
+  Enforces: worktree-first, no canonical writes, Beads traceability (epic/subtask/dependencies), MCP routing expectations, and required PR artifacts (PR_URL + PR_HEAD_SHA).
```

Add under the delivery contract section:

```diff
+- Tool routing contract for the delegated task:
+  - semantic discovery -> `context-plus`
+  - exact static analysis -> `llm-tldr`
+  - symbol-aware editing / memory -> `serena`
+- If a delegated agent intentionally skips the expected tool, it must return `Tool routing exception: <reason>`
```

### 10. `/Users/fengning/prime-radiant-ai/fragments/repo-addendum.md`
Add repo-specific tool routing examples instead of editing the generated universal baseline directly.

```diff
+### Tool-First Routing (Repo-Specific)
+
+For work in this repo:
+- use `context-plus` first for "where does this feature live?", route mapping, and semantically related code discovery
+- use `llm-tldr` first for exact trace work: call paths, slices, impact, and structural debugging
+- use `serena` first for known-symbol refactors, insertions, and persistent project context
+
+If one of these is skipped on a qualifying task, the final response or handoff must include `Tool routing exception: <reason>`.
```

Implementation rule:
- do not hand-edit `fragments/universal-baseline.md`; regenerate it from `agent-skills` after baseline changes land.

## Validation
- Baseline generation:
  - `cd /tmp/agents/bd-2n6g/agent-skills && make publish-baseline`
- Manifest consistency:
  - `rg -n "cass-memory|context-plus|llm-tldr|serena" /Users/fengning/agent-skills/configs/mcp-tools.yaml`
- Repo inheritance:
  - regenerate `prime-radiant-ai` AGENTS after baseline sync and confirm the new routing text appears
- Runtime health:
  - `codex mcp list`
  - `opencode mcp list`
  - `claude mcp list`
- Layer 5 adoption spot-check:
  - one qualifying research task should show actual use of one of the three MCP tools or an explicit routing exception

## Risks / Rollback
- Risk: over-constraining trivial tasks
  - mitigation: keep the fallback clause explicit and narrow
- Risk: documentation drift between manifest and skill docs
  - mitigation: change manifest + skill docs in the same implementation task
- Rollback:
  - revert the new baseline section and skill trigger contracts
  - restore `cass-memory.enabled: true` only if a deliberate pilot decision is made

## Recommended First Task
- First task: `bd-2qhi`
- Why first: the research is done and the spec now names the exact enforcement surfaces; implementation can proceed directly without more discovery.

## Deliverable Contract
- `SPEC_PATH: /tmp/agents/bd-2n6g/agent-skills/docs/specs/2026-03-27-mcp-tool-first-routing-and-cass-disposition.md`
- `BEADS_EPIC: bd-8ws5`
- `BEADS_CHILDREN: bd-b8te, bd-2n6g, bd-2qhi, bd-dqhl`
- `BLOCKING_EDGES: bd-b8te -> bd-2n6g; bd-2n6g -> bd-2qhi; bd-2qhi -> bd-dqhl`
- `FIRST_TASK: bd-2qhi`
- `VALIDATION_GATES: baseline regeneration, manifest consistency, repo inheritance, client visibility, Layer 5 adoption spot-check`
