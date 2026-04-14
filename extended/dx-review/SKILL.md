---
name: dx-review
description: Dispatch a low-friction review quorum through dx-review: native Claude Code Opus plus cc-glm GLM-5, with OpenCode GLM-5.1 as fallback and optional Gemini as a third reviewer. Use when the user asks for multi-model review, review quorum, Claude Code + GLM review, or a quick POC of reviewer lanes.
tags: [workflow, review, dispatch, claude-code, cc-glm, opencode, dx-runner]
allowed-tools:
  - Bash
---

# dx-review

`dx-review` is the minimal review quorum wrapper over `dx-runner`. It launches:

- `claude-code-review`: native Claude Code CLI with Opus
- `cc-glm-review`: GLM-5 through the cc-glm wrapper
- `opencode-review`: fallback GLM transport with `zhipuai/glm-5.1`, launched only if `cc-glm-review` fails at start/preflight
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
- effective logical quorum status (`2/2 completed, 0 failed`)
- raw provider outcomes, including any failed fallback attempts
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
- `cc-glm-review` is the primary GLM lane for `dx-review`.
- `opencode-review` is the GLM fallback lane, not a default second GLM reviewer.
- OpenCode fallback model is `zhipuai/glm-5.1`.
- Claude Code review model is `opus`.
- Gemini is optional and should not block the default two-reviewer path.
- Start-time provider failures are terminal for that provider attempt and should
  be reported as `start_failed`, not polled until timeout. If the failed provider
  is `cc-glm-review`, `dx-review` launches `opencode-review` as the GLM fallback.
- A review run that exits 0 with no mutations is expected. `dx-review` summarizes
  that as `review_completed` while preserving the raw `dx-runner` JSON.
- Read-only review enforcement is provider-specific best effort. Summaries should
  report `READ_ONLY_ENFORCEMENT` as:
  - `provider_enforced`
  - `contract_only`
  - `unavailable`

## Failure Handling

- If `claude-code-review` fails preflight, check Claude Code auth/model availability with `dx-runner preflight --profile claude-code-review --worktree <path>`.
- If `cc-glm-review` fails preflight, `dx-review run` tries `opencode-review` once as GLM fallback. Check `dx-runner preflight --profile cc-glm-review --worktree <path>` before debugging OpenCode.
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
