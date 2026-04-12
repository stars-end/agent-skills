---
name: dx-review
description: Dispatch a low-friction review quorum through dx-review: native Claude Code Opus plus OpenCode GLM-5.1, with optional Gemini as a third reviewer. Use when the user asks for multi-model review, review quorum, Claude Code + OpenCode review, or a quick POC of reviewer lanes.
tags: [workflow, review, dispatch, claude-code, opencode, dx-runner]
allowed-tools:
  - Bash
---

# dx-review

`dx-review` is the minimal review quorum wrapper over `dx-runner`. It launches:

- `claude-code-review`: native Claude Code CLI with Opus
- `opencode-review`: OpenCode with `zhipuai/glm-5.1`
- optional `gemini-burst`: Gemini CLI, opt-in only with `--gemini`

Use it when the desired outcome is independent review feedback, not implementation. It should stay thin: provider health, model pinning, logs, reports, and failure taxonomy belong in `dx-runner`.

The default reviewers start in parallel. A slow or failed provider must not block
the other reviewer from launching.

## Required Shape

Always pass a real worktree. Do not run review jobs from canonical repos.

```bash
dx-review run \
  --beads bd-xxx \
  --worktree /tmp/agents/bd-xxx/repo \
  --prompt-file /tmp/review.prompt \
  --wait
```

For a one-line smoke test:

```bash
dx-review run \
  --beads bd-xxx \
  --worktree /tmp/agents/bd-xxx/repo \
  --prompt "Answer exactly REVIEW_READY." \
  --wait
```

Before a live review on a new worktree, run:

```bash
dx-review doctor --worktree /tmp/agents/bd-xxx/repo
```

`doctor` checks both default review profiles and lets `dx-runner` perform safe
worktree preparation such as `mise trust` before strict provider preflight.

## Provider Contract

- Claude Code is the `claude-code` provider, not `cc-glm`.
- `cc-glm` remains the Z.ai/GLM wrapper lane.
- OpenCode review model is `zhipuai/glm-5.1`.
- Claude Code review model is `opus`.
- Gemini is optional and should not block the default two-reviewer path.
- Start-time provider failures are terminal for the current review run and should
  be reported as `start_failed`, not polled until timeout.
- A review run that exits 0 with no mutations is expected. `dx-review` summarizes
  that as `review_completed` while preserving the raw `dx-runner` JSON.

## Failure Handling

- If `claude-code-review` fails preflight, check Claude Code auth/model availability with `dx-runner preflight --profile claude-code-review --worktree <path>`.
- If `opencode-review` fails preflight, check `opencode models` and `dx-runner preflight --profile opencode-review --worktree <path>`.
- If OpenCode reports `opencode_mise_untrusted`, run `dx-review doctor --worktree <path>` first; if it still fails, run the exact `mise trust '<path>'` command emitted by preflight.
- Do not retry repeatedly. One retry after fixing auth/tooling is enough.
- Use `dx-runner report --beads <bd-id>.<reviewer> --format json` as the source of truth for logs and outcomes.
