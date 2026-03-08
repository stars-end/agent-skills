# Prime Radiant Codex Loop POC Tests

Run these manually in a live Codex session to test whether the skill can drive a useful `dx-runner -> sleep -> check -> review -> re-dispatch` cycle.

## Test 1: Passive `dx-runner` Watch

Goal:
- prove that the skill can reduce manual polling once a run exists

Prompt:

```text
Use $loop-orchestration to draft a Codex-first monitoring loop for Beads item `bd-sg2v.11`. The loop should assume the job already exists, sleep 5 minutes between checks, inspect `dx-runner` state, stay quiet while healthy, and interrupt only if blocked, exited without a PR artifact, or ready for human review.
```

Pass condition:
- no noisy updates while status is unchanged
- a concise interrupt when the job materially changes state

## Test 2: Dispatch + Watch

Goal:
- prove that the skill includes dispatch and not just passive watching

Prompt:

```text
Use $loop-orchestration to draft a prompt that starts a `dx-runner` OpenCode job for a Prime Radiant V2 fix wave, sleeps 5 minutes between checks, inspects runner state, and transitions into PR babysitting once a PR exists.
```

Pass condition:
- the prompt includes an initial `dx-runner start`
- the prompt includes the post-dispatch sleep/check cycle

## Test 3: Deterministic Re-dispatch

Goal:
- prove that the loop can prepare a bounded next step without inventing scope

Prompt:

```text
Use $loop-orchestration to draft a loop that checks an active Prime Radiant V2 fix wave every 5 minutes. If the run exits without a PR update but the next step is deterministic, prepare a one-shot re-dispatch prompt. If the failure is semantic or ambiguous, interrupt for a decision instead of inventing a retry.
```

Pass condition:
- deterministic failure produces a tight re-dispatch prompt
- ambiguous failure produces a decision request instead of an auto-fix

## Test 4: Deployment Poll

Goal:
- test a non-PR polling target after a code change lands

Prompt:

```text
Use $loop-orchestration to draft a deployment watch loop for Prime Radiant V2. The loop should sleep 10 minutes between checks, inspect deployment health, stay quiet while rollout is normal, and interrupt on success, failure, or a new error signal that changes the next action.
```

Pass condition:
- quiet during normal rollout
- one interrupt on success or failure

## Test 5: Merge-Ready Transition

Goal:
- verify that the skill models the terminal state correctly

Prompt:

```text
Use $loop-orchestration to draft a PR babysitting loop for a Prime Radiant PR. It should sleep 5 minutes between checks, stay quiet while checks are pending, and interrupt only when the PR is blocked, needs a decision, or is ready for human merge.
```

Expected result:
- the prompt treats `merge_ready` as the terminal human handoff
- the prompt does not imply auto-merge

## Evaluation Notes

This POC is successful if:
- the generated prompt is Codex-first and `dx-runner`-centric
- the sleep/check cadence is explicit
- manual polling is materially reduced
- interrupts are low-noise
- deterministic retries can be staged safely
- merge-ready handoff is clear

This POC is not sufficient to prove:
- durable orchestration
- cross-session state recovery
- autonomous semantic fix generation
