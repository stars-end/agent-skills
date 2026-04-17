---
name: dx-review
description: Dispatch a low-friction review quorum through dx-review: cc-glm GLM-5.1 primary, OpenCode GLM-5.1 fallback, plus Gemini as the second default lane. Use when the user asks for multi-model review, GLM-focused review quorum, or a quick POC of reviewer lanes.
tags: [workflow, review, dispatch, cc-glm, opencode, gemini, dx-runner]
allowed-tools:
  - Bash
---

# dx-review

`dx-review` is the minimal review quorum wrapper over `dx-runner`. It launches:

- `cc-glm-review`: primary GLM lane through the cc-glm wrapper
- `opencode-review`: fallback GLM lane with `zhipuai/glm-5.1`, launched only if `cc-glm-review` fails at start/preflight
- `gemini-burst`: Gemini CLI second default lane

Use it when the desired outcome is independent review feedback, not implementation. It should stay thin: provider health, model pinning, logs, reports, and failure taxonomy belong in `dx-runner`.

The GLM and Gemini lanes start in parallel. A slow or failed provider must not
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

`doctor` checks both default review profiles and lets `dx-runner` perform safe
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

- `cc-glm-review` is the primary GLM lane for `dx-review`.
- `opencode-review` is the GLM fallback lane, not a default second GLM reviewer.
- OpenCode fallback model is `zhipuai/glm-5.1`.
- Gemini is the second default lane.
- Start-time provider failures are terminal for that provider attempt and should
  be reported as `start_failed`, not polled until timeout. If the failed provider
  is `cc-glm-review`, `dx-review` launches `opencode-review` as the GLM fallback.
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

- If `cc-glm-review` fails preflight, `dx-review run` tries `opencode-review` once as GLM fallback. Check `dx-runner preflight --profile cc-glm-review --worktree <path>` before debugging OpenCode.
- `cc-glm-review` preflight must exercise the same `cc-glm-headless`
  token-resolution path as live runs. A Z.ai secret failure should surface as
  `secret_auth_resolution_failed_after_preflight` with a redacted
  `secret_ref_category`, not a raw secret or full `op://` URI.
- If `opencode-review` fallback fails preflight, check `opencode models` and `dx-runner preflight --profile opencode-review --worktree <path>`.
- If OpenCode fallback reports `opencode_mise_untrusted`, run the exact `mise trust '<path>'` command emitted by preflight.
- `beads-mcp binary: MISSING` is an expected warning on hosts without the optional Beads MCP helper. It does not block the fallback OpenCode review lane unless a profile explicitly escalates `beads_mcp_missing` to error.
- Do not retry repeatedly. One retry after fixing auth/tooling is enough.
- Use `dx-runner report --beads <bd-id>.<reviewer> --format json` as the source of truth for logs and outcomes.

## Session Discovery Note

After baseline or skill updates, already-running agent sessions may not advertise
new skill entries immediately. If `dx-review` behavior changed but session skill
discovery still looks stale, refresh or start a new session before debugging local
CLI installation.
