# Affordabot Data-Moat Example

Use this reference when the campaign is about proving Affordabot's data moat as a foundation for economic analysis.

## North Star

Affordabot should surface credible cost-of-living impacts from California local regulations, ordinances, meeting actions, mandates, and indirect policy constraints. The data moat is foundational only if evidence can reach the economic analysis engine and become reviewable in admin/HITL surfaces.

## Canonical Vertical Path

```text
structured + unstructured evidence
  -> EconomicHandoffPackage
  -> canonical adapter
  -> LegislationResearchResult
  -> AnalysisPipeline.run_from_evidence_package
  -> LegislationAnalysisResponse + ReviewCritique
  -> persisted run/evidence/review records
  -> admin glassbox/HITL review
  -> public dynamic impact surface
```

Do not count a data slice as accepted if it bypasses the economic analysis path.

## Fixed Eval Set Shape

A five-slice campaign should include different jurisdiction/source-family combinations, for example:

- fees or utility rates with numeric tables;
- zoning or parking rules that plausibly affect housing cost;
- permits or inspections with operational burden;
- meeting minutes or agenda actions with policy lineage;
- licensing, mandates, or staffing requirements with indirect cost channels.

The exact jurisdictions can change before the eval set is frozen. After freeze, record the eval set version/hash and do not swap cases to make the score look better.

For a path-proving campaign, two representative slices can be acceptable when
the goal is to prove a deep canonical path before broadening. In that case:

- label the goal as `PATH_PROVING`;
- require one structured-heavy and one unstructured-policy-heavy slice;
- keep the remaining diagnostic slices as breadth/regression guards;
- do not claim full moat durability when only two slices pass;
- require the next durability campaign to expand the live-bound quorum to at
  least four or five slices.

This avoids two bad extremes: mutating the whole pipeline to overfit two cases,
or broadening to more cases before the canonical path can persist and explain
even one structured and one unstructured slice.

## Suggested Final Gate

```text
- 5 fixed real vertical slices run through the canonical path
- average score >= 80
- at least 3/5 slices approved for economic-analysis quality
- at least 3/5 slices have official-source provenance and persisted evidence pointers
- at least 1 slice is quant-ready with numeric evidence usable by the analysis engine
- 0 unclassified failures
- 0 fixture-only, mock-only, or bridge-bypass successes
- admin glassbox shows evidence, model output, review critique, and failure classification for each slice
- at least 1 public/frontend route renders dynamic persisted analysis output
```

For a two-slice path-proving campaign, use a narrower final gate:

```text
- 2 fixed representative slices run through the canonical path
- one structured-heavy slice and one unstructured-policy-heavy slice are present
- average score >= 80
- per-slice score >= 70
- 2/2 slices approved
- at least 1 slice is approved_quant_ready
- approved_live_bound_with_gaps only allows analytical depth/coverage gaps,
  never provenance, storage, runtime, identity, or truth-ownership gaps
- remaining diagnostic slices have no source-grounding or refusal regression
- 0 unclassified failures
- 0 fixture-only, mock-only, or bridge-bypass successes
- admin/HITL and public trust surfaces expose missing inputs and refusals
```

Passing this gate proves the canonical live path, not full moat durability.

## Mutable Surfaces

The orchestrator may mutate:

- structured source targeting and extraction;
- unstructured discovery, crawl, extraction, and provenance capture;
- source catalog and jurisdiction profiles;
- evidence package schema and adapter code;
- economic analysis prompt/schema/reviewer behavior;
- persistence and read models needed for glassbox verification;
- admin and public surfaces needed to inspect real outputs.

Choose mutations from the dominant blocker, not from a fixed phase plan:

- data/source blocker -> mutate structured/unstructured source strategy or extraction;
- adapter blocker -> mutate evidence package, canonical adapter, or handoff schema;
- persistence blocker -> mutate Postgres, MinIO, pgvector-ready refs, idempotency, or Windmill evidence refs;
- analysis blocker -> mutate mechanism classification, parameter tables, prompts, reviewer behavior, sensitivity, or refusal logic;
- verification blocker -> mutate admin/HITL or public trust surfaces.

## Frozen Surfaces

Keep these stable during a campaign unless the user approves a new plan:

- eval set after freeze;
- scoring rubric after freeze;
- secret-auth safety rules;
- Railway topology and canonical storage targets;
- no canonical repo writes;
- hard gates.

## Hard Gates

Fail a slice if:

- evidence does not come from an official or explicitly validated source;
- numeric claims lack provenance;
- final proof uses fixtures, mocks, or static demo records;
- the economic analysis path is bypassed;
- model output is not persisted with review critique;
- admin/HITL cannot inspect the evidence and output;
- the failure reason is unclassified.

## Score Dimensions

Example 100-point rubric:

- 20 evidence breadth and official provenance;
- 15 extraction depth and field completeness;
- 15 handoff/adapter contract fidelity;
- 20 economic analysis validity and conservatism;
- 10 citation/reviewer grounding;
- 10 persistence and lineage visibility;
- 10 admin/public verification readiness.

Use the dominant blocker from failed slices to choose the next mutation. If the economic analysis fails, classify whether the root cause is evidence quality, adapter mismatch, model/prompt behavior, missing quantitative method, or admin persistence/read-model gaps.
