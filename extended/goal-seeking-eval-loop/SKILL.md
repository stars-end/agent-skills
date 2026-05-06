---
name: goal-seeking-eval-loop
description: Run autoresearch-style goal-seeking loops for code, product, data, or pipeline improvement. Use when Codex should define a fixed eval set, scalar score, hard gates, keep/discard rule, and iterative mutation loop; when users ask for goal-seeking, eval-led iteration, "autoresearch for X", 10-20 improvement loops, dynamic pipeline tuning, or Codex-native orchestration with up to N subagents. Prefer this skill before creating custom loop frameworks; optionally map the loop to Gas City convergence when an external agent runtime is desired.
tags: [workflow, goal-seeking, evals, orchestration, codex, autoresearch]
---

# Goal-Seeking Eval Loop

Use this skill to turn fuzzy iterative improvement into a disciplined loop:

```text
fixed eval set -> mutate target -> run evaluator -> score -> keep/discard -> repeat
```

The skill is orchestration guidance, not a new framework. Keep domain logic in
the target repo, use Codex subagents only when helpful, and make the evaluator
output legible enough that each cycle knows what to improve next.

## Core Contract

Before starting implementation loops, define these artifacts:

1. **Goal**: the product or engineering outcome, in one sentence.
2. **Eval set**: fixed cases that represent success. Do not change them to
   flatter experiments.
3. **Mutable surface**: files, services, prompts, data paths, schemas, UI
   layers, or operational knobs the orchestrator may change.
4. **Frozen surface**: evaluator, scoring rules, production safety rules,
   secrets rules, and anything explicitly out of scope.
5. **Final gate**: one gate with N required criteria. Do not default to phases
   or sub-gates.
6. **Evaluator result schema**: the JSON fields required by the loop.
7. **Scalar score**: one comparable number per run, usually 0-100.
8. **Hard gates**: failures that override score.
9. **Keep/discard rule**: what makes a mutation worth keeping.
10. **Loop budget**: max cycles or stop condition.
11. **Subagent budget**: max concurrent subagents, ownership boundaries, and
    whether they may edit or only evaluate.
12. **Artifact root**: where loop logs, score JSON, commands, post-mortems, and
    manual evidence are stored.

If any item is missing, write the loop spec before dispatching agents.

## Single-Gate Rule

The default abstraction is **one final gate with N criteria**.

```text
Final gate:
- criterion A
- criterion B
- criterion C
- criterion D
```

Passing one criterion is progress only. It is not completion unless the final
gate says all criteria pass. After every cycle:

1. read evaluator `passed`;
2. if false, read `failing_criteria` and `dominant_blocker`;
3. choose one or two mutation targets that directly address the dominant
   blocker;
4. rerun the evaluator;
5. stop only when the full gate passes, budget expires, or a strategic blocker
   appears.

Use phases only when the user or domain spec explicitly asks for them. If a
domain spec uses phases, it must still say whether passing one phase means
`STOP_FOR_REVIEW` or `AUTO_CONTINUE`.

## Evaluator Result Schema

Prefer JSON that can drive the next cycle without interpretation by memory:

```json
{
  "passed": false,
  "scalar_score": 72.5,
  "dimension_scores": {
    "coverage": 18,
    "analysis": 14
  },
  "hard_gate_failures": [],
  "failing_criteria": ["analysis_below_threshold"],
  "dominant_blocker": "analysis_gap",
  "candidate_next_mutation_target": "analysis",
  "verdict": "blocked",
  "notes": "analysis lacks source-bound parameter table"
}
```

Required per-slice fields:

- `slice_id`
- `passed`
- `scalar_score` or `score`
- `dimension_scores` or `dimensions`
- `hard_gate_failures`
- `failing_criteria`
- `dominant_blocker`
- `verdict`

Optional fields:

- `candidate_next_mutation_target`
- `notes`
- `diagnostics`

Candidate mutation target is advisory. The orchestrator owns the final
`next_mutation_target` in the post-mortem/cycle plan.

Use domain-specific verdicts only in the domain spec. The generic skill
vocabulary is:

```text
approved
blocked
rejected
unclassified_failure
```

## Defaults

Use these defaults unless the user overrides them:

