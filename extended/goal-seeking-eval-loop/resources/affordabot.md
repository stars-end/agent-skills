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

## Mutable Surfaces

The orchestrator may mutate:

- structured source targeting and extraction;
- unstructured discovery, crawl, extraction, and provenance capture;
- source catalog and jurisdiction profiles;
- evidence package schema and adapter code;
- economic analysis prompt/schema/reviewer behavior;
- persistence and read models needed for glassbox verification;
- admin and public surfaces needed to inspect real outputs.

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
