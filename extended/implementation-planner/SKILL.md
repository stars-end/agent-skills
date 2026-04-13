---
name: implementation-planner
description: |
  Create self-contained implementation specs with canonical Beads epic/subtask/dependency structure.
  MUST BE USED when the user asks for an implementation plan, tech spec, rollout plan, migration plan, or explicitly asks for "a comprehensive implementation plan with Beads epic, dependencies, and subtasks".
  Use for new systems, multi-phase refactors, cross-repo work, infra changes, or any work that needs a reviewable plan before execution.
tags: [planning, beads, specification, workflow, architecture]
allowed-tools:
  - Bash(bdx:*)
  - Read
  - Bash(bd:*)
  - Bash(git:*)
  - Bash(rg:*)
  - Bash(sed:*)
---

# Implementation Planner

Produce a reviewable plan that another agent or human can execute without hidden context.

## Goal

Every output from this skill should include:
- a written spec or implementation memo
- a canonical Beads structure using `BEADS_DIR=~/.beads-runtime/.beads`
- dependency edges that match the real execution order
- acceptance and validation gates
- a clear first executable task

## Canonical Contract

- Create and mutate Beads from a non-app directory with `BEADS_DIR=~/.beads-runtime/.beads`.
- Use worktrees for code/doc changes in canonical repos.
- Prefer one epic plus a small number of meaningful child tasks over a noisy task explosion.
- Model dependencies explicitly with `parent-child`, `blocks`, and `discovered-from`.
- Make the active contract executable, not aspirational.
- For cross-VM, cross-repo, vendor/API, infra/auth/workflow, or repeated-friction planning, retrieve memory first:
  - `bdx memories <keyword> --json`
  - `bdx search <keyword> --label memory --status all --json`
  - `bdx show <memory-id> --json`
  - `bdx comments <memory-id> --json`
- Memory lookup is optional for trivial routine edits/plans.

## When To Use

Use this skill when the user asks for:
- "write a comprehensive implementation plan"
- "make a spec"
- "break this into Beads tasks"
- "plan the migration"
- "review and refine the rollout plan"
- "give me epic + subtasks + dependencies"

## Output Shape

The plan should usually contain these sections:
- `Summary`
- `Problem`
- `Goals`
- `Non-Goals`
- `Active Contract`
- `Architecture / Design`
- `Execution Phases`
- `Beads Structure`
- `Validation`
- `Risks / Rollback`
- `Recommended First Task`

Use the templates in:
- `resources/spec-template.md`
- `resources/beads-planning-patterns.md`

## Workflow

### 1. Gather Minimal Context

Read only the files needed to answer:
- Which repo(s) are in scope?
- Is there already a Beads epic or existing work tree?
- Does the user want a new plan or a refinement of an existing one?
- Is the plan product, infra, migration, or meta-work?
- Is there existing Beads memory (KV or `memory` issues) that should constrain the plan?

For non-trivial planning domains, run targeted memory retrieval first and treat memory as guidance, not source truth.

### 2. Define the Execution Contract

Before writing the task tree, decide:
- the single success condition
- what is explicitly out of scope
- what order the work must happen in
- which parts can run in parallel
- what validation actually proves completion

If the plan cannot answer those questions, the plan is not ready.

### 3. Write the Spec

Create a self-contained memo in the target repo when there is a clear home for it.

Good destinations:
- `docs/specs/...`
- `docs/architecture/...`
- `docs/runbook/...`

If no repo path is appropriate, return the plan in the response and create the Beads structure only after the user confirms the target.

### 4. Create Canonical Beads Structure

Run Beads commands from a non-app directory with runtime explicitly set.

Preferred structure:
- `epic`: the full outcome
- `feature` or `task`: 3-7 meaningful child items
- `blocks`: only for true sequencing constraints

Default pattern:

```bash
cd ~
export BEADS_DIR="$HOME/.beads-runtime/.beads"
bdx create --title "<epic title>" --type epic --priority 1
bdx create --title "<phase or outcome>" --type feature --priority 1 --parent <epic>
bdx dep add <later-task> <earlier-task>
```

Use:
- `epic` for multi-phase outcomes
- `feature` for user-visible or coherent implementation chunks
- `task` for focused engineering work
- `chore` for narrow housekeeping only

### 5. Keep Dependencies Honest

Only add `blocks` when a task truly cannot start until another completes.

Examples:
- schema before API migration
- infra rollout before canary verification
- review findings fix before merge

Do not use `blocks` to express mere relatedness.

### 6. Define Validation Gates

Every plan should name the completion proof:
- build/test target
- runtime health check
- rollout verification
- operator check
- artifact review

If the plan has no validation section, it is incomplete.

### 7. End With the First Executable Task

The plan should always conclude with:
- the Beads epic id
- the immediate child task to start first
- why that task is first

## Durable Memory Capture From Planning

When the plan yields reusable knowledge, store it explicitly:

- Short global fact: `bdx remember --key <stable-key>`
- Structured durable memory: closed issue labeled `memory`
- Task-local rationale: `bdx comments add <issue-id>`

Required metadata for structured memory issues:

- `mem.scope`: `global|repo|tool|vendor|workflow`
- `mem.repo`: repo name or `global`
- `mem.source_issue`: concrete issue id or `none`
- `mem.kind`: `decision|runbook|learning|gotcha|handoff|best_practice`
- `mem.maturity`: `draft|validated|core`
- `mem.confidence`: `low|medium|high`

Optional metadata:

- `mem.paths`
- `mem.stale_if_paths`
- `mem.source_commit`
- `mem.query_hint`
- `mem.symbols`

## Planning Rules

- Prefer fewer, better tasks.
- Split by outcome, not by file.
- Put policy and architecture decisions in the spec, not in task titles.
- If a task depends on human approval, say so explicitly.
- If a migration must fail loudly, make that the active contract in the plan.

## Anti-Patterns

- giant flat task lists with no sequencing
- "investigate" subtasks without a decision gate
- putting every file change into Beads as its own task
- missing rollback or validation for infra work
- creating Beads tasks before the plan has a stable success condition

## Deliverable Contract

When you finish planning, return:
- `SPEC_PATH` or `INLINE_SPEC`
- `BEADS_EPIC`
- `BEADS_CHILDREN`
- `BLOCKING_EDGES`
- `FIRST_TASK`
- `VALIDATION_GATES`

## Related Skills

- `beads-workflow` for ongoing issue operations
- `prompt-writing` for delegation prompts after the plan is approved
- `tech-lead-handoff` for packaging a plan for review
