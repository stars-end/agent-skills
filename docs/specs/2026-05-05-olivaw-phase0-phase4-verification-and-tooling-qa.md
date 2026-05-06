# Olivaw Phase 0-4 Verification and Tooling QA

Feature-Key: `bd-1ocyi`
Sidequest: `bd-927zh`
Date: 2026-05-05

## Summary

Phase 0-4 implementation and verification are complete enough to proceed to
the next Olivaw workstream. The remaining gates are intentional safety gates,
not unknown blockers.

Completed:

- Runtime/supervisor preflight and restart health.
- Synthetic redaction canary.
- Slack channel membership and alert-thread canaries for
  `#railway-dev-alerts` and `#fleet-events`.
- Google/gog wrapper with positive allowlist and blocked-action tests.
- Local Olivaw Hermes skill `olivaw-gog-safe`, enabled after gateway restart.
- Phase 3 Slack evidence capture helper.
- Phase 3 `[SILENT]` cron contract canary.
- Phase 4 Hermes Kanban board lifecycle and Beads-handoff canary.
- Manual Computer Use checkpoints after each phase.

Intentional gates:

- Live finance/healthcare workflows remain blocked until the guarded Google
  artifact path is used and sensitive payload handling is explicitly reviewed.
- Google write operations remain blocked by the wrapper.
- Kanban remains local-ops only; code/repo work still belongs in Beads.
- Gas City, BD Symphony, and dx-* implementation belong to the BD Symphony
  agent. Olivaw only consumes those artifacts after explicit owner signoff.

## Phase Results

| Phase | Beads tasks | Result | Evidence |
| --- | --- | --- | --- |
| Phase 0 runtime foundation | `bd-1ocyi.1.1`, `bd-1ocyi.1.2`, `bd-1ocyi.1.3` | Pass | `scripts/olivaw-runtime-check.sh`, `scripts/olivaw-redaction-canary.sh` |
| Phase 1 Slack foundation | `bd-1ocyi.2.1`, `bd-1ocyi.2.2`, `bd-1ocyi.2.3` | Pass with Clawdbot deprecation note | Slack Mac app + Slack API thread evidence |
| Phase 2 Google/gog | `bd-1ocyi.3.1`, `bd-1ocyi.3.2`, `bd-1ocyi.3.3`, `bd-1ocyi.3.4` | Pass with human OAuth hygiene gate | `scripts/olivaw-gog-safe.sh`, local Hermes skill |
| Phase 3 deterministic Slack/cron | `bd-1ocyi.4.1` through `bd-1ocyi.4.5` | Pass for manual canary + executable contracts | `scripts/olivaw-slack-thread-evidence.sh`, `scripts/olivaw-cron-silent-canary.sh` |
| Phase 4 Kanban | `bd-1ocyi.5.1` through `bd-1ocyi.5.5` | Pass | `olivaw-localops` board canary cards |
| Phase 5/7 ownership correction | `bd-1ocyi.8.2`, `bd-1ocyi.6.1`, `bd-1ocyi.6.2` | Pass for Hermes-owned scope | `scripts/olivaw-kanban-policy-canary.sh`, non-GasCity closeout |
| Sidequest tooling QA | `bd-927zh.1`, `bd-927zh.2`, `bd-927zh.3` | Pass | Tool friction matrix below |

## Phase 0 Evidence

Commands:

```bash
scripts/olivaw-runtime-check.sh | jq .
scripts/olivaw-redaction-canary.sh | jq .
bdx preflight --json
```

Results:

- Runtime check: `ok=true`, profile `olivaw`, LaunchAgent
  `ai.hermes.gateway-olivaw`, no public Hermes/Python listener.
- Gateway restart after local skill install: healthy with new PID.
- Redaction canary: `ok=true`; synthetic secret, Slack token, OAuth, account,
  and claim patterns were redacted.
- Beads preflight: `ok=true`.

Manual Computer Use checkpoint:

- Slack Mac app reachable.
- `#fleet-events` visible and usable after runtime checks.

## Phase 1 Slack Evidence

Channel membership check:

- `#all-stars-end`: member.
- `#lifeops`: member.
- `#fleet-events`: member.
- `#coding-misc`: member.
- `#finance`: member.
- `#railway-dev-alerts`: member.

Alert-thread canaries:

```bash
scripts/olivaw-slack-thread-evidence.sh \
  --channel C0AEC54RZ6V \
  --contains OLIVAW_PHASE1_RAILWAY_ALERT_SMOKE_20260505T1748Z \
  --expect-reply RAILWAY_ALERT_OK_20260505

scripts/olivaw-slack-thread-evidence.sh \
  --channel C0A8YU9JW06 \
  --contains OLIVAW_PHASE1_FLEET_EVENTS_SMOKE_20260505T1755Z \
  --expect-reply FLEET_EVENTS_OK_20260505
```

Results:

- `#railway-dev-alerts`: Olivaw replied in-thread with the expected sentinel.
- `#fleet-events`: Olivaw replied in-thread with the expected sentinel.
- `#railway-dev-alerts`: Clawdbot also replied to the same sentinel. This is
  acceptable under the current plan because Clawdbot is being deprecated; it is
  not treated as a Phase 1 blocker.
- `#fleet-events`: only Olivaw replied.

Gateway logs after the latest restart show no fresh `groups:read` missing-scope
warning; old warnings remain in historical log files.

Manual Computer Use checkpoint:

- Synthetic messages were sent through the Slack Mac app.
- Replies were visible in the Slack UI as threaded replies.

## Phase 2 Google/gog Evidence

Wrapper:

```bash
scripts/olivaw-gog-safe.sh auth doctor --check --json
scripts/olivaw-gog-safe.sh gmail search 'newer_than:7d' --max 1 --json --no-input
scripts/olivaw-gog-safe.sh drive ls --json --no-input
```

Results:

- `auth doctor`: `status=ok`; token refresh check passed for
  `fengning@stars-end.ai`.
- Gmail read smoke: passed.
- Drive read smoke: passed.

Blocked-action tests:

- `gmail send`: blocked with exit code `10`.
- `drive share`: blocked with exit code `10`.
- `drive permissions`: blocked with exit code `10`.
- `auth add`: blocked with exit code `10`.
- `sheets update`: blocked with exit code `10`.
- `docs create`: blocked with exit code `10`.

Hermes integration:

- Added local profile skill:
  `/Users/fengning/.hermes/profiles/olivaw/skills/productivity/olivaw-gog-safe/SKILL.md`
- Verified by `hermes -p olivaw skills list`: `olivaw-gog-safe` is enabled.
- Restarted Olivaw gateway and reran runtime check successfully.

Manual Computer Use checkpoint:

- Slack Mac app remained healthy after gateway restart.
- Browser/DevTools were not used for this phase because the prior OAuth
  callback exposure made Slack + CLI evidence the safer choice.

## Phase 3 Slack/Cron Evidence

New executable helpers:

- `scripts/olivaw-slack-thread-evidence.sh`: read-only Slack evidence capture
  for manual canary threads. It uses agent-safe OP cache resolution and redacts
  token/OAuth-like patterns before output.
- `scripts/olivaw-cron-silent-canary.sh`: local contract test for no-change,
  changed, and failure classifications.

Cron canary result:

- Two no-change cases classified as `silent` with `slack_post=false`.
- One changed case classified as `alert` with `slack_post=true`.
- One failure case classified as `error` with `slack_post=true` and
  `failure_reason=synthetic_failure`.

Manual Computer Use checkpoint:

- Slack app remained on `#fleet-events`; the canary thread was visible.

## Phase 4 Kanban Evidence

Board:

- Slug: `olivaw-localops`.
- Display name: `Olivaw Local Ops`.
- Storage:
  `/Users/fengning/.hermes/kanban/boards/olivaw-localops/kanban.db`.

Canary cards:

- `t_f1c9960b`: `KANBAN_CANARY_2026-05-05`.
  - Status: `done`.
  - Lifecycle verified: `created -> blocked -> unblocked -> completed`.
  - Result: local-ops canary completed; no repo writes.
