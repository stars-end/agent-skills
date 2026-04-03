# CASS Memory Pilot Example Entries

These are sanitized examples for the pilot. Do not copy host-specific secrets or raw logs.

## Example 1: MCP Context EOF With Live Search Pass

- Trigger: `context` fails with empty-payload EOF while `search` still works
- Preconditions: `llm-tldr` connected in client MCP list
- Procedure:
1. Re-run the same entry via contained CLI context command.
2. If CLI passes and MCP fails, restart per-project daemon.
3. Retry MCP `context`; restart client only if transport remains stale.
- Failure signal: Both CLI and MCP fail after daemon restart.
- Reuse guidance: Use for parser/EOF-style context failures; do not use for install/auth failures.
- Sources: runtime diagnostics + pilot runbook

Summary candidate for `cm playbook add`:
> When MCP context fails with EOF but search works, verify via contained CLI, restart per-project daemon, then retry MCP; only restart client if transport is stale.

## Example 2: Fleet Audit Red With Host-Specific Drift

- Trigger: daily fleet audit reports one host red with remediation hint
- Preconditions: global audit currently mixed (green on most hosts, one failed host)
- Procedure:
1. Confirm current local daily audit payload and timestamp.
2. Run the per-host repair command from remediation hints.
3. Re-run daily audit and compare host-level statuses.
- Failure signal: host remains red with same check id after repair.
- Reuse guidance: Use only for fleet control-plane health checks, not product service outages.
- Sources: `dx-audit` payload + `dx-fleet-repair` command output

Summary candidate for `cm playbook add`:
> For single-host red fleet audits, follow remediation hint per host, then re-run daily audit and compare the same host/check id before escalating.
