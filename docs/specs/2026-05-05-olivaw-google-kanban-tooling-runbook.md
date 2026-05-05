# Olivaw Worker B Runbook: Google, Kanban, and Tooling QA

Feature-Key: `bd-1ocyi`
Date: 2026-05-05
Owner scope: Worker B only (`bd-1ocyi.3.*`, `bd-1ocyi.5.*`, `bd-927zh.*`)

## 1) Scope and Safety Contract

This runbook covers:

- Phase 2 Google/gog hardening and blocked-action tests.
- Phase 4 Kanban boundary and Kanban-to-Beads handoff rules.
- Sidequest tooling QA documentation and manual canary method.

Out of scope for this runbook:

- Runtime supervisor and Slack gateway mutation (Phase 0/1/3 worker-owned paths).
- Any destructive Google action (send/delete/admin/sharing) or secret rotation.

## 2) Google/gog Safety Wrapper Contract

Canonical safe invocation:

```bash
scripts/olivaw-gog-safe.sh <gog-subcommand> [args...]
```

Policy:

- Defaults account to `fengning@stars-end.ai`.
- Defaults client to `olivaw-gog`.
- Always applies `--gmail-no-send`.
- Allows only approved read/doctor commands before invoking `gog`.
- Supports read-only and doctor-style verification lanes.

Human confirmation gate (document-only, no automation here):

- If Google Cloud shows multiple OAuth client secrets, a human must confirm and then disable/remove the stale secret in the Google Cloud Console. Do not perform this from agent automation.

## 3) Blocked-Action Test Plan (Phase 2)

Purpose:

- Prove fail-closed behavior for Gmail send/delete and Drive sharing/admin paths.

Method:

1. Run allowed preflight:
   - `scripts/olivaw-gog-safe.sh auth doctor --check --json`
2. Run allowed read smoke:
   - `scripts/olivaw-gog-safe.sh gmail search 'newer_than:7d' --max 1 --json --no-input`
3. Run blocked probes (must fail before API call):
   - `scripts/olivaw-gog-safe.sh gmail send ...`
   - `scripts/olivaw-gog-safe.sh gmail delete ...`
   - `scripts/olivaw-gog-safe.sh drive share ...`
   - `scripts/olivaw-gog-safe.sh drive permissions ...`
4. Capture evidence:
   - command
   - exit code
   - stderr block reason
   - timestamp

Pass criteria:

- Allowed commands succeed.
- Blocked commands exit non-zero with explicit policy reason.
- No OAuth token/client secret/password/OAuth callback code appears in logs.

## 4) Hermes-Facing Google Skill Bridge Spec

Bridge intent:

- Keep Hermes-side Google execution on one guarded substrate.

Interface contract:

- Hermes tool bridge calls `scripts/olivaw-gog-safe.sh` only.
- Olivaw profile skill installed at:
  `/Users/fengning/.hermes/profiles/olivaw/skills/productivity/olivaw-gog-safe/SKILL.md`
- Tool inputs are mapped to a constrained command grammar:
  - allowed examples: `auth doctor`, `gmail search`, `calendar calendars`,
    `calendar events`, `drive ls`, `drive search`, `docs info`, `docs cat`,
    `sheets get`, `sheets metadata`, `contacts list`
  - disallowed families: `gmail send/delete`, Drive sharing/permissions/admin actions, credential mutation commands
- JSON output mode is required for machine parsing.

Operational notes:

- Keep business account and personal Gmail isolation explicit in bridge prompts/tool docs.
- If future requirement needs draft creation, add explicit allowlist entry and accompanying blocked-action regression tests before enabling by default.
- Verify skill loading with `hermes -p olivaw skills list | rg olivaw-gog-safe`.

## 5) OAuth Hygiene Decision Checklist

For each OAuth/client change request, decide exactly one:

1. `ALL_IN_NOW`
   - Rename project/app labels to Star's End naming standard.
   - Verify API enablement and OAuth client ownership alignment.
   - Human-confirm and remove stale client secret.
2. `DEFER_TO_P2_PLUS`
   - Keep functional setup and log risk register item.
   - Add dated follow-up Beads task.
3. `CLOSE_AS_NOT_WORTH_IT`
   - Close only if no security/compliance risk is introduced and current posture is already minimal-risk.

Checklist:

- OAuth app audience/publishing state documented.
- Token expiry implications documented if app remains in testing mode.
- Stale secrets handled only via human-confirmed console action.
- Downloaded client JSON lifecycle documented (imported then removed from transient paths).

## 6) Kanban Capability and Storage Inventory Method (Phase 4)

Inventory steps (read-only first):

