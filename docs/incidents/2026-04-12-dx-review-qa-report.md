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

## Retest After PR #552 / `b52eef9`

Date: 2026-04-12
Host: Fengs-MacBook-Pro
Local `agent-skills` HEAD: `b52eef9 bd-p87lk: stabilize dx-review quorum runs`

This section records a second product-agent QA pass after the reported #552 fixes landed locally.

### Retest Commands

Affordabot doctor against the original repro worktree:

```bash
dx-review doctor \
  --worktree /tmp/agents/offline-20260412-windmill-bakeoff/affordabot
```

Affordabot live review smoke:

```bash
dx-review run \
  --beads bd-jxclm.15r \
  --worktree /tmp/agents/offline-20260412-windmill-bakeoff/affordabot \
  --prompt-file /tmp/dx-review-bd-jxclm.15r.prompt \
  --wait \
  --timeout-sec 900 \
  --poll-sec 10
```

Agent-skills doctor from a different current working directory:

```bash
dx-review doctor \
  --worktree /tmp/agents/bd-jxclm.15/agent-skills
```

Agent-skills live review from a different current working directory:

```bash
dx-review run \
  --beads bd-jxclm.15s \
  --worktree /tmp/agents/bd-jxclm.15/agent-skills \
  --prompt-file /tmp/dx-review-bd-jxclm.15r.prompt \
  --wait \
  --timeout-sec 240 \
  --poll-sec 10
```

Agent-skills live review from inside the target worktree:

```bash
cd /tmp/agents/bd-jxclm.15/agent-skills
dx-review run \
  --beads bd-jxclm.15t \
  --worktree /tmp/agents/bd-jxclm.15/agent-skills \
  --prompt-file /tmp/dx-review-bd-jxclm.15r.prompt \
  --wait \
  --timeout-sec 300 \
  --poll-sec 10
```

Missing metadata check:

```bash
dx-runner check --beads bd-jxclm.15s.missing --json
```

### Fixed In Retest

#### Parallel reviewer launch now works

The affordabot smoke run printed both launch lines immediately:

```text
dx-review reviewers: claude-code-review opencode-review
launching reviewer=bd-jxclm.15r.claude profile=claude-code-review start_log=/tmp/dx-review/bd-jxclm.15r/bd-jxclm.15r.claude.start.log
launching reviewer=bd-jxclm.15r.opencode profile=opencode-review start_log=/tmp/dx-review/bd-jxclm.15r/bd-jxclm.15r.opencode.start.log
```

This fixes the original quorum-breaking behavior where Claude startup blocked OpenCode from launching.

#### Affordabot repro worktree now passes doctor

Doctor result against `/tmp/agents/offline-20260412-windmill-bakeoff/affordabot`:

```text
claude binary: OK (claude)
canonical model probe: OK (opus)
=== Preflight PASSED ===
opencode binary: OK (opencode)
model availability: OK (16 models)
canonical model probe: OK (zhipuai/glm-5.1)
execution mode capability: OK (headless run)
beads-mcp binary: MISSING
  WARN_CODE=opencode_beads_mcp_missing severity=warn action=install_beads_mcp_for_richer_context
mise trust: OK (/private/tmp/agents/offline-20260412-windmill-bakeoff/affordabot)
=== Preflight PASSED ===
```

The `beads-mcp` warning is still present, but non-blocking.

#### Affordabot live review now completes both reviewers

The affordabot smoke run completed both lanes:

```text
reviewer=bd-jxclm.15r.claude state=review_completed raw_state=no_op_success rc=0
reviewer=bd-jxclm.15r.opencode state=review_completed raw_state=no_op_success rc=0
```

Final report summary:

```json
{
  "beads": "bd-jxclm.15r.claude",
  "provider": "claude-code",
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations",
  "selected_model": "opus",
  "mutations": 0
}
```

```json
{
  "beads": "bd-jxclm.15r.opencode",
  "provider": "opencode",
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations",
  "selected_model": "zhipuai/glm-5.1",
  "mutations": 0
}
```

The wrapper status output now maps review-lane no-mutation completion to `review_completed`, which is materially better for product-agent UX. The underlying `dx-runner report` JSON still preserves the raw `no_op_success` state.

#### Start/preflight failure is now terminal and structured

The run against the `agent-skills` worktree from `/Users/fning/prime-radiant-ai` triggered an OpenCode preflight failure. Unlike the first QA pass, `dx-review` did not poll it as `unknown` until timeout:

```text
reviewer_start_failed reviewer=bd-jxclm.15s.opencode profile=opencode-review rc=21 start_log=/tmp/dx-review/bd-jxclm.15s/bd-jxclm.15s.opencode.start.log
reviewer=bd-jxclm.15s.claude state=healthy raw_state=healthy rc=0
reviewer=bd-jxclm.15s.opencode state=start_failed rc=21
reviewer=bd-jxclm.15s.claude state=review_completed raw_state=no_op_success rc=0
reviewer=bd-jxclm.15s.opencode state=start_failed rc=21
```

