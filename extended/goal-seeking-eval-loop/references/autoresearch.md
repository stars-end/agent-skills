# Autoresearch Pattern

Use this reference when adapting the `~/autoresearch` method to another domain.

## Pattern To Borrow

`~/autoresearch` is not a generic framework. It is useful because it has a
clear loop discipline:

```text
fixed eval harness
single mutable target
scalar metric
run experiment
keep improvement
discard regression
repeat
```

Important ideas:

- Keep eval fixed.
- Make the metric comparable across runs.
- Record every experiment.
- Keep only changes that improve the metric without unacceptable complexity.
- Prefer simplification wins.
- Do not stop just because a loop completed; stop on gate pass, budget, or
  blocker.

## Adaptation Rule

Translate the pattern, not the code.

For product or pipeline work, the mutable target may be multiple layers, but
each iteration should still mutate only one or two dominant blockers.

Use hard gates when a scalar score could hide invalid output.
