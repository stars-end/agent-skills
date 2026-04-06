# bd-n14ag — Cass Pilot Measurement and Scheduling Repair

## Summary

Repair the cass-memory pilot so it produces measurable evidence instead of
repeated retrieval spot-checks. Align `agent-skills` runtime/config messaging,
make the pilot feedback loop explicit, and replace the current daily review
automation with a weekly delta-focused review.

## Problem

The current pilot has three issues:

1. `agent-skills` surfaces disagree about how `cass-memory` is exposed:
   manifest/docs say CLI-only + disabled-by-default, while older Fleet Sync
   templates still render it as an MCP server.
2. The pilot captures discoverability but not enough measured reuse:
   no populated reuse log, no `cm mark --helpful/--harmful` guidance, and weak
   agent trigger language.
3. The current daily automation mostly re-proves the same absence of evidence
   instead of checking for meaningful delta.

## Goals

1. Make the `cass-memory` runtime story internally consistent.
2. Tighten pilot instructions so agents know exactly when to use `cm context`
   and how to record helpful/harmful outcomes.
3. Keep candidate-first promotion intact; do not broaden cass into a canonical
   default surface.
4. Replace the daily automation with a weekly delta-focused review.

## Non-Goals

1. Promoting `cass-memory` into the canonical default assistant loop.
2. Enabling `cass-memory` in IDE MCP configs.
3. Expanding the pilot beyond DX/control-plane heuristics.
4. Bulk-promoting current candidate bullets into durable shared truth.

## Active Contract

1. `cass-memory` remains pilot-only, CLI-only, and disabled by default in Fleet
   Sync.
2. `cm context` is the default read path only for:
   - explicit cross-session/cross-agent memory work
   - repeated DX/control-plane incidents with known pilot heuristics
3. `cm similar` is for wording QA and loose discoverability checks, not default
   retrieval.
4. Agents must not write directly to durable shared memory from intuition;
   candidate-first promotion remains the rule.
5. Real reuse events must be logged via:
   - a reuse-log row
   - `cm mark --helpful` or `cm mark --harmful` when applicable

## Execution Phases

### Phase 1: Runtime / Template Alignment

- Remove stale `cass-memory` MCP entries from Fleet Sync client templates.
- Keep manifest + Fleet Sync docs aligned with CLI-only / disabled-by-default.

### Phase 2: Skill + Runbook Tightening

- Update `extended/cass-memory/SKILL.md` with:
  - concise trigger conditions
  - explicit `cm context` vs `cm similar` guidance
  - explicit candidate-first write boundary
- Update the pilot quickstart with:
  - reuse-log requirement
  - `cm mark --helpful/--harmful` workflow
  - upstream-inspired agent-native harvesting guidance routed through the local
    candidate contract

### Phase 3: Baseline Regeneration

- Run `make publish-baseline`.
- Confirm generated AGENTS/baseline text stays aligned with the CLI-only pilot
  contract and contains only a small, high-signal cass trigger.

### Phase 4: Automation Replacement

- Remove the current `review-cass-pilot` daily review automation.
- Replace it with a weekly delta-based automation that checks:
  - new reuse-log rows
  - new helpful/harmful marks
  - retrieval noise only as a secondary signal
  - explicit stop recommendation if no new measured reuse appears

## Beads Structure

- Epic: `bd-n14ag` — CASS_PILOT_MEASUREMENT_AND_SCHEDULING_REPAIR
- Feature: `bd-lqyvf` — Tighten cass pilot measurement and trigger surfaces
- Task: `bd-j2kpd` — Replace cass pilot automation with delta-based review schedule
- Blocking edge: `bd-j2kpd` blocks on `bd-lqyvf`

## Validation

1. `rg` confirms no stale `cass-memory` MCP entries remain in Fleet Sync client
   templates.
2. `extended/cass-memory/SKILL.md` states the narrow trigger + candidate-first
   boundary clearly.
3. `docs/runbook/cass-memory-pilot-quickstart.md` contains:
   - explicit reuse logging
   - explicit marking guidance
   - no direct drift toward ungated durable writes
4. `make publish-baseline` completes successfully.
5. The new automation TOML reflects weekly delta review instead of daily
   generic re-checking.

## Risks

1. Over-correcting into too much baseline text would create ritualized fake
   cass usage.
2. Changing automation without changing measurement would still leave the pilot
   inconclusive.
3. Template cleanup could surface downstream assumptions if any client still
   expects `cass-memory` as MCP.

## Recommended First Task

Start with `bd-lqyvf`.

Reason: the automation should only be replaced after the pilot instructions,
template story, and measurement loop are fixed; otherwise the new schedule just
repeats the same ambiguity on a different cadence.