The final report included synthetic structured JSON for the failed start:

```json
{
  "beads": "bd-jxclm.15s.opencode",
  "provider_profile": "opencode-review",
  "state": "start_failed",
  "reason_code": "dx_runner_start_failed",
  "start_exit_code": 21,
  "start_log": "/tmp/dx-review/bd-jxclm.15s/bd-jxclm.15s.opencode.start.log"
}
```

This is a meaningful fix.

#### Agent-skills live review works when run from the target worktree

Running from `/tmp/agents/bd-jxclm.15/agent-skills` completed both reviewers:

```text
reviewer=bd-jxclm.15t.claude state=review_completed raw_state=no_op_success rc=0
reviewer=bd-jxclm.15t.opencode state=review_completed raw_state=no_op_success rc=0
```

OpenCode preflight correctly treated `mise` as not applicable in that worktree:

```text
mise trust: N/A (no .mise target)
=== Preflight PASSED with warnings (1 warning(s)) ===
```

### Remaining Product Frictions / Bugs

#### A. `dx-review doctor --worktree` can still evaluate `mise` against the caller cwd

Severity: High

Repro:

```bash
cd /Users/fning/prime-radiant-ai
dx-review doctor --worktree /tmp/agents/bd-jxclm.15/agent-skills
```

Observed failure:

```text
cwd: /Users/fning/prime-radiant-ai
mise trust: UNTRUSTED (/Users/fning/prime-radiant-ai)
  ERROR_CODE=opencode_mise_untrusted severity=error action=mise_trust target=/Users/fning/prime-radiant-ai command="mise trust '/Users/fning/prime-radiant-ai'"
=== Preflight FAILED (1 error(s), 1 warning(s)) ===
```

Expected behavior:

- The command should evaluate the supplied worktree, not the product agent's caller cwd.
- Since `/tmp/agents/bd-jxclm.15/agent-skills` has no `.mise.toml`, expected result is:

```text
mise trust: N/A (no .mise target)
```

Why this matters:

- Product agents commonly run orchestration commands from their current app repo while reviewing another worktree.
- In this repro, the target review worktree was valid, but the doctor failed because the caller cwd had an unrelated `.mise.toml`.
- Workaround is to `cd` into the target worktree before running `dx-review doctor` or `dx-review run`, but that weakens the advertised command shape.

Likely cause:

- `opencode` adapter preflight falls back to `$(pwd)/.mise.toml` when the supplied worktree has no `.mise.toml`.
- That fallback should be disabled when an explicit `--worktree` / `DX_RUNNER_PREFLIGHT_WORKTREE` is present. An explicit worktree with no `.mise.toml` should produce `N/A`, not inspect cwd.

#### B. `dx-runner check --json` still emits no JSON for totally missing metadata

Severity: Medium

Repro:

```bash
dx-runner check --beads bd-jxclm.15s.missing --json
```

Observed output:

```text

rc=1
```

Expected behavior, based on the #552 fix claim:

```json
{
  "beads": "bd-jxclm.15s.missing",
  "provider": "unknown",
  "state": "start_failed",
  "reason_code": "missing_reviewer_metadata",
  "next_action": "inspect_dx_review_start_log_or_rerun_preflight"
}
```

Why this matters:

- `dx-review` now handles its own failed starts well, but direct `dx-runner check --json` remains weak for missing metadata.
- External automation that relies on `dx-runner check --json` still needs shell exit-code special handling.

#### C. `beads-mcp binary: MISSING` warning remains in every OpenCode preflight

Severity: Low

Observed warning:

```text
beads-mcp binary: MISSING
  WARN_CODE=opencode_beads_mcp_missing severity=warn action=install_beads_mcp_for_richer_context
```

This is non-blocking, but noisy. If `beads-mcp` is optional, the product-agent docs should explicitly say that this warning is expected and not a reason to stop.

## Updated Verdict After Retest

`dx-review` is now usable for product-agent review of app worktrees, especially when the command is run from the target worktree or the caller cwd has no unrelated untrusted `.mise.toml`.

It is not fully frictionless yet. The remaining high-value fix is to make explicit `--worktree` authoritative for `mise` preflight, including the case where the target worktree has no `.mise.toml`. The second fix is to make direct `dx-runner check --json` emit structured missing-metadata JSON as advertised.

Recommended product-agent command until the cwd bug is fixed:

```bash
cd /tmp/agents/<id>/<repo>
dx-review doctor --worktree "$PWD"
dx-review run \
  --beads bd-xxxx \
  --worktree "$PWD" \
  --prompt-file /tmp/review.prompt \
  --wait
```

## Retest After PR #554 / `816387a`

