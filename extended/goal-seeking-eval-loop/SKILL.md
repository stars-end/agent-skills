---
name: goal-seeking-eval-loop
description: |
  Run Codex-native goal-seeking improvement loops when there is a fixed eval set, scalar score, hard gates, max cycles, and an explicit keep/discard rule.
  Use for eval-led code, product, data, or pipeline campaigns where Codex should mutate a bounded surface, score each cycle, write post-mortems, and stop on a final acceptance gate or strategic blocker.
  Do not use for ordinary implementation, open-ended brainstorming, single-pass QA, or loops that lack a stable eval/rubric contract.
---

# Goal-Seeking Eval Loop

Use this skill when the work should behave like a bounded optimization campaign:

```text
fixed eval set -> mutate target -> run eval -> score -> keep/discard -> post-mortem -> repeat
```

This is orchestration guidance, not a new framework. Keep domain logic in the target repo. Use Codex subagents only when explicitly allowed. Use one scalar score plus hard gates so each cycle has a legible result.

## Use Only When

All of these are true:

- the user wants iterative improvement, goal seeking, autoresearch-style work, or eval-led mutation;
- a fixed eval set can be written before the first mutation;
- a scalar score and binary hard gates can be evaluated each cycle;
- the orchestrator is allowed to keep, discard, or revise mutations based on the score;
- there is a max cycle budget or explicit stop condition.

Use ordinary implementation, `loop-orchestration`, `dx-loop`, `dx-review`, or `implementation-planner` when the work lacks this eval contract.

## DX Contract

Before mutable work:

1. Create or identify the Beads epic/task for the campaign.
2. Create a worktree for every repo that may be edited.
3. Record `Feature-Key: bd-...` in prompts, artifact metadata, commits, and PRs.
4. Define the final acceptance gate and hard gates.
5. Define where run artifacts will live.

Do not write in canonical clones. Do not mutate the eval set to flatter a candidate. Do not silently downgrade requested subagent models. If the requested model is unavailable, stop with a clear blocker or ask for an override.

## Core Contract

Write a loop spec before dispatching agents:

1. **Goal**: one sentence describing the product or engineering outcome.
2. **Eval set**: fixed cases that represent success.
3. **Eval set version/hash**: a stable identifier for the cases and rubric.
4. **Mutable surface**: files, services, prompts, data paths, schemas, data sources, or UI layers the orchestrator may change.
5. **Frozen surface**: evaluation harness, scoring rules, secrets rules, production safety rules, and explicit out-of-scope areas.
6. **Scalar score**: one number per run, normally 0-100.
7. **Score dimensions**: dimensions that sum to the scalar score.
8. **Hard gates**: failures that override score.
9. **Final acceptance criteria**: exact pass condition for the campaign.
10. **Keep/discard rule**: what makes a mutation worth keeping.
11. **Loop budget**: max cycles or stop condition.
12. **Subagent budget**: max concurrent subagents, model, reasoning effort, and ownership boundaries.
13. **Artifact root**: location for logs, score JSON, prompts, diffs, commands, and post-mortems.

If any item is missing, write the spec before dispatching agents.

## Defaults

Use these defaults unless the user overrides them:

- implementation model: `gpt-5.3-codex`
- reasoning effort: `medium`
- max concurrent implementation subagents: `2`
- max concurrent evaluator subagents: `1`
- total concurrent subagent cap: `3`
- max cycles: `10`
- max mutation surfaces per cycle: `2`
- keep threshold: score improves by at least `5` points, or a hard gate is closed without a material regression
- artifact root:
  - repo-committed planning/evidence: `docs/evals/<feature-key>/`
  - local run logs: `/tmp/goal-seeking-eval-loop/<feature-key>-<timestamp>/`

For high-risk work, reduce concurrency and increase review depth. For independent implementation surfaces, the user may raise the cap.

## Final Acceptance

Final acceptance must be written before the first mutation. It must include:

- required eval cases or slice count;
- minimum aggregate score;
- minimum approved/successful cases;
- live/manual checks, if required;
- hard gates that must be zero;
- maximum tolerated unclassified failures, normally `0`;
- what happens when the gate fails.

Example:

```text
Final gate:
- run 5 fixed vertical slices
- average score >= 80
- at least 3/5 approved outputs
- at least 1 quant-ready output
- no unclassified failures
- no hard gate failures
- manual admin verification passes
- if the gate fails, run another cycle targeting the dominant blocker
```

## Loop Shape

Each cycle must include a post-mortem before the next plan:

```text
1. Establish or load baseline score.
2. Read the previous cycle post-mortem.
3. Diagnose the dominant blocker from eval output.
4. Choose one or two mutation targets.
5. Dispatch subagents by outcome, if allowed and useful.
6. Integrate and review changes.
7. Rerun the fixed eval set, or failed cases plus required regressions.
8. Keep if the keep rule passes and no hard gate regresses.
9. Discard, revise, or open a focused repair task if it fails.
10. Write the cycle post-mortem.
11. Write the next-cycle plan.
12. Stop when the final gate passes, the loop budget expires, or a strategic blocker appears.
```

Do not count a cycle as progress unless it produces a scored delta and a keep/discard decision.

## Post-Mortem Template

```markdown
## Cycle N Post-Mortem

### Score Delta
- before:
- after:
- kept/discarded:

### What Improved

### What Regressed

### Dominant Blocker

### Root Cause

### Mutation Chosen For Cycle N+1

### Why This Mutation Should Improve The Score

### Regression Cases To Rerun

### Stop Or Strategy Questions
```