1. Enumerate boards and lists in Hermes UI/API for `olivaw`, `family`, `finance`, `coder`.
2. For each board, record:
   - board key/name
   - intended profile owner
   - storage location/system of record
   - allowed task classes
   - prohibited task classes
3. Verify that coding source-of-truth fields (repo, branch, Feature-Key, PR state) are not authored as canonical state inside Kanban.
4. Record one sample item lifecycle (`create -> block -> unblock -> complete`) with timestamps.

Evidence format:

- Table in Beads comment or run artifact with one row per board.

## 7) Local-Ops Board Taxonomy

Allowed Hermes Kanban categories:

- lifeops admin
- research digest prep
- Google Workspace follow-up tasks
- watchdog/manual check summaries
- HITL reminders for non-coding operations

Disallowed categories:

- coding implementation source-of-truth
- PR lifecycle state management
- cross-VM orchestration ownership
- durable engineering memory replacing Beads

## 8) Kanban-to-Beads Handoff Rule

Trigger:

- Any Kanban item that requires code change, repo mutation, CI/review action, or cross-VM execution.

Required handoff payload:

- Beads ID (existing or newly created)
- target repo
- target worktree path
- acceptance criteria
- validation commands
- link-back pointer from Beads to originating Kanban item

Rule:

- Kanban item status becomes `blocked-on-beads` until Beads artifact/PR result exists.
- Completion happens in Kanban only after result link is posted back.

## 9) Delegation and Memory Boundary Tests

Delegation boundary tests:

- Attempt prohibited coding delegation path (`subagent-driven-development`) from Kanban context; expect fail-closed with policy message.
- Attempt read-only reasoning delegation; expect allowed.

Memory boundary tests:

- Verify durable engineering decision is recorded in Beads memory/issue, not only Kanban card text.
- Verify Kanban card stores only pointer metadata (Beads ID + summary), not canonical engineering state.

Pass criteria:

- One positive and one negative test for each boundary with explicit evidence lines.

## 10) Kanban Manual UI Canary Plan

Owned by parent agent for Computer Use execution; this runbook defines exact steps.

Steps:

1. Open Hermes Kanban surface for `olivaw`.
2. Create canary card: `KANBAN_CANARY_2026-05-05`.
3. Move lifecycle:
   - `todo -> blocked -> in-progress -> done`
4. Create second card requiring code handoff:
   - title includes `needs-beads`.
5. Trigger handoff:
   - record Beads ID and paste into card.
6. Verify board/profile visibility boundaries:
   - card should appear only in intended local board scope.
7. Capture evidence:
   - timestamped screenshots/notes
   - card IDs
   - state transitions
   - Beads linkage

Expected evidence:

- Transition history visible.
- `needs-beads` card shows blocked/handoff semantics.
- No direct repo-write action from Kanban-only flow.

## 11) Tooling QA Matrix (Manual and Automation Surfaces)

| Surface | Best for | Avoid when | Evidence type |
| --- | --- | --- | --- |
| Computer Use | Slack app flows, OAuth/account switching, sensitive UI checks | repeatable assertion-heavy CI checks | screenshots + operator notes |
| Chrome DevTools MCP | post-auth page inspection, console/network debugging on safe pages | OAuth callback URLs with sensitive query params | page/console traces with redaction |
| `agent-browser` | repeatable CLI browser walkthroughs and read-oriented canaries | privileged desktop-only app interactions | command logs + snapshots |
| Playwright | deterministic E2E assertions/regression checks | ad hoc multi-account manual operator work | test reports/artifacts |

Decision rule:

- Start with Computer Use for account-sensitive UI.
- Use DevTools MCP only after auth callback risk is gone.
- Use `agent-browser` for CLI-repeatable browser checks.
- Use Playwright for scripted assertions and regression lanes.

## 12) Task Mapping

- `bd-1ocyi.3.1`: Google/gog safety wrapper contract.
- `bd-1ocyi.3.2`: blocked-action test plan.
- `bd-1ocyi.3.3`: Hermes-facing Google skill bridge spec.
- `bd-1ocyi.3.4`: OAuth hygiene checklist.
- `bd-1ocyi.5.1`: Kanban capability/storage inventory method.
- `bd-1ocyi.5.2`: local-ops board taxonomy.
- `bd-1ocyi.5.3`: Kanban-to-Beads handoff rule.
- `bd-1ocyi.5.4`: delegation/memory boundary tests.
- `bd-1ocyi.5.5`: Kanban manual UI canary plan.
- `bd-927zh.1/.2/.3`: tooling QA matrix and wrapper-oriented guardrail documentation.
