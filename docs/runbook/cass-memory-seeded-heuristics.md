# CASS Memory Seeded Heuristics

Use these as the first operator-style candidates for the `cass-memory` pilot.
They are intentionally narrow and cross-agent.

## Candidate 1: Use `op` CLI for Dev Secrets

- Category: workflow
- Scope: DX / secrets
- Rule: Use `op` CLI and the service-account flow for dev secrets and auth
  checks instead of ad hoc local env assumptions.
- Why it matters: portable across repos and agents; easy to forget; costly when
  wrong.

## Candidate 2: Prefer Z.AI Coding Endpoints First

- Category: workflow
- Scope: provider routing
- Rule: Prefer Z.AI coding endpoints first when they are available and healthy
  for the relevant coding lane.
- Why it matters: this is an operator preference with repeated cross-agent
  impact, not a code fact.

## Candidate 3: Verify Deploy Identity Before Product Signoff

- Category: debugging
- Scope: Railway / deploy truth
- Rule: Before treating a remote failure as product behavior, verify live build
  identity and expected SHA/timestamp.

## Candidate 4: MCP EOF With Search Pass Means Runtime First

- Category: debugging
- Scope: MCP / tool runtime
- Rule: If `context` fails with EOF or empty payload while `search` still
  works, investigate daemon/runtime state before concluding the tool is down.

## Candidate 5: Canonical Repos Are Read-Mostly

- Category: workflow
- Scope: repo hygiene
- Rule: Use worktrees for edits; treat dirty canonical clones as blockers to
  resolve or isolate.

## Candidate 6: Railway CLI Must Be Non-Interactive

- Category: integration
- Scope: Railway
- Rule: Prefer explicit `railway run` or fully flagged `railway link` over
  ambient linked state.

## Candidate 7: Separate Product Bugs From Control-Plane Bugs

- Category: workflow
- Scope: triage
- Rule: Label DX/control-plane failures explicitly so they do not get mistaken
  for product regressions.

## Candidate 8: Shared Memory Stores Summaries, Not Logs

- Category: documentation
- Scope: privacy
- Rule: Persist only sanitized procedural summaries into shared memory; keep raw
  evidence in PRs, docs, or local artifacts.

## Candidate 9: Use `cm context` As The Default Read Path

- Category: workflow
- Scope: cass-memory
- Rule: Default retrieval should be `cm context "<task>" --json` with
  task-shaped phrasing and `.data.relevantBullets`; use `cm similar` with
  threshold tuning only when broader search is needed.

## Candidate 10: Candidate First, Promote Later

- Category: workflow
- Scope: pilot governance
- Rule: If an agent thinks something is important, record it as a candidate
  first; promote only after reuse or explicit operator validation.
