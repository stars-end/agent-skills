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
  --pr https://github.com/<owner>/<repo>/pull/<n> \
  --template code-review \
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

After reviewers complete, generate the merged artifact:

```bash
dx-review summarize --beads bd-xxx
```

Expected summarize output includes:
- final quorum status (`2/2 completed, 0 failed`)
- per-reviewer state/verdict/failure signals
- findings counts
- token/cost usage when available
- log/report paths

## Template Contract

`dx-review` templates are inbound reviewer contracts, not outbound implementation prompts.

Available templates:
- `smoke`
- `code-review`
- `architecture-review`
- `arch-review` (alias for `architecture-review`)
- `security-review`

Template assets:
- `templates/dx-review/*.md`
- `templates/dx-review/contracts/*.md`

Review templates must not request PR creation, commits, pushes, or code fixes.

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
- Read-only review enforcement is provider-specific best effort. Summaries should
  report `READ_ONLY_ENFORCEMENT` as:
  - `provider_enforced`
  - `contract_only`
  - `unavailable`

## Failure Handling

- If `claude-code-review` fails preflight, check Claude Code auth/model availability with `dx-runner preflight --profile claude-code-review --worktree <path>`.
- If `opencode-review` fails preflight, check `opencode models` and `dx-runner preflight --profile opencode-review --worktree <path>`.
- If OpenCode reports `opencode_mise_untrusted`, run `dx-review doctor --worktree <path>` first; if it still fails, run the exact `mise trust '<path>'` command emitted by preflight.
- `beads-mcp binary: MISSING` is an expected warning on hosts without the optional Beads MCP helper. It does not block the default OpenCode review lane unless a profile explicitly escalates `beads_mcp_missing` to error.
- Do not retry repeatedly. One retry after fixing auth/tooling is enough.
- Use `dx-runner report --beads <bd-id>.<reviewer> --format json` as the source of truth for logs and outcomes.

## Session Discovery Note

After baseline or skill updates, already-running agent sessions may not advertise
new skill entries immediately. If `dx-review` behavior changed but session skill
discovery still looks stale, refresh or start a new session before debugging local
CLI installation.
