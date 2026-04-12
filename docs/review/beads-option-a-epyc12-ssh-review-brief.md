# Beads Option A Review Brief

Feature-Key: bd-pj1lk
Parent Incident: bd-o8lri
Date: 2026-04-12

## Decision Under Review

Option A makes epyc12 the canonical Beads mutation host. Agents on other
canonical machines would run mutating Beads commands through Tailscale SSH,
instead of connecting their local `bd` clients directly to the epyc12 Dolt SQL
port.

Example shape:

```bash
ssh epyc12 'BEADS_DIR=$HOME/.beads-runtime/.beads bd create ...'
```

or a wrapper:

```bash
bdx create ...
bdx comments add ...
bdx dep add ...
```

## Current Problem

The current fleet model points remote clients at the central epyc12 Dolt SQL
server over Tailscale. That keeps one apparent source of truth, but high RTT
clients pay for many sequential SQL and procedure round trips per command.

Observed timings from the incident:

| Host | Link to epyc12 | Result |
| --- | --- | --- |
| epyc12 | local | fast |
| epyc6 | about 1-2 ms | fast |
| homedesktop-wsl | about 75 ms | `bd create` around 20s, edge ops around 32-48s |
| MacBook Pro | about 120 ms | simple reads 5-14s, mutations often unusable |

This is not currently classified as an epyc12 outage. It looks like RTT
amplification from using Dolt SQL server mode as a cross-VM coordination API.

## Source/Docs Findings

The refreshed Beads source and docs appear to describe:

- local embedded Dolt for local-first operation
- local Dolt SQL server mode for same-machine multi-writer/orchestrator use
- shared local server mode for multiple projects on one machine
- cross-machine distribution through Dolt push/pull or federation

They do not appear to document remote Tailscale clients talking directly to one
central Dolt SQL server as the supported low-latency coordination model.

Important source areas to inspect:

- `docs/DOLT-BACKEND.md`
- `docs/DOLT.md`
- `docs/ARCHITECTURE.md`
- `docs/FAQ.md`
- `cmd/bd/main.go`
- `cmd/bd/create.go`
- `internal/storage/dolt/store.go`
- `internal/storage/dolt/dependencies.go`
- `internal/storage/issueops/`

## Review Goals

Review Option A for:

- robustness
- speed
- agent friendliness
- skill, AGENTS.md, and script-wrapper changes
- testing and rollout gates
- low founder cognitive load
- security and Tailscale SSH failure modes
- path/cwd/source-repo correctness
- observability and incident recovery
- concurrency/race behavior with multiple agents writing on epyc12
- what else this plan misses

## Non-Goals

Do not implement the wrapper in this review.

Do not propose broad upstream Beads rewrites as the P0 path unless they are
strictly required to make Option A safe.

Do not rely on Mac-local or `/tmp/agents/...` paths as source of truth.

## Expected Output

Produce a review report with:

1. verdict: adopt, adopt with blockers, or reject
2. top risks, ordered by severity
3. required guardrails before rollout
4. wrapper behavior contract
5. AGENTS.md and skill updates required
6. test plan
7. rollout plan
8. founder cognitive-load assessment
9. open questions

