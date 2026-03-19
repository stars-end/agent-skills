# DX-Loop Product Execution Retrospective

> Status: draft reference for future `dx-loop-mvp` work
>
> Feature-Key: `bd-c2wg`
>
> Date: 2026-03-18

## Purpose

This document captures a real founder-facing product execution attempt across two Prime Radiant waves:

1. a `dx-loop`-driven path intended to prove unattended `implement -> review -> revision if needed -> merge-ready`
2. an in-session subagent path used after `dx-loop` proved too expensive to keep hardening in the middle of product work

The goal is not to relitigate every branch detail. The goal is to preserve the operational lessons, identify the actual gap in `dx-loop`, and define the minimum bar for a future `dx-loop-mvp`.

## Executive Summary

`dx-loop` improved materially during this experiment, but it was still not ready for real product work.

It was able to:

- understand Beads dependency graphs
- avoid wasting dispatches on blocked waves
- open real implementer jobs
- produce reviewable PR artifacts after several control-plane fixes

It was not able to prove the thing that matters most for founder-low-load product execution:

- a trustworthy unattended loop from real task dispatch to real review to revision to merge-ready outcome

The in-session subagent approach did deliver the product wave.

It worked because:

- model choice was deliberate per task
- the orchestrator could steer or take over immediately when agents drifted
- real product blockers were addressed directly instead of being hidden behind control-plane state

The key documented gap for `dx-loop` is:

> `dx-loop` did not yet provide a dependable execution lane and review baton for real product tasks, so it remained a tool-under-test rather than a trustworthy product execution surface.

That gap should be the basis of a future `dx-loop-mvp`.

## Product Scope Used As The Test

The product execution target was the Prime Radiant two-wave stack:

### Wave 1: QA Clean

- `bd-sg2v.14.5.4.1` Prime Radiant auth policy cleanup and canonical manual/browser bypass helper
- `bd-sg2v.14.5.4.2` agent-skills guidance for the three auth lanes and canonical helper usage

### Wave 2: Testing/Product

- `bd-sg2v.14.5.3.1` canonical QA personas and shared V2 data contract
- `bd-sg2v.14.5.3.2` `/demo` as a usable product test-drive
- `bd-sg2v.14.5.2` explicit full Plaid connected-state proof
- `bd-sg2v.14.5.3.3` trust-gap cleanup around session isolation and stale state carryover

This was a good test because it combined:

- real dependencies
- cross-repo guidance work
- frontend product behavior
- CI-sensitive validation
- founder-visible correctness

## What We Tried With DX-Loop

### Initial Goal

Use `dx-loop` as the primary orchestrator on the default lane, with the expectation that it would:

- respect dependency order
- dispatch when work became runnable
- keep waiting state truthful
- hand off from implementer to reviewer
- support revision loops without active babysitting

### What Happened

The early `dx-loop` runs exposed multiple control-plane issues before meaningful product implementation began.

Notable issues discovered:

- `bd-5w5o.16` Ship `dx-loop` operator entrypoint on PATH or document canonical invocation
- `bd-5w5o.17` Make `dx-loop` surface dependency-blocked waves explicitly instead of generic pending
- `bd-5w5o.19` Make `dx-loop` wave bootstrap visible to status immediately after start
- `bd-5w5o.20` `dx-loop` should not run indefinitely when a wave starts with zero dispatchable tasks
- `bd-5w5o.21` `dx-loop` should recognize newly closed Beads dependencies instead of classifying them as external_or_incomplete
- `bd-5w5o.22` `dx-loop` should not report `in_progress_healthy` when implement dispatch fails before any run starts
- `bd-5w5o.23` `dx-loop` should launch `dx-runner` through a Bash 4 compatible entrypoint or fail with explicit shell preflight on macOS
- `bd-5w5o.25` `dx-loop` should adopt already-running `dx-runner` jobs on restart instead of reporting `run_blocked`
- `bd-5w5o.26` `dx-runner/opencode`: product-wave implement runs quick-fail with `monitor_no_rc_file` before agent output
- `bd-5w5o.27` `dx-loop` CLI ignores `--config` so cadence/provider overrides are not applied from the command surface
- `bd-ppt4` `dx-loop`: persist implement baton and auto-dispatch review after successful implement run
- `bd-aoy1` `dx-loop`: support prompt artifacts / stronger implement prompts for real product waves