- **Implementation model**: `gpt-5.3-codex`
- **Reasoning effort**: `medium`
- **Max concurrent implementation subagents**: `2`
- **Max concurrent evaluator subagents**: `1`
- **Total subagent cap per loop**: `3`
- **Max cycles**: `10`
- **Max mutation surfaces per cycle**: `2`
- **Artifact root**:
  - repo work: `docs/evals/<feature-key>/` or `artifacts/evals/<feature-key>/`
  - local-only exploration: `/tmp/goal-seeking-eval-loop/<run-id>/`

For higher-risk work, lower the subagent cap and increase evaluation depth.
For broad but independent implementation surfaces, the user may raise the cap.

## Final Acceptance

Write final acceptance before the first mutation. It must include:

- required eval cases or slice count;
- minimum aggregate score;
- minimum approved/successful cases;
- required live/manual checks, if any;
- hard gates that must be resolved by final acceptance;
- maximum tolerated final unclassified failures, normally `0`;
- what happens when the full gate fails.

Example:

```text
Final gate:
- run 5 fixed vertical slices
- average scalar_score >= 80
- every slice has hard_gate_failures == []
- every non-approved slice has failing_criteria and dominant_blocker
- at least 3/5 approved outputs
- admin/API verification evidence stored
- public/manual verification evidence stored
- final unclassified_failure count == 0
- if gate fails, run another cycle targeting dominant_blocker
```

Intermediate hard gates and unclassified failures may appear while the loop is
learning. They must be classified in the next post-mortem before they can guide
a kept mutation. Final acceptance is stricter.

## Loop Shape

Use this loop:

```text
1. Establish or load baseline score.
2. Read the previous cycle post-mortem, if any.
3. Run or inspect the evaluator output.
4. Diagnose failing_criteria and dominant_blocker.
5. Choose one or two mutation targets.
6. Dispatch up to N subagents by outcome, not file.
7. Integrate and review changes.
8. Rerun eval set or failed cases plus regressions.
9. Keep if score improves, a hard gate closes, or a failure becomes more precise
   without opening a new hard gate or weakening frozen criteria.
10. Discard, revise, or open a focused repair task if it does not.
11. Write the cycle post-mortem and next-cycle plan.
12. Record score, verdict, failing criteria, hard gates, artifacts, and next
    mutation target.
13. Stop when the full final gate passes, loop budget expires, or a strategic
    blocker appears.
```

Do not run loops that only produce activity. Every loop must produce a scored
delta and a keep/discard decision.

## Stochastic Criteria

If a criterion depends on an LLM, model judge, stochastic search result, or
other non-deterministic process, do not keep or discard primarily from a single
lucky run. Before stochastic criteria affect keep/discard, use at least one:

- three or more repeats with score range recorded;
- cached identical-input replay;
- reviewer quorum from two or more independent passes;
- a deterministic proxy that the domain spec accepts.

Record the noise-control method in the cycle post-mortem. This is a loop
invariant, not a separate final-gate criterion.

## Progression And Mutation

Each cycle must be guided by the last cycle's evidence. Use this post-mortem:

```markdown
## Cycle N Post-Mortem

### Gate Status
- passed:
- failing_criteria:
- hard_gate_failures:
- dominant_blocker:

### Score Delta
- before:
- after:
- kept/discarded:

### What Improved

### What Regressed

### Root Cause

### Mutation Chosen For Cycle N+1

### Why This Mutation Should Improve The Score

### Regression Cases To Rerun

### Budget State
- cycles_used:
- max_cycles:
- budget_exhausted:

### Skill/Runbook Lessons

### Stop/Strategy Questions
```

Only mutate surfaces that plausibly address the dominant blocker, unless the
orchestrator explicitly identifies a higher-leverage pivot. If two consecutive
cycles fail to improve the same blocker, change strategy instead of repeating
similar patches.

## Scoring Rules

Use a scalar score for comparability, but never let it hide unsafe failures.
Prefer 100-point rubrics with 4-7 dimensions.

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

Hard gates should be binary. Examples:

