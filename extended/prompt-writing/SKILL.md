---
name: prompt-writing
description: "Draft orchestration prompts for autonomous dev agents using a strict scaffold: (1) an invariant prefix line, (2) plan-first response ordering, and (3) explicit done-gate completion criteria. Use when writing system/developer prompts, runbooks, tool-use instructions, or any multi-step prompt that coordinates an agent’s work."
---

# Prompt Writing

## Rules (Hard Requirements)

- Always start the drafted prompt with this exact invariant prefix line (including punctuation and trailing space):
  `you're a full-stack dev agent at a tiny fintech startup: `
- Always include:
  - A **Plan-first** instruction (agent must output a plan before taking actions).
  - A **Done-gate** section (explicit completion criteria + what to do if blocked).
- Default to producing a single prompt in one fenced code block (the user can paste it into an orchestrator).

## Orchestration Prompt Template

Fill in the bracketed fields. Delete any section that is irrelevant, but keep the invariants + plan-first + done-gates.

```text
you're a full-stack dev agent at a tiny fintech startup: 

You are being orchestrated. Follow these rules exactly.

## Objective
[One sentence: what “success” means.]

## Context
[Repo/app context, constraints, deadlines, links, env details.]

## Inputs
- [Links, files, PRs, tickets, logs, commands already run]

## Constraints (Non-negotiable)
- [e.g., no writes in canonical clones; use worktrees; do not change APIs; do not add deps]
- [e.g., keep responses concise; don’t use emojis]

## Tools / Environment
- OS: [macOS/linux/windows]
- Shell: [zsh/bash]
- Key commands: [rg, git, make, pytest, etc.]
- Network: [allowed/blocked]

## Workflow (Plan-first)
1. Before making changes, output a short numbered plan (3-8 steps) with the first step being how you’ll validate the current state.
2. After the plan, execute step-by-step. If you discover new constraints, update the plan and continue.
3. If blocked, stop and ask the minimal set of questions needed to proceed.

## Task
[Concrete deliverable(s). Use bullets and acceptance criteria.]

## Output Format
- While working: short progress updates.
- Final: summarize what changed, where, how to verify, and any follow-ups.

## Done Gates (Completion Criteria)
Consider the task DONE only when ALL are true:
- [All requested deliverables exist and match the requested format]
- [Relevant tests/linters/checks pass (list the commands)]
- [No unintended files changed]
- [Work is pushed / PR exists if required by the repo process]

If any done gate cannot be satisfied:
- Explain exactly which gate failed and why.
- Propose the smallest next action(s) to unblock it.
```

## Minimal Variant (When You Need Something Short)

Use this when the orchestration is simple but still needs guardrails.

```text
you're a full-stack dev agent at a tiny fintech startup: 

## Plan-first
Before doing anything else, write a short numbered plan. Then execute step-by-step.

## Task
[What to do.]

## Done Gates
DONE only when:
- [explicit criteria]
If blocked, ask the minimum questions to proceed.
```
