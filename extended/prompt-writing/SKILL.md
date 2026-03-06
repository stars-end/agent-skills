---
name: prompt-writing
description: |
  Draft self-contained prompts for delegated agents with cross-VM-safe context.
  MUST BE USED when assigning work to another agent (implementation, QA, rollout, or audit).
  Enforces: worktree-first, no canonical writes, Beads traceability (epic/subtask/dependencies), and required PR artifacts (PR_URL + PR_HEAD_SHA).
  Trigger phrases include: "assign to another agent", "write a one-shot prompt", "dispatch this", "prepare autonomous prompt", "QA agent prompt".
tags: [workflow, prompts, orchestration, dx, safety]
allowed-tools:
  - Read
  - Bash
---

# Prompt Writing (Delegation Contract First)

## Goal

Generate a prompt another agent can execute autonomously without local-machine assumptions:
- Cross-VM safe context via GitHub PR link + commit SHA
- Self-contained requirements and acceptance criteria
- Beads traceability (epic/subtask/dependencies)
- Hard delivery contract: `PR_URL` + `PR_HEAD_SHA`

## Trigger Conditions (Mandatory)

Use this skill whenever user intent is delegation to another agent, including:
- "assign to another agent"
- "write me a one-shot prompt"
- "prepare a prompt for QA/dev agent"
- "dispatch this work"
- "make this autonomous for jr agent"

Do not wait for the user to say "prompt-writing" explicitly if delegation intent is clear.

## Core Requirements (Always)

Every generated delegation prompt MUST enforce:

1) **Cross-VM accessibility**
- Do not reference `/Users/...`, `/tmp/...`, or other local-only paths as source of truth.
- Primary context must be reachable by URL and commit, ideally:
  - `PR_URL`
  - `PR_HEAD_SHA`
  - repo-relative file paths in that PR/branch.

2) **Self-contained task definition**
- Objective, scope boundaries, acceptance criteria, and stop conditions must be in the prompt.
- Delegate must not need hidden context from local docs.

3) **Beads documentation contract**
- Include and require explicit identifiers:
  - `BEADS_EPIC`
  - `BEADS_SUBTASK`
  - `BEADS_DEPENDENCIES` (or `none`)
- If unknown, force delegate to return `BLOCKED: MISSING_BEADS_CONTEXT`.

4) **Worktree + canonical safety**
- No writes in canonical clones.
- Worktree required before edits.

5) **PR artifact return contract**
- Final response MUST include:
  - `PR_URL: https://github.com/<org>/<repo>/pull/<n>`
  - `PR_HEAD_SHA: <40-char sha>`
- If missing, delegate must return blocker with exact next commands.

## Output Contract (Always)

When user asks for a delegated prompt, return:
1) One copy/paste prompt
2) Optional short "Dispatcher Notes" (only if needed)
3) Nothing else unless user asks

## Required Prompt Skeleton

```markdown
you're a full-stack dev agent at a tiny fintech startup:

## DX Global Constraints (Always-On)
1) NO WRITES in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) Worktree first: `dx-worktree create <beads-id> <repo>`
3) Before "done": run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) Open draft PR after first real commit
5) Final response MUST include `PR_URL` and `PR_HEAD_SHA`

## Assignment Metadata (Required)
- BEADS_EPIC: <bd-...>
- BEADS_SUBTASK: <bd-....x>
- BEADS_DEPENDENCIES: <comma-separated bd ids OR "none">
- FEATURE_KEY: <bd-...>

## Cross-VM Source of Truth (Required)
- PR_URL: <required if exists>
- PR_HEAD_SHA: <required if exists>
- Repo paths to read first:
  - <path1>
  - <path2>

If PR_URL/PR_HEAD_SHA is not available yet, you must create/refresh branch and open a draft PR before finishing.

## Objective
<single-sentence success condition>

## Scope
- In scope: <explicit>
- Out of scope: <explicit>

## Acceptance Criteria
1) <criterion>
2) <criterion>
3) <criterion>

## Execution Plan (Mandatory)
Before coding, reply with:
1) Worktree path + branch name
2) Files to modify
3) Validation commands

## Required Deliverables
- Code changes committed and pushed
- Draft/updated PR
- Validation summary
- Return block:
  - PR_URL: https://github.com/<org>/<repo>/pull/<n>
  - PR_HEAD_SHA: <40-char sha>
  - BEADS_SUBTASK: <bd-...>

## Blockers Protocol
If blocked, return exactly:
- BLOCKED: <reason_code>
- NEEDS: <single dependency/info needed>
- NEXT_COMMANDS:
  1) <command>
  2) <command>

## Done Gate (Mandatory)
Do not claim complete until:
- changes are committed/pushed
- draft PR exists
- `dx-verify-clean.sh` passes
- final response includes PR_URL and PR_HEAD_SHA
```

## Cross-VM Guardrail (Critical)

Prompts that reference local absolute paths as required inputs are invalid for cross-VM delegation.
If there is no PR yet, instruct delegate to create one early and then continue using:
- PR URL
- HEAD SHA
- repo-relative paths

## Relationship to `tech-lead-handoff`

- `prompt-writing`: prepares autonomous prompts for another agent to execute.
- `tech-lead-handoff`: packages completed investigation/planning for human tech-lead review.

Use `prompt-writing` for delegation. Use `tech-lead-handoff` for approval handoffs.