- unclassified failure at final acceptance
- fixture-only proof for a live-data gate
- missing provenance for material claims
- bypassing the canonical path
- unsafe secret access
- static/demo output used as product proof
- mocked model used for final acceptance when live behavior is required

Use `scripts/aggregate_scores.py` when you have JSON slice results and want a
deterministic aggregate.

## Subagent Pattern

Use subagents only when the user explicitly allows them. The orchestrator keeps
architecture, final integration, and keep/discard authority.

Recommended split:

- **Worker agents**: make bounded mutations to disjoint surfaces.
- **Evaluator agents**: run or inspect eval output and classify blockers.
- **Orchestrator**: chooses mutation targets, resolves conflicts, reruns final
  gates, commits, and reports the next decision surface.

Prompt subagents with:

- goal and current score;
- eval cases and hard gates;
- owned files or owned outcome;
- forbidden surfaces;
- validation commands;
- required artifact format.

Do not let different subagents edit the same unstable surface in the same loop.

When using Codex subagents, default implementation workers to
`gpt-5.3-codex` with `medium` reasoning. Use fewer agents when ownership is not
cleanly separable. The orchestrator should not delegate final acceptance,
architecture decisions, or merge authority.

## Artifacts And Logging

Initialize an artifact directory before the baseline run. Use
`scripts/init_run_artifacts.py` for local directories, or create the same shape
inside the repo when artifacts should be committed.

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
      results.json
      aggregate.json
      postmortem.md
      logs/
      screenshots/
    002/
      ...
  final/
    report.md
    aggregate.json
```

Store enough evidence to debug without rerunning immediately:

- eval input cases and version;
- commands run;
- raw logs or links to logs;
- slice result JSON;
- aggregate score JSON;
- commit SHA or sanitized `git diff --no-color` output for kept changes;
- post-mortem and next-cycle plan;
- screenshots/manual verification artifacts when UI is involved.

Committed logs should use tracked extensions such as `.txt` or `.md`, not
extensions commonly ignored by repos such as `.log`. If storing a diff, sanitize
it or keep the commit SHA instead. Record the command working directory and keep
artifact paths relative to the repo root.

Do not store secrets. Redact tokens, cookies, API keys, and private credentials
from artifacts. Before committing artifacts, run a targeted scan for obvious
secret patterns such as `Bearer `, `op://`, `api_key`, `password`, `token`, and
long opaque credential-looking values.

## Codex-Native Vs Gas City

Use Codex-native orchestration when:

- the user wants all work inside the current Codex flow;
- the loop is exploratory or early;
- subagents are available in the current runtime;
- the orchestrator needs tight product judgment after each loop.

Use Gas City convergence later when:

- the loop needs long-running durable state outside the current Codex session;
- you need external LLM providers or non-Codex agents;
- iteration/gate state should live in Gas City artifacts and Beads;
- the workflow should continue unattended across sessions.

Gas City already provides bounded convergence loops, gates, artifacts, and
formula-based orchestration. Do not rebuild those primitives in a product repo.
This skill supplies the loop contract and domain scoring; Gas City can be one
runtime for that contract.

Read `references/gascity.md` when deciding whether to use Gas City.
Read `references/autoresearch.md` when designing the keep/discard loop.

## Output Template

When creating a loop plan, return:

```markdown
## Goal

## Eval Set

## Mutable Surface

## Frozen Surface

## Final Gate

## Evaluator Result Schema

## Score Rubric

## Hard Gates

## Keep/Discard Rule

## Subagent Plan

## Loop Budget And Stop Conditions

## Artifact Root

## Baseline Command

## Post-Mortem Template

## First Loop
```

## Domain Examples

Domain-specific verdicts should live in the domain plan, not the generic skill.
For an economic-analysis product, a domain plan might add:

```text
approved_quant_ready
approved_qualitative_only
approved_unable_to_estimate_with_source_bound_diagnosis
data_gap
adapter_gap
analysis_gap
persistence_gap
admin_gap
public_gap
model_gap
```

## Final Report

End each loop with:

- score before and after;
- kept/discarded decision;
- files or surfaces changed;
- failing criteria;
- dominant blocker;
- next mutation target;
- remaining hard-gate failures;
- budget state.

If the loop hits a strategic blocker, stop and name the single decision needed.