Date: 2026-04-12
Host: Fengs-MacBook-Pro
Local `agent-skills` HEAD: `816387a bd-icwpm: fix dx-review worktree preflight`

This section records a third QA pass after PR #554 merged and the local canonical checkout was fast-forwarded.

### Commands

Previously failing authoritative-worktree repro:

```bash
cd /Users/fning/prime-radiant-ai
dx-review doctor --worktree /tmp/agents/bd-jxclm.15/agent-skills
```

Missing metadata JSON repro:

```bash
cd /Users/fning/prime-radiant-ai
dx-runner check --beads bd-jxclm.15u.missing --json
printf '\nrc=%s\n' "$?"
```

Live review from the previously failing caller cwd:

```bash
cd /Users/fning/prime-radiant-ai
dx-review run \
  --beads bd-jxclm.15u \
  --worktree /tmp/agents/bd-jxclm.15/agent-skills \
  --prompt-file /tmp/dx-review-bd-jxclm.15r.prompt \
  --wait \
  --timeout-sec 300 \
  --poll-sec 10
```

### Resolved

#### Explicit `--worktree` is now authoritative for `mise`

The exact repro that previously failed by inspecting `/Users/fning/prime-radiant-ai/.mise.toml` now passes:

```text
cwd: /Users/fning/prime-radiant-ai
provider: opencode
canonical model probe: OK (zhipuai/glm-5.1)
execution mode capability: OK (headless run)
beads-mcp binary: MISSING
  WARN_CODE=opencode_beads_mcp_missing severity=warn action=install_beads_mcp_for_richer_context
mise trust: N/A (explicit worktree has no .mise target: /private/tmp/agents/bd-jxclm.15/agent-skills)

=== Preflight PASSED with warnings (1 warning(s)) ===
```

This closes the high-severity product-agent cwd bleed bug.

#### Missing reviewer metadata now emits JSON

The missing-metadata check now emits machine-readable JSON:

```json
{
  "beads": "bd-jxclm.15u.missing",
  "provider": "unknown",
  "state": "missing",
  "reason_code": "no_meta",
  "next_action": "verify_beads_id_or_start_reviewer"
}
```

The command still exits `1`, which is appropriate for missing metadata as long as automation can parse the JSON body.

#### Live run passes from a non-target caller cwd

The live run from `/Users/fning/prime-radiant-ai` against `/tmp/agents/bd-jxclm.15/agent-skills` completed both reviewers:

```text
reviewer=bd-jxclm.15u.claude state=review_completed raw_state=no_op_success rc=0
reviewer=bd-jxclm.15u.opencode state=review_completed raw_state=no_op_success rc=0
```

Final reports:

```json
{
  "beads": "bd-jxclm.15u.claude",
  "provider": "claude-code",
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations",
  "selected_model": "opus",
  "worktree": "/tmp/agents/bd-jxclm.15/agent-skills",
  "mutations": 0
}
```

```json
{
  "beads": "bd-jxclm.15u.opencode",
  "provider": "opencode",
  "state": "no_op_success",
  "reason_code": "exit_zero_no_mutations",
  "selected_model": "zhipuai/glm-5.1",
  "worktree": "/tmp/agents/bd-jxclm.15/agent-skills",
  "mutations": 0
}
```

### Remaining P2 Enhancement Requests

The blocking/friction bugs from the first two passes are resolved. Remaining items are product-agent ergonomics:

- Add `dx-review summarize --beads <id>` to combine reviewer verdicts, findings, failures, token/cost use, and log/report paths into one artifact.
- Add `dx-review run --pr <owner/repo#num>` or `--github-pr <url>` to auto-populate repository, PR URL, base/head SHAs, changed files, and default review prompt context.
- Add prompt templates such as `--template smoke`, `--template code-review`, and `--template arch-review`.
- Add an explicit read-only review mode that permits non-mutating shell commands like `git diff`, `rg`, `sed`, and `pytest --collect-only` while still blocking edits, commits, pushes, and secret retrieval.
- Print a final quorum line, for example `dx-review quorum: 2/2 completed, 0 failed`, so product agents do not need to infer status from per-reviewer JSON.
- Include token and cost summaries in the final wrapper output. The OpenCode smoke prompt previously consumed about 50k total tokens, which is acceptable only if visible.
- Continue improving runtime skill discovery so already-running product-agent sessions notice the new `dx-review` skill or get an explicit refresh instruction.

### Final Tooling Verdict

After PR #554, `dx-review` is ready for product-agent use with the advertised command shape:

```bash
dx-review doctor --worktree /tmp/agents/<id>/<repo>

dx-review run \
  --beads bd-xxxx \
  --worktree /tmp/agents/<id>/<repo> \
  --prompt-file /tmp/review.prompt \
  --wait
```

The remaining work is polish, not a blocker for adoption.
