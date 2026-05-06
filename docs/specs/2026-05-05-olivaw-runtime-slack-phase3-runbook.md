# Olivaw Runtime + Slack + Phase 3 Runbook

Feature-Key: `bd-1ocyi`
Scope owner: Worker A (`bd-1ocyi.1.*`, `bd-1ocyi.2.*`, `bd-1ocyi.4.*`)
Date: 2026-05-05
Source refs:
- `docs/specs/2026-05-05-olivaw-hermes-implementation-epic.md`
- `docs/specs/2026-05-05-olivaw-phase0-phase2-evidence.md`

## 1) Beads task coverage map

- `bd-1ocyi.1.1`: Correlation-id and structured log field contract.
- `bd-1ocyi.1.2`: Sensitive-data guardrail test skeleton (non-mutating).
- `bd-1ocyi.1.3`: Supervisor/runtime baseline and drift checks.
- `bd-1ocyi.2.1`: Slack alert-channel threaded behavior contract.
- `bd-1ocyi.2.2`: Multi-agent echo policy.
- `bd-1ocyi.2.3`: Slack scope/channel regression checks.
- `bd-1ocyi.4.1`: Deterministic producer inventory template.
- `bd-1ocyi.4.2`: `#railway-dev-alerts` summarizer acceptance.
- `bd-1ocyi.4.3`: `#fleet-events` summarizer acceptance.
- `bd-1ocyi.4.4`: Cron `[SILENT]` no-change contract.
- `bd-1ocyi.4.5`: Adapter observability canary.

## 2) Runtime baseline and supervisor drift regression

### 2.1 Baseline checks (non-destructive)

Run from any non-app directory:

```bash
bdx dolt test --json
bdx preflight --json
~/agent-skills/scripts/dx-bootstrap-auth.sh --json
```

Run on `macmini` host shell:

```bash
hermes doctor
hermes profile list
hermes gateway status
launchctl print "gui/$(id -u)/ai.hermes.gateway-olivaw"
```

Expected:
- Beads connectivity checks return success JSON.
- Auth bootstrap reports an agent-safe mode.
- Hermes doctor passes core checks.
- `olivaw` profile is present and gateway is running.
- LaunchAgent shows loaded/running state for `ai.hermes.gateway-olivaw`.

### 2.2 Supervisor drift regression command/check

Use this exact regression sequence before/after config edits:

```bash
ts="$(date -u +%Y%m%dT%H%M%SZ)"
before="$(pgrep -f 'hermes_cli.main --profile olivaw gateway run' | head -n1)"
launchctl kickstart -k "gui/$(id -u)/ai.hermes.gateway-olivaw"
sleep 2
after="$(pgrep -f 'hermes_cli.main --profile olivaw gateway run' | head -n1)"
echo "ts=${ts} before_pid=${before:-none} after_pid=${after:-none}"
hermes gateway status
```

Pass criteria:
- `after_pid` exists.
- `hermes gateway status` remains healthy.
- If `before_pid` existed, `after_pid` changes (proves supervised restart works).

## 3) Correlation-id and log field contract

Every runtime/slack/adapter action must emit one correlation record with:

- `correlation_id`
- `profile`
- `source_surface`
- `target_host`
- `beads_id`
- `repo`
- `worktree`
- `tool_surface`
- `artifact_refs`
- `status`
- `failure_reason`

Contract rules:
- `correlation_id` format: `olivaw-YYYYMMDDThhmmssZ-<8hex>`.
- For success, set `status=ok` and `failure_reason=""`.
- For failure, set `status=error` and a short machine-readable `failure_reason`.
- `artifact_refs` must be stable paths or IDs (log path, Beads ID, run ID).
- Never include token values, OAuth query strings, message bodies with sensitive payloads, or raw secrets in any field.

Minimal JSON example:

