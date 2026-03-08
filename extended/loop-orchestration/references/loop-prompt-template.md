# Loop Functional Template

Use this template when the user wants Codex to emulate `/loop` behavior inside a live session with `dx-runner` as the execution substrate.

```text
Dispatch the target below with `dx-runner`, then run a recurring control cycle with a sleep interval.

Target:
- Kind: <dx-runner implementation wave | PR watch | deployment watch>
- Identifier: <beads id / PR number / deployment id>
- Initial dispatch: <exact dx-runner start command if applicable>

Each cycle:
1. Sleep for <interval>.
2. Inspect the current status of the target.
3. Compare it with the previous known state.
4. If the target is still healthy and making progress, do not interrupt.
5. If the target is merge-ready, blocked, or needs a human decision, interrupt with:
   - current state
   - why it changed
   - exact next action
6. If a deterministic re-dispatch is allowed, prepare the re-dispatch prompt and say so.
7. Otherwise wait for human instruction.

Interrupt conditions:
- `merge_ready`
- `blocked`
- `needs_decision`

Silence conditions:
- checks still pending
- runner still healthy
- no material status change

Boundaries:
- Do not expand scope.
- Do not create new work items unless explicitly instructed.
- Do not merge automatically.
```

Adapt the interval upward when:
- checks are slow
- the system is queue-bound
- the user wants low interruption cost

Adapt the interval downward only when:
- there is a short-lived deployment check
- there is an active failure being triaged

Treat `/loop` as the product reference for expected behavior:
- recurring cadence
- quiet while healthy
- interrupt on material state change
- bounded retries

Do not require `/loop` as the runtime implementation.
