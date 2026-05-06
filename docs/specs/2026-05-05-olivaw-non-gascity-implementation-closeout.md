# Olivaw Non-GasCity Implementation Closeout

Feature-Key: `bd-1ocyi.8.2`
Date: 2026-05-05

## Scope

This pass implements only work owned by the Olivaw/Hermes lane while the BD
Symphony agent continues Gas City/BD Symphony/dx-* work.

In scope:

- Hermes/Olivaw spec alignment.
- Hermes Kanban pointer schema.
- Hermes Kanban stop condition for coding/repo work.
- Stable Olivaw Google wrapper routing.
- Non-coding, non-GasCity smoke checks for runtime, Google auth, redaction,
  cron-noise behavior, and Kanban policy.

Out of scope:

- Gas City implementation.
- BD Symphony implementation.
- `dx-runner`, `dx-review`, `dx-loop`, or dx-* primitive/config implementation.
- Coding dispatch.
- Repo/worktree execution from Hermes.
- Live finance/healthcare payload processing.

## Implemented

Updated:

- `docs/specs/2026-05-05-olivaw-hermes-implementation-epic.md`
- `docs/specs/2026-05-05-olivaw-google-kanban-tooling-runbook.md`
- `docs/specs/2026-05-04-hermes-feature-workstream-matrix.md`

Added:

- `scripts/olivaw-kanban-policy-canary.sh`
- `/Users/fengning/.hermes/profiles/olivaw/bin/olivaw-gog-safe.sh`
- `/Users/fengning/.hermes/profiles/olivaw/skills/productivity/olivaw-kanban-boundary/SKILL.md`

The docs and local skill now state:

- BD Symphony owns Gas City, BD Symphony, `dx-runner`, `dx-review`, `dx-loop`,
  and dx-* implementation.
- Olivaw/Hermes owns Slack/Google-facing behavior, Hermes Kanban/operator
  clipboard behavior, and source_bdx intake semantics.
- Gas City-dependent Olivaw work is final-phase only and waits for BD Symphony
  signoff.

## Kanban Pointer Contract

Allowed metadata:

```json
{
  "source_bdx": "bd-...",
  "gascity_order_id": "...",
  "gascity_run_id": "...",
  "correlation_id": "...",
  "surface": "olivaw-kanban",
  "canonical_url": "beads://bd-...",
  "operator_intent": "triage|launch|followup|blocked_review",
  "last_known_bdx_status": "open|in_progress|blocked|closed"
}
```

Rules:

- `source_bdx` is required before a card represents real engineering work.
- Missing `source_bdx` means intake/reminder only.
- `last_known_bdx_status` is display-only and may be stale.
- Beads/Gas City remain authoritative.

Stop condition:

> if fulfilling a Kanban action requires creating a parallel task graph,
> executing repo work without Beads identity, or treating Kanban state as more
> authoritative than Beads/Gas City, stop and request canonical Beads routing.

## Verification

Executed checks:

```bash
scripts/olivaw-kanban-policy-canary.sh | jq .
scripts/olivaw-redaction-canary.sh | jq .
scripts/olivaw-cron-silent-canary.sh | jq .
scripts/olivaw-runtime-check.sh | jq .
/Users/fengning/.hermes/profiles/olivaw/bin/olivaw-gog-safe.sh auth doctor --check --json
scripts/olivaw-gog-safe.sh calendar calendars --json --no-input
hermes -p olivaw skills list | rg 'olivaw-gog-safe|olivaw-kanban-boundary'
```

Results:

- Kanban policy canary: pass.
- Redaction canary: pass.
- Cron `[SILENT]` canary: pass.
- Runtime check: pass; Olivaw LaunchAgent running; no public listener.
- gog auth doctor: pass for `fengning@stars-end.ai`.
- Calendar read smoke: pass; raw output suppressed.
- Hermes skills list: both `olivaw-gog-safe` and `olivaw-kanban-boundary` are
  enabled.

## Remaining Blocked Work

Blocked on BD Symphony agent signoff:

- `bd-1ocyi.6.3`
- `bd-1ocyi.6`
- `bd-1ocyi.6.4`
- `bd-1ocyi.6.5`
- `bd-1ocyi.8`
- `bd-1ocyi.8.1`
- Gas City-dependent parts of `bd-1ocyi.9`

Blocked on human/HITL approval rather than Gas City:

- live finance/healthcare payload processing,
- reservation workflows that call, book, send, or mutate external systems,
- Google write/draft actions beyond the current read-only wrapper.

## Next Safe Work

While waiting for BD Symphony, the next safe Olivaw work is manual Slack/Google
operator verification for non-sensitive, non-GasCity flows only.