```json
{
  "correlation_id": "olivaw-20260505T221530Z-a13f9b2c",
  "profile": "olivaw",
  "source_surface": "slack:#fleet-events",
  "target_host": "macmini",
  "beads_id": "bd-1ocyi.4.5",
  "repo": "agent-skills",
  "worktree": "/tmp/agents/bd-k9rfq/agent-skills",
  "tool_surface": "hermes-gateway",
  "artifact_refs": [
    "/Users/fengning/.hermes/profiles/olivaw/logs/gateway.log"
  ],
  "status": "ok",
  "failure_reason": ""
}
```

## 4) Sensitive-data guardrail test skeleton (non-mutating)

Goal: verify redaction and no-secrets-in-logs behavior without sending real sensitive payloads.

Skeleton cases:

1. Secret-pattern canary:
   - Input text with synthetic placeholders like `sk-test-REDACT_ME` and `xoxb-REDACT_ME`.
   - Expected: output/logs redact or drop patterns; no literal synthetic secret pattern appears.
2. OAuth URL canary:
   - Input text containing fake callback query keys (`code=FAKE_CODE`, `state=FAKE_STATE`).
   - Expected: logs strip or hash query values.
3. Finance text canary:
   - Input text with fake account/claim fragments.
   - Expected: Slack summary uses sanitized placeholders and no raw values.

Evidence capture:
- Record only pass/fail and sanitized snippets.
- Save counts of redaction events.
- Do not store raw test payload beyond local temporary shell variables.

## 5) Slack smoke and policy plan (manual; parent agent executes)

Do not run mutating Slack tests here. Parent agent executes via Computer Use.

### 5.1 Manual steps

1. DM smoke:
   - Send: `DM_OK_20260505`
   - Expected evidence: Olivaw reply in DM with correlation-id footer or linked trace token.
2. App mention smoke in `#coding-misc`:
   - Send: `@olivaw CODING_OK_20260505`
   - Expected evidence: threaded Olivaw response, not silent.
3. Alert-thread smoke in `#railway-dev-alerts`:
   - Post deterministic synthetic alert line.
   - Expected evidence: Olivaw replies in thread (not top-level) with summary classification.
4. Alert-thread smoke in `#fleet-events`:
   - Post deterministic synthetic status line.
   - Expected evidence: threaded summary with same correlation-id contract.
5. Discussion-channel behavior:
   - In `#lifeops` or `#all-stars-end`, request a digest summary.
   - Expected evidence: new top-level digest thread allowed.

### 5.2 Expected evidence format

For each test:
- channel/surface
- local timestamp
- correlation_id
- expected result
- actual result
- redaction note (`none` or what was sanitized)

## 6) Multi-agent echo policy

Policy objective: avoid double-responses when multiple bots are present.

Rules:
- In alert channels, Olivaw only responds when explicit adapter trigger markers are present.
- In discussion channels, Olivaw responds to direct mention, DM, or explicit prefix command.
- If another agent already posted a matching sentinel in-thread within 90 seconds, Olivaw skips duplicate summary and logs `failure_reason=duplicate_echo_suppressed`.

Manual regression checks:
- Trigger one coding-misc mention while Clawdbot is active.
- Expected: at most one Olivaw response; if duplicate condition detected, suppression note in logs.

## 7) Slack scope/channel regression plan

Run as read-only checks after any Slack reinstall/scope change:

```bash
hermes gateway status
```

Then verify in runtime logs that:
- Socket Mode connected.
- No missing-scope warnings for private channel reads.
- Channel directory includes:
  - `#railway-dev-alerts`
  - `#fleet-events`
  - `#lifeops`
  - `#finance`
  - `#coding-misc`
  - `#all-stars-end`

Fail conditions:
- Missing alert channels from directory.
- Reappearance of private-channel scope warnings.
- Repeated reconnect loop without stable ready state.

## 8) Deterministic producer inventory template (Phase 3)

Use this template as the canonical producer register:

