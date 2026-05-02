---
name: dx-review
description: Dispatch a low-friction review quorum through dx-review: OpenCode Kimi K2.6 and DeepSeek V4 Pro lanes only. Use when the user asks for multi-model review, Kimi/DeepSeek review quorum, or a quick POC of reviewer lanes.
tags: [workflow, review, dispatch, opencode, kimi, deepseek, dx-runner]
allowed-tools:
  - Bash
---

# dx-review

`dx-review` is the minimal review quorum wrapper over `dx-runner`. It launches:

- `opencode-go-kimi-review`: OpenCode lane pinned to `opencode-go/kimi-k2.6`
- `opencode-go-deepseek-review`: OpenCode lane pinned to `opencode-go/deepseek-v4-pro`

Use it when the desired outcome is independent review feedback, not implementation. It should stay thin: provider health, model pinning, logs, reports, and failure taxonomy belong in `dx-runner`.

The Kimi and DeepSeek lanes start in parallel. A slow or failed provider must not
block the other reviewer from launching.

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

`doctor` checks both default OpenCode review profiles and lets `dx-runner` perform safe
worktree preparation such as `mise trust` before strict provider preflight.

After reviewers complete, generate the merged artifact:

```bash
dx-review summarize --beads bd-xxx
```

Expected summarize output includes:
- effective usable-review quorum status (`2/2 completed, 0 failed` by default)
- raw/process provider outcomes, including any failed fallback attempts
- `process_success`, `review_success`, and `usable_review` so process exit 0
  is not confused with a usable review body
- per-reviewer state/verdict/failure signals
- findings counts
- token/cost usage when available
- mutation count/warnings in read-only runs
- log/report/review-body paths

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

- `opencode-go-kimi-review` is the first default review lane.
- `opencode-go-deepseek-review` is the second default review lane.
- The only default dx-review models are `opencode-go/kimi-k2.6` and `opencode-go/deepseek-v4-pro`.
- `cc-glm-review`, `gemini-burst`, and `claude-code-review` are not part of the default `dx-review` quorum.
- Start-time provider failures are terminal for that provider attempt and should
  be reported as `start_failed`, not polled until timeout.
- A review run that exits 0 with no mutations can be a valid process result, but
  it only counts toward quorum when `dx-review summarize` can find the explicit
  reviewer schema (`VERDICT` and `FINDINGS_COUNT`, or equivalent structured JSON).
  Human-readable prose without that schema is useful context but not quorum.
- Empty process success is summarized as `review_unusable` with
  `usable_review=false` and `review_status_reason=missing_review_schema`.
- A manually stopped or timed-out lane is summarized as `timeout_manual_stop`
  and does not count as a usable review.
- Read-only review enforcement is provider-specific best effort. Summaries should
  report `READ_ONLY_ENFORCEMENT` as:
  - `provider_enforced`
  - `contract_only`
  - `not_enforced`

## Failure Handling

- If either OpenCode review lane fails preflight, check `opencode models` and
  `dx-runner preflight --profile opencode-go-kimi-review --worktree <path>` or
  `dx-runner preflight --profile opencode-go-deepseek-review --worktree <path>`.
- If an OpenCode lane reports `opencode_mise_untrusted`, run the exact `mise trust '<path>'` command emitted by preflight.
- `beads-mcp binary: MISSING` is an expected warning on hosts without the optional Beads MCP helper. It does not block the fallback OpenCode review lane unless a profile explicitly escalates `beads_mcp_missing` to error.
- Do not retry repeatedly. One retry after fixing auth/tooling is enough.
- Use `dx-runner report --beads <bd-id>.<reviewer> --format json` as the source of truth for logs and outcomes.

## Session Discovery Note

After baseline or skill updates, already-running agent sessions may not advertise
new skill entries immediately. If `dx-review` behavior changed but session skill
discovery still looks stale, refresh or start a new session before debugging local
CLI installation.
