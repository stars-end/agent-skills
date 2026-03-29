## dx-loop Default Execution Surface

For this repo:
- use `dx-loop` first for chained Beads work, multi-step outcomes, and tasks expected to need implement -> review baton flow
- use direct/manual implementation only for isolated single-task work or when `dx-loop` itself is the active blocker
- if `dx-loop` is the blocker, stop with a truthful blocker report and track the control-plane issue under the separate `dx-loop` Beads epic rather than folding it into the product epic

This keeps product work and orchestration work distinct while making `dx-loop` the canonical low-overhead path for non-trivial execution.
