# dx-review QA Report

Date: 2026-04-12
Host: Fengs-MacBook-Pro
Reporter: Codex
Scope: `dx-review` smoke/QA pass against affordabot PR #426

## Summary

`dx-review` is usable enough to launch the default two-reviewer path, but the first live run exposed several workflow failures that will confuse product agents and can leave `--wait` hanging until timeout.

Claude Code Opus successfully ran through `claude-code-review` and produced a useful code review. OpenCode GLM-5.1 did not run because the `opencode-review` preflight failed on `mise trust`. After that start failure, `dx-review --wait` kept polling the failed reviewer as `unknown` instead of treating it as a terminal start failure.

The largest product-agent risk is that `dx-review` starts reviewers serially. A slow or stuck Claude startup blocks OpenCode from even starting, so the wrapper does not behave like an actual review quorum under partial provider failure.

## Command Under Test

```bash
dx-review run \
  --beads bd-jxclm.15 \
  --worktree /tmp/agents/offline-20260412-windmill-bakeoff/affordabot \
  --prompt-file /tmp/dx-review-bd-jxclm.15.prompt \
  --wait \
  --timeout-sec 1200 \
  --poll-sec 10
```

The prompt was explicitly framed as code review only, with no file edits, commits, pushes, or secret retrieval commands.

## Target Under Review

- Repo: `stars-end/affordabot`
- Worktree: `/tmp/agents/offline-20260412-windmill-bakeoff/affordabot`
- PR: `https://github.com/stars-end/affordabot/pull/426`
- Head SHA: `ea26fbc8e67832bfc6d846d759b2b41840b85727`
- Feature key used for the smoke run: `bd-jxclm.15`

## What Worked

### `dx-review` binary and skill exist locally

`dx-review --help` worked and advertised the expected command shape.

Local skill/config discovery found:

- `extended/dx-review/SKILL.md`
- `configs/dx-runner-profiles/claude-code-review.yaml`
- `configs/dx-runner-profiles/opencode-review.yaml`
- `scripts/dx-review`
- `scripts/dx-runner`

### Claude Code review lane succeeded

Claude preflight passed:

```text
profile: claude-code-review -> provider: claude-code
claude binary: OK (claude)
headless cli flags: OK
canonical model probe: OK (opus)
=== Preflight PASSED ===
```

`dx-runner report --beads bd-jxclm.15.claude --format json` reported:

```json
{
  "provider": "claude-code",
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations",
  "duration_sec": "216",
  "exit_code": "0",
  "outcome_state": "success",
  "selected_model": "opus",
  "mutations": 0
}
```

The Claude review output was useful and correctly followed the requested review format. It found low-severity issues in the affordabot POC, including divergent `canonical_document_key` schemes, a confusing `stale_backed=true` string, a relative subprocess path in the Path A Windmill script, and the intentionally stubbed Path B Windmill script.

## Failures And Frictions

### 1. Reviewers start serially, so one slow provider blocks the quorum

Severity: High

Observed behavior:

- `dx-review` printed `starting reviewer=bd-jxclm.15.claude profile=claude-code-review`.
- It did not print `starting reviewer=bd-jxclm.15.opencode profile=opencode-review` until roughly 216 seconds later.
- During that period, the process tree showed only the Claude reviewer path:

```text
bash /tmp/dx-runner/claude-code-launcher-bd-jxclm.15.claude...
claude
bash /Users/fning/agent-skills/scripts/dx-runner start --profile claude-code-review ...
bash /Users/fning/bin/dx-review run ...
```

Impact:

- This is a review quorum wrapper, but the quorum lanes are not started independently.
- A stuck Claude auth/model/session issue can prevent OpenCode from starting at all.
- Product agents will see no OpenCode evidence even when OpenCode is healthy.

Likely cause:

- `dx-review` captures `dx-runner start` output using command substitution.
- The Claude launcher appears to keep the captured stdout/stderr pipe open until the child exits, so `dx-review` does not proceed to the next reviewer until Claude completes.

Recommended fix:

