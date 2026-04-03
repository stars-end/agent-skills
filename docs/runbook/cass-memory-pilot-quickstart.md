# CASS Memory Pilot Quickstart (bd-9q92)

Use this runbook to execute the first bounded pilot slice defined in `docs/specs/2026-04-03-cass-memory-cross-vm-dx-pilot.md`.

## Scope

This pilot slice is for DX/control-plane incidents only.

In scope examples:
- MCP failure recovery
- Fleet sync breakages
- Railway deploy-truth quirks
- Beads/Dolt operational recovery

Out of scope examples:
- product behavior changes
- feature implementation memory
- raw transcript capture

## Canonical Tool Boundary

- `llm-tldr`: discovery / static analysis
- `serena`: assistant continuity / symbol-aware memory
- `cass-memory` pilot: reusable procedural playbooks across agents/VMs

Only store memory when the incident requires procedural recovery knowledge that is not already obvious from code + runbooks.

## Entry Checklist (Must Pass)

1. Incident is DX/control-plane, not product behavior.
2. You resolved or materially diagnosed the incident with validated steps.
3. Content can be sanitized (no secrets, no full logs, no credentials, no cookies).
4. The memory is reusable across sessions or hosts.

If any check fails, do not create a cass-memory entry.

## Pilot Workflow

1. Resolve incident using normal workflow.
2. Open `templates/cass-memory-pilot-entry-template.md`.
3. Write a sanitized entry and retain source references (PR URL, file paths, runbook links).
4. Store to cass-memory manually (example):

```bash
cm remember "<sanitized one-paragraph summary of the entry>"
```

5. Record a row in `templates/cass-memory-pilot-reuse-log-template.csv` (or copied log file) for each reuse event.

## Suggested Storage Pattern

- Keep rich entry bodies in repo docs for auditability.
- Store concise procedural summaries in cass-memory for retrieval speed.
- Link summaries back to repo artifacts.

## Redaction Rules

Never store:
- API keys/tokens
- auth cookies/session IDs
- raw stack traces with sensitive payloads
- full user transcripts
- 1Password material

Always store:
- trigger pattern
- preconditions
- validated steps
- failure/rollback signal
- host/runtime qualifiers
- links to supporting artifacts

## Minimal Validation (Per Session)

```bash
cm --version
cm quickstart --json
```

## End-of-Slice Output

At the end of the first slice, produce:
- count of pilot entries created
- count of reuse events
- notes on retrieval noise (high/medium/low)
- recommendation: continue or stop
