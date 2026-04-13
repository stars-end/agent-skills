---
name: spark-prompt-writer
description: |
  Write tightly scoped, execution-ready prompts optimized for `gpt-5.3-codex-spark` implementation batches and short verification passes.
  Use when the user wants a Spark-specific overnight batch prompt, a large grouped-fix prompt, or a follow-on integrated verification prompt after fix waves.
  Preserve the `prompt-writing` DX contract: worktree-first, no canonical writes, Beads traceability, cross-VM-safe context, and required `PR_URL` + `PR_HEAD_SHA`.
tags: [workflow, prompts, orchestration, spark, dx]
allowed-tools:
  - Read
  - Bash
---

# Spark Prompt Writer

## Goal

Generate prompts that fit `gpt-5.3-codex-spark` well:
- large enough to be worth delegation
- narrow enough to avoid drift
- explicit enough to run overnight without hand-holding

This skill specializes `prompt-writing` for Spark-shaped execution.

## When To Use

Use this skill when the user wants:
- a prompt pack for overnight implementation batches
- one large grouped-fix prompt instead of piecemeal tickets
- a Spark-specific rewrite of an existing implementation plan
- a short integrated verification pass after multiple fix batches land

Do not use this skill for:
- local implementation in the current session
- high-level planning with no delegation intent
- tiny single-file prompts that do not need Spark-specific shaping

## Positioning

`spark-prompt-writer` is a specialization of `prompt-writing`, not a replacement.

Keep all outbound DX invariants from `prompt-writing`, then add Spark-specific tightening:
- one coherent outcome per prompt
- exact files to read first
- exact validation commands
- exact blocker protocol
- exact done gate
- explicit stale/duplicate/trunk-already-satisfied handling

## Boundary: Review Lanes

Use this skill for outbound Spark implementation/verification prompt packs. For
inbound reviewer lanes, call `dx-review --template <smoke|code-review|architecture-review|security-review>`
and do not embed review prompt bodies manually.

## Spark Optimization Rules

### 1. Batch by outcome, not by file

Each prompt should own one coherent batch:
- analytics integrity wave
- Plaid reliability wave
- integrated V2 verification wave

Do not split a batch into side PRs unless the user explicitly asks.

### 2. Front-load context

Every prompt must include:
- `PR_URL`
- `PR_HEAD_SHA`
- repo-relative files to read first
- mandatory fetch/checkout step before worktree creation

Spark performs better when the first reading set is explicit and short.

### 3. Reduce narrative, increase structure

Prefer:
- fixed headings
- numbered acceptance criteria
- enumerated validation commands
- concrete response schema
- non-blocking execution-plan checkpoints

Avoid:
- long prose explanations
- speculative architecture discussion
- optional branches unless truly needed

### 4. Force truthful resolution behavior

Every Spark prompt should say what to do if:
- the issue is already fixed on trunk
- the issue is stale
- two incidents collapse into one root cause
- one included issue is only adjacent, not the same failure

Require the agent to document that outcome in the PR summary instead of silently reimplementing.

### 5. Require a real artifact return

Every implementation prompt must require:
- committed and pushed changes
- draft PR
- `PR_URL`
- `PR_HEAD_SHA`

If any of those are missing, the run is incomplete.

## Dispatch Workflow

This skill writes prompt packs, but prompt packs also need an execution topology.

Use this default workflow unless the user explicitly asks for a different rollout:

### 1. Run independent implementation batches first

If the pack contains multiple implementation batches:
- run independent batches in parallel
- cap parallelism at `2` by default
- give each batch one coherent outcome and one PR

Good parallel pair:
- analytics integrity batch
- Plaid reliability batch

Do not add the verification pass to this first wave.

### 2. Review and converge before verification

After implementation batches return:
- review each return in the orchestrator session
- accept, repair, or redispatch each batch
- merge accepted batches before launching integrated verification

The orchestrator owns:
- outcome review
- repair decisions
- merge gating
- final decision on whether the system is ready for integrated verification

### 3. Run integrated verification last

Integrated verification should run only after the upstream implementation batches are landed, or at minimum materially validated on one convergence base.

Do not run the verification pass in parallel with the implementation wave unless the user explicitly wants early failure sampling and accepts noisy results.

Default sequence:
1. implementation batch A
2. implementation batch B
3. review/repair/merge A and B
4. integrated verification batch

### 3.5. Active monitoring is part of the topology

For multi-prompt packs, the orchestrator should not rely on passive completion notifications alone.

Default monitoring expectation:
- poll on a short cadence after dispatch
- confirm each implementation batch moved past any planning checkpoint
- if an agent is silent after early polls, request status explicitly
- if the agent still does not respond clearly, interrupt and demand progress or blocker state

Prompt packs should be written so the orchestrator can tell the difference between:
- waiting for approval
- active implementation
- real blocker
- silent stall

### 4. One repair round max by default