If two consecutive cycles fail to improve the same blocker, change strategy instead of repeating a similar mutation.

## Scoring Rules

Prefer 100-point rubrics with 4-7 dimensions. Dimensions must sum to the top-level score. If JSON results provide `dimensions` and omit `score`, use `scripts/aggregate_scores.py` to compute the score from dimension values.

Example:

```text
score / 100:
- 20 data coverage and provenance
- 15 adapter or contract fidelity
- 25 product output validity
- 15 citation/reviewer grounding
- 15 persistence/admin visibility
- 10 public/HITL readiness or classified diagnostic
```

Hard gates are binary. Examples:

- unclassified failure;
- fixture-only proof for a live-data gate;
- missing provenance for material claims;
- bypassing the canonical path;
- unsafe secret access;
- static/demo output used as product proof;
- mocked model used for final acceptance when live behavior is required.

## Subagent Dispatch

Use subagents only when the user explicitly allows them. The orchestrator owns architecture, final integration, final acceptance, commit, PR, and merge decisions.

Recommended ownership:

- worker agents: bounded mutations to disjoint outcomes;
- evaluator agents: inspect eval output and classify blockers;
- orchestrator: choose mutation targets, integrate, resolve conflicts, rerun final gates, and write the next decision surface.

Subagent prompt skeleton:

```text
You are a Codex implementation subagent for <feature-key>.

Goal:
<one-sentence goal>

Current eval state:
- eval_set_version: <version/hash>
- current_score: <score>
- dominant_blocker: <blocker>
- final_gate: <gate>
- hard_gates: <list>

Ownership:
- repo/worktree: <path>
- owned outcome: <outcome>
- allowed files/surfaces: <surfaces>
- forbidden surfaces: <surfaces>

Task:
Implement one mutation that should improve <blocker>.

Validation:
<commands>

Artifacts to return:
- changed files
- commands run
- score evidence, if available
- risks/regressions

Rules:
- do not edit canonical clones
- do not change the eval set/rubric
- do not overlap with other agents' owned surfaces
- commit only if instructed by the orchestrator
```

If the Codex runtime subagent tool is unavailable, use the repo's governed dispatch surface (`dx-loop` or `dx-runner`) or run the cycle directly. Do not pretend a delegated loop ran.

## Strategic Blockers

Stop and surface a decision when any of these appear:

- final gate depends on product judgment that cannot be inferred from existing docs;
- the eval set is invalid or no longer represents the goal;
- the next mutation requires a new external service, schema rewrite, paid resource, or production-risk decision;
- required live data/auth is unavailable under the agent-safe secret rules;
- repeated cycles show the chosen architecture cannot plausibly reach the gate;
- two independent evaluators disagree on whether a hard gate is closed.

Tactical bugs, low/medium risk refactors, and ordinary test failures are not strategic blockers; fix them inside the loop.

## Artifacts

Initialize artifacts before the baseline run:

```bash
python3 extended/goal-seeking-eval-loop/scripts/init_run_artifacts.py \
  /tmp/goal-seeking-eval-loop/bd-xxxx-$(date -u +%Y%m%dT%H%M%SZ) \
  --goal "Improve canonical pipeline output quality" \
  --feature-key bd-xxxx \
  --eval-set-version evs-001@<hash> \
  --score-rubric-version rubric-v1 \
  --worktree /tmp/agents/bd-xxxx/repo
```

Recommended layout:

```text
<artifact-root>/
  run.json
  baseline/
    command.txt
    results.json
    logs/
  cycles/
    001/
      plan.md
      prompts/
      commands.txt
      score.json
      postmortem.md
      diff.patch
      logs/
  final/
    summary.md
    final_score.json
```

Use `scripts/aggregate_scores.py` for deterministic aggregation:

```bash
python3 extended/goal-seeking-eval-loop/scripts/aggregate_scores.py results.json \
  --min-average 80 \
  --min-approved 3 \
  --require-no-hard-gates \
  --require-eval-version evs-001
```

## Autoresearch And Gas City

Prefer Codex-native loops when:

- the mutation target is repo code, prompts, tests, data fixtures, or docs;
- the orchestrator needs direct code review and git integration;
- subagents should stay inside Codex/DX governance.

Consider external harnesses when:

- the main work is black-box prompt/model optimization;
- the eval function is already a stable scalar;
- the candidate space is large and mostly parameterized;
- cross-model optimizer agents are desired outside Codex.

Use [resources/autoresearch.md](resources/autoresearch.md) and [resources/gascity.md](resources/gascity.md) for mapping a Codex loop to those harnesses.

## Affordabot Example

For Affordabot data-moat/economic-analysis campaigns, use [resources/affordabot.md](resources/affordabot.md). The critical rule is that the data moat is not proven until real structured or unstructured evidence flows through the canonical economic analysis path and becomes reviewable in admin/HITL surfaces.

## Output Contract

When using this skill, return:

- `GOAL`
- `EVAL_SET_VERSION`
- `FINAL_GATE`
- `MUTABLE_SURFACES`
- `FROZEN_SURFACES`
- `SUBAGENT_BUDGET`
- `ARTIFACT_ROOT`
- `CURRENT_SCORE`
- `NEXT_MUTATION`
- `STOP_CONDITION`