```markdown
### Producer: <name>
- Source channel: <#railway-dev-alerts | #fleet-events>
- Source system: <railway summary | dx status | vm watchdog | other deterministic job>
- Producer script/service: <path or service id>
- Cadence: <cron/interval/event-driven>
- Deterministic payload keys: <list>
- Hermes adapter mode: <thread-summary | classify-only | ignore>
- No-change behavior: <silent | heartbeat-only>
- Correlation seed fields: <keys used to derive correlation id>
- Evidence artifact path: <log/report path>
- Owner: <team/persona>
```

## 9) Summarizer acceptance criteria

### 9.1 `#railway-dev-alerts` summarizer acceptance (`bd-1ocyi.4.2`)

- Input: one deterministic deploy/health alert message.
- Output: one threaded summary reply.
- Must include:
  - category (`deploy`, `health`, `incident`, `noop`)
  - severity
  - short action recommendation
  - correlation_id
- Must not:
  - post routine all-clear top-level noise
  - include raw secret/env payloads

### 9.2 `#fleet-events` summarizer acceptance (`bd-1ocyi.4.3`)

- Input: one deterministic fleet status/update event.
- Output: one threaded summary reply.
- Must include:
  - host list or target tag
  - changed/not-changed state
  - next-check hint
  - correlation_id
- Must not:
  - produce duplicate replies for same event key
  - leak internal auth or token details

## 10) Cron `[SILENT]` contract (`bd-1ocyi.4.4`)

For mechanical checks where nothing changed:
- Exit code `0`.
- No Slack post.
- Optional local log line: `[SILENT] no change`.

For changed or failing checks:
- Post exactly one alert summary to appropriate channel/thread.
- Include `correlation_id` and one artifact reference.
- Nonzero exit only for execution failure, not for "change detected."

Regression checks:
- Run no-change input twice: both runs stay silent in Slack.
- Run one changed input: one alert appears.
- Run one forced failure path: one error summary appears with `failure_reason`.

## 11) Adapter observability canary (`bd-1ocyi.4.5`)

Canary objective: prove end-to-end trace across producer -> adapter -> Slack summary.

Executable evidence helper:

```bash
scripts/olivaw-slack-thread-evidence.sh \
  --channel C0AEC54RZ6V \
  --contains OLIVAW_PHASE1_RAILWAY_ALERT_SMOKE_20260505T1748Z \
  --expect-reply RAILWAY_ALERT_OK_20260505
```

Canary procedure:
- Inject one synthetic deterministic event key:
  - `canary_key=OLIVAW_CANARY_20260505`
- Derive `correlation_id` using run timestamp + key hash suffix.
- Confirm one summary thread appears in target alert channel.
- Confirm runtime logs contain matching:
  - `correlation_id`
  - `source_surface`
  - `artifact_refs`
  - `status`

Acceptance:
- One input event yields one summary thread.
- Correlation fields match across log and Slack evidence.
- No sensitive payload appears in summary or logs.

## 11.1 Cron `[SILENT]` executable canary

Run:

```bash
scripts/olivaw-cron-silent-canary.sh | jq .
```

Pass criteria:

- Two no-change cases classify as `silent` with `slack_post=false`.
- One changed case classifies as `alert` with `slack_post=true`.
- One failure case classifies as `error` with `slack_post=true` and a
  machine-readable `failure_reason`.

## 12) Operator checklist (closeout gate)

All true before marking Worker A tasks complete:

- Runtime supervisor drift check passed.
- Correlation-id field contract enforced in at least one real trace.
- Sensitive-data guardrail skeleton executed with sanitized evidence.
- Slack DM/app-mention/alert-thread manual smoke evidence captured.
- Multi-agent echo behavior validated with suppression policy evidence.
- Slack scope/channel regression checks passed after latest gateway restart.
- Producer inventory template instantiated for active Phase 3 producers.
- `#railway-dev-alerts` and `#fleet-events` summarizer acceptance passed.
- Cron `[SILENT]` no-change and changed/failure behavior validated.
- Adapter observability canary trace captured and archived.
