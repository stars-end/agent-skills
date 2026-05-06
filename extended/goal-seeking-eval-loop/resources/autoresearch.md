# Autoresearch Mapping

Autoresearch-style systems are useful when the candidate mutation space can be reduced to a stable optimization problem:

```text
candidate -> run fixed eval -> scalar score -> keep/discard -> mutate again
```

Use Codex-native goal-seeking first when the mutation is mostly code, repo wiring, data schemas, or product pipeline behavior. Use Autoresearch-style harnesses when the mutation is mostly prompt/model/search parameter optimization and the eval is already deterministic enough to run outside the repo.

## Mapping

| Goal-Seeking Skill | Autoresearch Equivalent |
| --- | --- |
| goal | objective |
| eval set | benchmark cases |
| eval set version/hash | benchmark version |
| scalar score | reward/fitness |
| hard gates | invalid-candidate filters |
| mutable surface | candidate parameter space |
| keep/discard rule | selection rule |
| post-mortem | run analysis |
| final gate | stop condition |

## Handoff Checklist

- The eval set is frozen and versioned.
- The score can be computed without human interpretation.
- Hard gates can be detected automatically or by a bounded evaluator.
- Candidate mutations are parameterized.
- Run artifacts include candidate config, score, logs, and rejected-candidate reasons.

If these are not true, keep the work in Codex until the harness contract exists.