- Launch reviewer start commands in parallel or make `dx-runner start` detach without inheriting the caller's command-substitution pipe.
- At minimum, start all reviewers before waiting on any of them.

### 2. OpenCode strict preflight failed on `mise trust`

Severity: High

Observed preflight failure:

```text
profile: opencode-review -> provider: opencode
opencode binary: OK (opencode)
model availability: OK (16 models)
canonical model probe: OK (zhipuai/glm-5.1)
execution mode capability: OK (headless run)
beads-mcp binary: MISSING
  WARN_CODE=opencode_beads_mcp_missing severity=warn action=install_beads_mcp_for_richer_context
mise trust: UNTRUSTED (/private/tmp/agents/offline-20260412-windmill-bakeoff/affordabot)
  ERROR_CODE=opencode_mise_untrusted severity=error action=run_mise_trust_in_worktree target=/private/tmp/agents/offline-20260412-windmill-bakeoff/affordabot
=== Preflight FAILED (1 error(s), 1 warning(s)) ===
preflight gate failed for provider opencode
reviewer_start_failed reviewer=bd-jxclm.15.opencode profile=opencode-review rc=21
```

Impact:

- Product agents can hit this even when OpenCode itself is installed, authenticated, and has the pinned model available.
- The visible action uses `/private/tmp/...`, while agents commonly pass `/tmp/...`, which makes the trust target less obvious.
- The Claude lane emitted a related warning earlier:

```text
[bd-8wdg.11] WARN: mise trust auto-remediation failed for /private/tmp/agents/offline-20260412-windmill-bakeoff/affordabot
```

Additional observation:

- A later `mise trust --show` in the worktree reported `/private/tmp/agents/offline-20260412-windmill-bakeoff/affordabot: trusted`.
- That means either trust state changed after the failure, the preflight path canonicalization is inconsistent, or the auto-remediation/trust check has a race or stale read.

Recommended fix:

- Add a `dx-review doctor` or preflight-only command that checks both reviewer profiles before launching.
- Make `dx-review run` fail fast with a concise `mise trust` remediation command before starting any reviewer.
- Normalize `/tmp` and `/private/tmp` consistently in preflight output and trust checks.

### 3. Failed reviewer start is not treated as terminal under `--wait`

Severity: High

Observed behavior after OpenCode start failure:

```text
reviewer_start_failed reviewer=bd-jxclm.15.opencode profile=opencode-review rc=21
reviewer=bd-jxclm.15.claude state=no_op_success rc=0
reviewer=bd-jxclm.15.opencode state=unknown rc=1
reviewer=bd-jxclm.15.claude state=no_op_success rc=0
reviewer=bd-jxclm.15.opencode state=unknown rc=1
```

The wrapper continued polling `bd-jxclm.15.opencode` as `unknown`. The run had to be manually stopped after enough evidence was collected.

Impact:

- `--wait` can hang until timeout after a start-time preflight failure.
- The final reports section may be delayed by the full timeout even though the failure is already known.
- This makes product agents think the review is still running when one reviewer never started.

Recommended fix:

- If `dx-runner start` returns non-zero for a reviewer, mark that reviewer as terminal for the current `dx-review` run.
- Emit the failed start output in the final report immediately.
- Consider adding `start_failed` to `is_terminal_state` or tracking start failures separately from runtime states.

### 4. `dx-runner check`/`dx-review` output for a missing reviewer is weak

Severity: Medium

Observed behavior:

- `dx-review` parsed the failed OpenCode reviewer as `state=unknown rc=1`.
- A direct `dx-runner check --beads bd-jxclm.15.opencode --json || true` produced no useful JSON output in this session.

Impact:

- The wrapper cannot produce a useful source-of-truth report for a reviewer that failed before metadata/log files were created.
- Product agents have to preserve scrollback from the original `dx-review run` to understand the failure.

Recommended fix:

- `dx-runner check --json` should always emit a JSON object, even for missing run metadata.
- Suggested shape:

```json
{
  "beads": "bd-jxclm.15.opencode",
  "provider": "opencode",
  "state": "start_failed",
  "reason_code": "preflight_failed",
  "next_action": "run mise trust in worktree or run dx-review doctor"
}
```