- `t_9dfbd73f`: `needs-beads: OLIVAW_CODE_HANDOFF_CANARY_2026-05-05`.
  - Status: `blocked`.
  - Block reason points to `bd-1ocyi.5.3`.
  - Purpose: prove Kanban-to-Beads handoff instead of Kanban-owned code state.

Manual Computer Use checkpoint:

- Slack Mac app was rechecked after Kanban canary completion.
- Hermes Kanban was verified via CLI because no separate safe dashboard/browser
  surface was required for this local canary.

## Phase 5/7 Hermes-Owned Boundary Evidence

New executable helper:

- `scripts/olivaw-kanban-policy-canary.sh`

Result:

- Missing `source_bdx`: intake/reminder only.
- Invalid `source_bdx`: blocked.
- Valid `source_bdx` followup: pointer-only.
- Valid `source_bdx` launch: waits for BD Symphony signoff.
- Native Hermes Kanban engineering/worktree execution: stop.

Local Olivaw profile updates:

- Stable wrapper:
  `/Users/fengning/.hermes/profiles/olivaw/bin/olivaw-gog-safe.sh`
- Enabled skill:
  `/Users/fengning/.hermes/profiles/olivaw/skills/productivity/olivaw-kanban-boundary/SKILL.md`

Owner boundary:

- BD Symphony owns Gas City, BD Symphony, `dx-runner`, `dx-review`, `dx-loop`,
  and dx-* primitive/config implementation.
- Olivaw owns only Hermes non-Kanban behavior, Hermes Kanban/operator clipboard
  behavior, Slack/Google-facing behavior, and manual verification of those
  surfaces.

## Tooling QA Sidequest

Computer Use:

- Best fit: Slack Mac app workflows, OAuth/account-sensitive setup, and manual
  checkpoints where visual context matters.
- Worked well for: channel navigation, message composition, send button, and
  visual confirmation of threaded replies.
- Frictions:
  - Accessibility trees can include stale labels after channel changes.
  - Element IDs shift; always re-query before clicks.
  - Browser state can expose sensitive URLs if the active tab is an OAuth or
    healthcare callback page.

Chrome DevTools MCP:

- Best fit: non-sensitive browser debugging after auth has completed.
- Friction:
  - Page/listing calls can expose full active URLs, including auth callback
    query strings. Do not use it as routine evidence on OAuth or healthcare
    pages.

agent-browser:

- Best fit: repeatable CLI browser walkthroughs and non-sensitive browser
  snapshots.
- Not used in this pass because Slack desktop and local CLI checks were enough.

Playwright:

- Best fit: deterministic E2E assertions.
- Not used in this pass because no web app route or browser-rendered Hermes
  dashboard was part of the acceptance surface.

Recommended routing:

- Use Computer Use first for Slack, Google account switching, and any
  sensitive/manual UI.
- Use DevTools MCP only after moving away from callback or protected pages.
- Use agent-browser/Playwright for repeatable non-sensitive browser checks.

## Remaining Gates

These are deliberate gates:

- Human confirms stale Google OAuth client-secret cleanup in Google Cloud.
- Any future Google write/draft operation must first add a wrapper allowlist
  entry and a blocked-action regression test.
- Any live healthcare/finance pilot must use Docs/Sheets/Drive artifacts and
  avoid raw Slack payloads.
- Clawdbot deprecation/routing cleanup remains a separate migration item.

## Epic Closeout State

Phase parent status after this pass:

- `bd-1ocyi.1`: closed.
- `bd-1ocyi.2`: closed.
- `bd-1ocyi.3`: closed.
- `bd-1ocyi.4`: closed.
- `bd-1ocyi.5`: closed.
- `bd-1ocyi.6`: final-phase only; blocked on BD Symphony agent signoff and
  owner-provided Gas City/BD Symphony/dx-* artifacts.
- `bd-1ocyi.7`: blocked on explicit HITL pilot selection and sensitive-data
  artifact routing.
- `bd-1ocyi.8`: final-phase only; Olivaw verifies BD Symphony-provided
  visibility artifacts after signoff.
- `bd-1ocyi.9`: blocked on Phase 6/7 live surfaces for broad manual UI
  verification; Gas City-dependent checks wait for BD Symphony signoff.