For Spark-shaped execution:
- allow one repair redispatch per batch by default
- if the batch is still messy after one repair round, take over locally or switch execution surfaces

This keeps Spark fast without letting it churn indefinitely.

### 5. Keep the topology generic

Write prompts so they are portable across execution surfaces:
- Spark subagents in-session
- other subagent models
- governed runners such as `dx-runner`

The prompt should encode:
- the batch outcome
- the acceptance contract
- the review gate

The surrounding orchestration can change later without rewriting the batch intent.

## Default Prompt Shapes

### A. Overnight Implementation Batch

Use this shape when Spark should implement one large grouped-fix outcome.

Required sections:
1. `DX Global Constraints`
2. `Assignment Metadata`
3. `Outcome Enforcement`
4. `Cross-VM Source of Truth`
5. `Step 0: Fetch Remote PR`
6. `Objective`
7. `Included Incident Bundle`
8. `Scope`
9. `Acceptance Criteria`
10. `Validation (Required)`
11. `Execution Plan (Mandatory)`
12. `Required Deliverables`
13. `Blockers Protocol`
14. `Done Gate`

Execution-plan wording should be non-blocking by default:
- ask the delegate to report the plan briefly
- then continue automatically unless blocked

Preferred wording:
- `Before coding, reply with your execution plan, then continue automatically unless blocked.`

Avoid wording that implies:
- stop after plan
- wait for approval
- hold for confirmation before implementation

### B. Integrated Verification Pass

Use this shape when Spark should verify a repaired end-to-end product flow after implementation batches land.

Required sections:
1. `DX Global Constraints`
2. `Assignment Metadata`
3. `Outcome Enforcement`
4. `Cross-VM Source of Truth`
5. `Step 0: Fetch Remote PR`
6. `Verification Goal`
7. `Verification Route`
8. `Required Assertions`
9. `Validation Artifacts`
10. `Failure Handling`
11. `Required Deliverables`
12. `Done Gate`

## Overnight Batch Rules

For overnight implementation prompts:
- include one canonical issue bundle
- make root-cause consolidation an explicit deliverable
- require the agent to say whether included issues collapsed into one cause or remained separate
- cap scope to the named incident family
- make the execution-plan response non-blocking
- tell the agent to continue automatically after the plan unless blocked
- require the agent to adapt validation to current repo truth if one named command is stale

Good bundle examples:
- analytics integrity
- Plaid reliability
- auth/session stability

## Integrated Verification Rules

For verification prompts:
- define the route step by step
- define the expected state at each step
- define what counts as pass vs residual bug
- require screenshots, logs, or explicit test outputs if the route is UI-heavy

The purpose is not to "look around." The purpose is to prove a founder-facing path works.

## Response Contract

When asked to produce prompts, return:
1. a short `Dispatcher Notes` section if needed
2. one copy/paste prompt per batch
3. nothing else unless the user asks for commentary

If the user asks how to run the pack, say explicitly:
- which prompts run in parallel
- which prompts wait on review/merge
- what the orchestrator should do between waves
- what cadence the orchestrator should use for active monitoring

## Preflight Checklist

Before emitting a Spark prompt, verify:
- concrete `BEADS_EPIC`
- concrete `BEADS_SUBTASK`
- no placeholder IDs
- no local absolute paths in required context
- `PR_URL` and `PR_HEAD_SHA` are present
- file list is short and relevant
- validation commands are explicit and still match current repo config
- stale/trunk-already-fixed behavior is defined
- dispatch topology is defined when emitting a multi-prompt pack
- execution-plan wording does not create a stop-and-wait checkpoint
- active monitoring expectations are defined when emitting a multi-prompt pack

If any of these are missing, stop and resolve them first.

## Recommended Wording Patterns

Use direct language:
- "Execute one big-bang DEV-only analytics integrity batch"
- "Treat these incidents as one coherent reliability wave"
- "Do not open side PRs"
- "If trunk already satisfies part of the task, document it and do not reimplement it"
- "Do not claim complete until draft PR exists and final response includes `PR_URL` and `PR_HEAD_SHA`"

## Anti-Patterns

- prompts that mix implementation and architecture redesign
- prompts that ask Spark to decide the scope boundary from scratch
- prompts that omit the exact files to read first
- prompts that rely on local `/Users/...` paths as the source of truth
- prompts that allow a "done" response without a real PR artifact
- prompts that split a single incident family into multiple small side quests
- prompt packs that do not say which prompts run in parallel vs sequentially
- prompts whose execution-plan step causes the delegate to wait for approval
- prompts with validation commands that are stale relative to the current repo configuration

## Relationship to Other Skills

- Use `prompt-writing` for the base delegation contract.
- Use `spark-prompt-writer` when that contract needs to be tuned specifically for `gpt-5.3-codex-spark` overnight execution.
- Use `agent-skills-creator` when evolving this skill further.