### Hardening That Landed During The Attempt

Several fixes were implemented and merged during the experiment:

- operator entrypoint and blocked-wave state truthfulness
- blocked-at-start auto-exit instead of idling for hours
- closed dependency recognition
- prompt-writing / tech-lead-handoff / review-contract integration
- stronger review baton persistence
- macOS host preflight and launch hardening

This was not wasted work. It meaningfully improved `dx-loop`.

But it also changed the character of the session:

- instead of doing product work, we were doing `dx-loop` infrastructure work in order to reach product work

That tradeoff eventually became too expensive.

## Why DX-Loop Still Was Not Ready

After the hardening work, `dx-loop` was better but still not trustworthy enough for founder-facing product execution.

### 1. It Consumed Founder Attention Before Product Work Started

The early failure mode was especially costly:

- a wave could be "alive" for hours while being non-actionable
- the scheduler state was technically correct
- the operator experience was operationally misleading

That violated the intended value proposition.

`dx-loop` should reduce monitoring load, not create a new kind of monitoring burden.

### 2. The Default Execution Lane Was Not Stable Enough

Even after control-plane fixes, the default OpenCode lane still hit real product-work reliability problems:

- monitor/bootstrap quick-fails
- shell/runtime mismatches on macOS
- stale adoption/restart behavior

The remaining failures were no longer about the DAG. They were about whether a real run would start, stay healthy, and emit actionable artifacts.

### 3. The Implementer -> Reviewer Baton Was Not Proven End-To-End

This was the key test and it did not pass.

The experiment improved implementer dispatch and review prompt structure, but it did not yet prove:

- implementer returns a strong artifact
- reviewer runs automatically
- reviewer produces deterministic actionable feedback
- loop redispatches revision successfully
- loop reaches merge-ready without hand-holding

That is the core missing capability.

### 4. Prompt Quality Was Still Too Generic For Real Product Waves

`dx-loop` improved once prompt-writing, structured handoffs, and the review contract were integrated.

But the product result was still weaker than the best in-session orchestration because:

- dependency-base nuances needed live steering
- product-specific validation expectations needed active judgment
- some branches required direct takeover rather than another blind re-dispatch

In short:

- the loop gained better prompt plumbing
- it still lacked enough repo-aware execution quality to replace an engaged tech lead

## What Worked Better With In-Session Subagents

After pivoting away from `dx-loop`, the product stack moved faster.

### Concrete Wins

- We chose stronger models for the contract-setting tasks and faster coding-oriented models for bounded implementation tasks.
- We could inspect and redirect weak work immediately.
- We could take over locally when a subagent stalled instead of waiting for the control plane to notice.
- We preserved momentum across stacked branches and CI friction.

### Product Outcomes Delivered

The in-session subagent path produced the actual product stack:

- canonical bypass helper and auth-lane guidance
- shared V2 QA persona contract
- `/demo` as a usable product test-drive
- explicit connected-state Plaid proof
- trust-gap cleanup around session isolation

Those outcomes were not hypothetical. They were implemented as real PRs and moved through review.

## Subagent Approach Strengths

### Strengths

- deliberate model choice per task
- immediate steering when an agent drifted
- easy takeover when a task stalled
- better fit for stacked product branches
- lower control-plane tax during active product work

### Weaknesses

- more hands-on orchestration from the main session
- weaker persistent automation story
- less durable than a true unattended loop
- success depended on an engaged orchestrator rather than a dependable control plane

## DX-Loop Strengths

Even though `dx-loop` was not ready, it did demonstrate real strengths.

### Strengths

- persistent wave state
- explicit dependency handling
- real PR-aware orchestration model
- growing convergence on Ralph-like baton semantics
- machine-actionable status and blocker surfaces after hardening

This means `dx-loop` is not a dead end.

It is a promising orchestration layer that has not yet crossed the threshold into dependable product execution.

## The Documented Gap

This is the single most important conclusion from the experiment:

## Documented Gap

`dx-loop` does not yet provide a dependable unattended real-product execution lane that can:

1. start cleanly on the default provider
2. keep operator state truthful during failures and blocked periods
3. produce strong task-specific implementation output
4. hand off automatically into deterministic review
5. support revision loops without active founder babysitting
6. exit at merge-ready with confidence

Until that gap is closed, `dx-loop` is still a DX hardening project, not the primary way to ship founder-facing product work.

## What A Future DX-Loop-MVP Should Target

The MVP should not try to solve every orchestration problem.

It should solve the narrow problem that mattered most in this experiment:

### `dx-loop-mvp` target

> Make one real stacked product wave complete via unattended `implement -> review -> revision if needed -> merge-ready` on the default lane, with truthful status and no founder babysitting.

### Required MVP Scope

#### 1. Stable Default Execution Lane

- default provider starts reliably on canonical hosts
- host preflight failures are explicit and early
- no silent quick-fail before agent output

#### 2. Truthful Operator States

- blocked-at-start waves do not linger indefinitely
- start/bootstrap races are visible
- failed dispatch never appears healthy
- already-running jobs are adopted instead of misclassified

#### 3. Real Prompt Artifacts

- implementer prompt is task-specific and dependency-aware
- reviewer prompt consumes a structured implementation handoff
- review verdict is deterministic and machine-actionable

#### 4. Review Baton That Actually Works

- implement success triggers review automatically
- review can demand revision with structured findings
- loop redispatches revision cleanly
- merge-ready is explicit and trustworthy

#### 5. Branch And Stack Awareness

- dependency PR heads are honored, not just trunk
- stacked PRs do not collapse into merge confusion
- merge-readiness reflects real branch state, not stale assumptions

## Non-Goals For DX-Loop-MVP

To keep scope sane, the MVP should explicitly avoid:

- becoming a universal distributed scheduler
- supporting every provider equally well on day one
- solving all multi-repo orchestration cases
- replacing live orchestration for exploratory product work
- auto-merging

## Recommended Acceptance Test

The next real acceptance test should be a single stacked product wave comparable to the Prime Radiant wave used here.

Success criteria:

- one wave root
- one default provider lane
- real implementation PR
- real review pass
- at least one forced revision loop
- merge-ready outcome without manual orchestration between steps

If that works, `dx-loop` is ready for another serious product trial.

If it fails, the failure should produce a new narrow issue, not another sprawling hardening campaign.

## Suggested Side-Quest Follow-Ups Outside DX-Loop-MVP

These were useful lessons but should not be the core MVP:

- stronger AGENTS guidance for dependency-base selection on stacked PR work
- explicit frontend worktree bootstrap guidance (`pnpm install --frozen-lockfile`)
- commit-hook support for dotted Beads ids without `--no-verify`
- simpler targeted frontend test runners outside contract-heavy defaults

These matter, but they are broader workflow quality improvements rather than the central `dx-loop` gap.

## Recommended Agent-Skills Follow-Ups

These are the most likely `agent-skills` improvements worth doing as a side-quest:

### AGENTS / Baseline Guidance

- tell downstream agents to base stacked work on dependency PR heads, not just `master`
- call out frontend worktree bootstrap explicitly for Prime Radiant
- state when local takeover is preferred over waiting on a stalled delegated run

### Prompt-Writing

- add a standard section for "branch base / dependency PR head"
- add explicit validation expectations for frontend-heavy repos
- add a standard "if stacked PRs exist, do not silently re-base to trunk" instruction

### Review Contract

- require findings-first review with concrete file references
- require a deterministic verdict that an orchestrator can consume
- treat "implementation weak / prompt weak" as a first-class review outcome instead of generic failure

### Possible New Skill

If we create a new skill, it should be narrow.

Best candidate:

- `stacked-pr-handoff`

Purpose:

- capture dependency PR heads
- define the expected merge order
- record what must be refreshed after upstream merge

This is more attractive than a broad new orchestration skill because it addresses a repeated failure mode without expanding the control plane.

## Recommendation

For current founder-facing product work:

- prefer in-session subagents plus direct orchestration

For future automation investment:

- build `dx-loop-mvp` around the documented gap above

That preserves the long-term payoff bias without letting the control plane consume the product roadmap.
