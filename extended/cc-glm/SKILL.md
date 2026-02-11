---
name: cc-glm
description: |
  Use cc-glm (Claude Code wrapper using GLM-4.7) in headless mode to outsource repetitive work.
  Trigger when user mentions cc-glm, glm-4.7, "headless", or wants to delegate easy/medium tasks to a junior agent.
tags: [workflow, delegation, automation, claude-code, glm]
allowed-tools:
  - Bash
  - Read
---

# cc-glm (Headless Delegation)

## Delegation Boundary (V8.1)

**Delegate**: Mechanical tasks estimated < 1 hour with clear acceptance criteria.

**Never delegate**:
- Security-related changes (auth, secrets, permissions)
- Architecture decisions (schema changes, API design)
- High-risk operations (database migrations, deployment configs)
- Multi-repo coordination (use jules-dispatch or parallelize-cloud-work instead)

## When To Use

- You want to delegate repetitive CLI/codebase work (search, refactors, doc edits, running tests).
- You want a headless sub-agent loop without opening an interactive TUI.
- The task is well-scoped, mechanical, and estimated under 1 hour.

## DX V8.1 Constraints

- **Worktree mandatory**: Always work in worktrees, never canonical clones (`~/agent-skills`, `~/prime-radiant-ai`, `~/affordabot`, `~/llm-common`).
- **No secrets**: Do not print or dump dotfiles/configs (they often contain tokens). Avoid `type cc-glm` and avoid `cat ~/.zshrc`.
- **No git commit/push**: Delegated agents propose diffs only; humans commit.
- **Feature-Key tracking**: All prompts must include Beads ID for traceability.

## Quick Start

`cc-glm` is typically a **zsh function**, not a binary. In headless/non-interactive contexts, invoke via:

```bash
zsh -ic 'cc-glm -p "YOUR PROMPT" --output-format text'
```

**Recommended**: Use the DX-compliant delegation wrapper:

```bash
# Using the helper script (enforces guardrails)
~/agent-skills/scripts/dx-delegate.sh --beads-id bd-f6fh --repo agent-skills --prompt-file /path/to/prompt.txt

# Or the existing cc-glm wrapper
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt-file /path/to/prompt.txt
```

## Fallback

If `cc-glm` is not available on the host, fall back to standard Claude Code headless mode:

```bash
claude -p "YOUR PROMPT" --output-format text"
```

## DX-Compliant Prompt Template

When delegating to cc-glm, use this prompt structure:

```text
you're a mid-level junior dev agent working in a git worktree.

Repo: /tmp/agents/<beads-id>/<repo>
Branch: codex/<beads-id>-<repo>-<suffix>
Feature-Key: <beads-id>
Agent: cc-glm

## DX V8.1 Invariants (must follow)
- Never edit canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}. Work only in the worktree path above.
- Do not run git commit/push, do not open PRs. Just propose diffs + commands to run.
- Any new scripts must be deterministic + safe (no secrets).

## Scope
[Describe the specific task with clear boundaries]

## Constraints
- [List any technical constraints, edge cases to avoid]

## Expected Outputs
- [List specific deliverables: files to read, patches to propose, commands to run]

## Output Format
[Unified diff patch against current files, then list any commands to run to validate]
```

### Example Delegation Prompt

```text
you're a mid-level junior dev agent working in a git worktree.

Repo: /tmp/agents/bd-f6fh/agent-skills
Branch: codex/bd-f6fh-agents-skills-plane
Feature-Key: bd-f6fh
Agent: cc-glm

## DX V8.1 Invariants (must follow)
- Never edit canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common}. Work only in the worktree path above.
- Do not run git commit/push, do not open PRs. Just propose diffs + commands to run.
- Any new scripts must be deterministic + safe (no secrets).

## Scope
Update the cc-glm skill to include explicit delegation boundaries in SKILL.md.

## Constraints
- Maintain existing functionality
- Add delegation boundary section at the top
- Include "Never delegate" list for high-risk tasks

## Expected Outputs
- Unified diff of changes to extended/cc-glm/SKILL.md
- Commands to validate the changes
```

## Patterns That Work Well

```bash
# 1) Run a tight task in a worktree
zsh -ic 'cc-glm -p "cd /tmp/agents/bd-1234/agent-skills && rg -n \"TODO\" -S . | head" --output-format text'

# 2) Generate a patch plan (no edits)
zsh -ic 'cc-glm -p "Read docs/CANONICAL_TARGETS.md and propose a 5-step verification plan." --output-format text'

# 3) DX-compliant delegation via helper script
~/agent-skills/scripts/dx-delegate.sh \
  --beads-id bd-f6fh \
  --repo agent-skills \
  --scope "Add delegation boundary to cc-glm skill" \
  --constraints "No functional changes, documentation only" \
  --prompt "Update extended/cc-glm/SKILL.md with delegation rules"
```

## See Also

- **dx-delegate.sh**: DX-compliant wrapper with guardrails (canonical CWD check, worktree validation)
- **prompt-writing**: For comprehensive prompt patterns with plan-first gates
- **jules-dispatch**: For multi-repo or complex orchestration
- **parallelize-cloud-work**: For cloud-based parallel execution