### 5. Review success is labeled `no_op_success`

Severity: Medium

Observed report state:

```json
{
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations"
}
```

Impact:

- For implementation lanes, `no_op_success` can be suspicious.
- For review lanes, no mutations are the expected outcome.
- The state is technically correct but semantically noisy for code-review UX.

Recommended fix:

- Add a review-lane success state or reason, for example `review_success` / `exit_zero_no_mutations_expected`.
- Alternatively, have `dx-review` translate `no_op_success` to `review_completed` in its summary while preserving the underlying `dx-runner` JSON.

### 6. Local discovery is not guaranteed in the active product-agent context

Severity: Medium

Observed behavior:

- The `dx-review` skill exists locally in `~/agent-skills/extended/dx-review/SKILL.md`.
- Local baseline files also contain `dx-review`.
- The active product-agent skill list for this session did not advertise `dx-review` as an available skill, so discovery still depended on shell/path probing.

Impact:

- Product agents may not automatically use the `dx-review` skill even though the binary works.
- The quote says agents should discover it because the skill entry and baseline were regenerated, but this session did not expose it in the runtime skill registry.

Recommended fix:

- Verify that all app repo `AGENTS.md` baselines include `dx-review`.
- Verify that the runtime skill registry loads the newly added skill on session start.
- Add a lightweight smoke check to `dx-ensure-bins.sh` or the baseline publish flow:

```bash
command -v dx-review
test -f ~/agent-skills/extended/dx-review/SKILL.md
rg -n "dx-review" ~/agent-skills/AGENTS.md
```

### 7. Existing generated-file drift in canonical `agent-skills`

Severity: Low

Observed state before filing this report:

```text
## master...origin/master
 M AGENTS.md
 M dist/universal-baseline.md
```

Impact:

- This did not block the `dx-review` run.
- It does make it harder to distinguish intended baseline regeneration from local drift.
- The report was therefore filed in a clean worktree rather than directly in the canonical clone.

Recommended fix:

- Normalize the canonical `agent-skills` checkout before asking product agents to verify baseline propagation.
- Keep `dx-review` report/fix work in worktrees.

## Non-Failures

- No raw `op` secret commands were run.
- No Beads mutations were run.
- No lingering `dx-review`, `dx-runner`, `claude-code-launcher`, or `bd-jxclm.15` reviewer processes remained after cleanup.
- Claude auth/model access worked on this host.
- OpenCode auth/model access appeared healthy up to the model probe. The blocking error was `mise trust`, not model availability.

## Recommended Acceptance Criteria For Fix

1. `dx-review run --wait` starts Claude and OpenCode without one provider blocking the other's launch.
2. A start-time preflight failure exits promptly and reports a terminal state without waiting for the full timeout.
3. `dx-runner check --json` emits machine-readable JSON for missing/start-failed reviewers.
4. `mise trust` remediation is either automatic and reliable or presented as a single copy/paste command before any reviewer starts.
5. Review-lane no-mutation success is summarized as review success, not suspicious no-op implementation success.
6. Runtime skill discovery exposes `dx-review` consistently to product agents after `agent-skills` update and baseline regeneration.
7. A one-line smoke test works from a clean worktree:

```bash
dx-review run \
  --beads bd-smoke \
  --worktree /tmp/agents/<id>/<repo> \
  --prompt "You are performing code review only. Answer exactly REVIEW_READY." \
  --wait \
  --timeout-sec 180
```

## Follow-Up Patch Ideas

- Change `dx-review` to start reviewers in parallel and then poll all reviewer ids.
- Track `start_failed_reviewers` separately and skip runtime polling for those ids.
- Add `dx-review doctor --worktree <path>` to run both profile preflights without launching reviewers.
- Update `opencode-review` preflight to normalize `/tmp`/`/private/tmp` and emit exact `mise trust -y <path>` remediation.
- Add a review-lane state mapping in `dx-review` summaries.
- Add a small shell test covering failed reviewer start behavior.
