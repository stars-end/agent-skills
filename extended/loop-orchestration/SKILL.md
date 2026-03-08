---
name: loop-orchestration
description: |
  Orchestrate Codex-first implementation loops built around `dx-runner` dispatch, bounded sleep intervals, status checks, review passes, and deterministic re-dispatch.
  Use when a live session should repeatedly dispatch work, wait, inspect `dx-runner` state, review outcomes, and continue until merge-ready or blocked.
  Invoke when users mention "poll every 5m", "check this runner repeatedly", "sleep loop", "babysit this PR", "re-dispatch round N", "keep checking until merge-ready", or "build a loop orchestrator". `/loop` is only a prototype model for the desired behavior, not the required runtime surface.
---

# loop-orchestration

Use this skill to build a Codex-first operator loop around `dx-runner`.

This skill is still session-bound. If the session ends, the operator loop ends.

## Purpose

Turn an operator request into:
- one `dx-runner` dispatch step
- one sleep cadence
- one check/review policy
- one re-dispatch or merge-ready policy

Keep the loop narrow. It should check status, classify the result, and either stay quiet or surface a decision.

## Workflow

### 1. Define the run target

Choose one target only:
- `dx-runner` job
- PR checks for the resulting branch or PR
- deployment
- bounded implement/review wave backed by `dx-runner`

Do not mix multiple unrelated targets in one loop.

### 2. Define the control cycle

The default cycle is:
1. dispatch with `dx-runner start`
2. sleep for the chosen interval
3. inspect with `dx-runner check --json`
4. inspect outcome with `dx-runner report --format json` when needed
5. review whether to:
   - continue waiting
   - prepare a fix redispatch
   - surface a blocker
   - declare merge-ready

Use the prototype functional requirements in [references/loop-prompt-template.md](/tmp/agents/bd-3l12.9/agent-skills/extended/loop-orchestration/references/loop-prompt-template.md).

### 3. Define the interrupt policy

Default policy:
- stay quiet while healthy and still progressing
- surface only on `needs_decision`
- surface on `blocked`
- surface on `merge_ready`

Optional policy:
- allow low-noise heartbeat only when the user explicitly asks for it

### 4. Define the redispatch boundary

Allow re-dispatch only when:
- the next action is deterministic
- the retry is bounded
- the fix context is already available

Do not auto-redispatch semantic fixes unless the user explicitly asks for that behavior.

### 5. Write the Codex loop prompt

The prompt should always include:
- the initial `dx-runner` dispatch artifact
- the polling interval
- the `dx-runner` beads id
- what to inspect each cycle
- what counts as healthy
- what counts as blocked
- what event should interrupt the user

The output should be a Codex-facing orchestration prompt, not a Claude `/loop` command.

If the user wants a deterministic scaffold, use [scripts/render_loop_prompt.py](/tmp/agents/bd-3l12.9/agent-skills/extended/loop-orchestration/scripts/render_loop_prompt.py) to generate the first draft and then tighten it for the specific repo and wave.

### 6. Run a bounded POC first

Before relying on the loop for real work, run one of the test scenarios in [references/prime-radiant-poc-tests.md](/tmp/agents/bd-3l12.9/agent-skills/extended/loop-orchestration/references/prime-radiant-poc-tests.md).

Start with:
- `dx-runner` dispatch + sleep + check
- PR watch after dispatch
- one bounded re-dispatch scenario

## Guardrails

- Keep intervals at `5m` or longer unless there is a real operational need.
- Do not use the loop as a substitute for repo policy.
- Do not assume the loop is durable; it is only valid while the session stays open.
- Treat the loop as operator assistance, not a source of truth.
- Use `dx-runner` as the source of machine state.

## Output Contract

When using this skill, produce:
- one Codex-ready orchestration prompt
- one concrete sleep cadence
- one sentence explaining why the cadence is appropriate
- one sentence stating the interrupt policy
- optional test scenario recommendation

## Script Usage

Generate a starter prompt with:

```bash
python3 extended/loop-orchestration/scripts/render_loop_prompt.py \
  --beads bd-xxxx \
  --interval 600 \
  --provider opencode \
  --target "Prime Radiant V2 fix wave"
```

Add `--pr 123` when the loop should transition into PR babysitting after dispatch.

## Codex Reload

Creating this skill under `~/agent-skills` does not make it auto-available in the current session or in Codex desktop until it is installed and the session is refreshed.

Assume a new Codex session or skill refresh is required before this skill can auto-trigger by name.
